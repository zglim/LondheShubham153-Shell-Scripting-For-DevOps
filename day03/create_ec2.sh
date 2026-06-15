#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------------
# AWS CLI check & install
# ------------------------------------------------------------------

check_awscli() {
    # Returns 0 if aws is already installed, 1 otherwise.
    # Does NOT exit the script — caller decides what to do.
    if command -v aws &> /dev/null; then
        echo "AWS CLI is already installed: $(aws --version 2>&1)"
        return 0
    else
        echo "AWS CLI is not installed." >&2
        return 1
    fi
}

install_awscli() {
    # Attempts to install AWS CLI v2 on Linux.
    # Returns 0 on success, 1 on failure.
    echo "Installing AWS CLI v2 on Linux..."

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN

    if ! curl -sf "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
            -o "$tmp_dir/awscliv2.zip"; then
        echo "ERROR: Failed to download AWS CLI." >&2
        return 1
    fi

    if ! sudo apt-get install -y unzip &> /dev/null; then
        echo "ERROR: Failed to install unzip." >&2
        return 1
    fi

    if ! unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"; then
        echo "ERROR: Failed to extract AWS CLI archive." >&2
        return 1
    fi

    if ! sudo "$tmp_dir/aws/install"; then
        echo "ERROR: AWS CLI installation failed." >&2
        return 1
    fi

    if ! aws --version &> /dev/null; then
        echo "ERROR: AWS CLI installed but verification failed." >&2
        return 1
    fi

    echo "AWS CLI installed successfully."
    return 0
}

ensure_awscli() {
    # Orchestrates check → install with three distinct outcomes:
    #   0 = aws is ready (already present or freshly installed)
    #   1 = aws is not available and installation failed
    if check_awscli; then
        return 0
    fi

    echo "Attempting automatic installation..."
    if install_awscli; then
        return 0
    else
        echo "ERROR: AWS CLI is not available and could not be installed." >&2
        return 1
    fi
}

# ------------------------------------------------------------------
# Parameter validation
# ------------------------------------------------------------------

validate_params() {
    # Validates that all required EC2 creation parameters are non-empty.
    # Prints a clear message for each missing value and returns 1 if any
    # are missing, 0 if all are present.
    local ami_id="$1"
    local key_name="$2"
    local subnet_id="$3"
    local security_group_ids="$4"

    local missing=()

    if [[ -z "$ami_id" ]]; then
        missing+=("AMI_ID")
    fi
    if [[ -z "$key_name" ]]; then
        missing+=("KEY_NAME")
    fi
    if [[ -z "$subnet_id" ]]; then
        missing+=("SUBNET_ID")
    fi
    if [[ -z "$security_group_ids" ]]; then
        missing+=("SECURITY_GROUP_IDS")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: The following required parameters are empty:" >&2
        for p in "${missing[@]}"; do
            echo "  - $p" >&2
        done
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------
# Wait for instance
# ------------------------------------------------------------------

# Configurable limits (can be overridden via environment variables)
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"
WAIT_POLL_INTERVAL="${WAIT_POLL_INTERVAL:-10}"
WAIT_MAX_CONSECUTIVE_FAILURES="${WAIT_MAX_CONSECUTIVE_FAILURES:-3}"

wait_for_instance() {
    local instance_id="$1"
    echo "Waiting for instance $instance_id to reach 'running' state " \
         "(timeout: ${WAIT_TIMEOUT_SECONDS}s)..."

    local elapsed=0
    local consecutive_failures=0

    while (( elapsed < WAIT_TIMEOUT_SECONDS )); do
        local state
        if state=$(aws ec2 describe-instances \
                    --instance-ids "$instance_id" \
                    --query 'Reservations[0].Instances[0].State.Name' \
                    --output text 2>&1); then
            consecutive_failures=0  # reset on any successful query
            case "$state" in
                running)
                    echo "Instance $instance_id is now running."
                    return 0
                    ;;
                terminated|shutting-down)
                    echo "ERROR: Instance $instance_id entered unexpected state: $state" >&2
                    return 1
                    ;;
                pending)
                    : # keep waiting
                    ;;
                *)
                    echo "WARNING: Instance $instance_id in state '$state', continuing to wait..." >&2
                    ;;
            esac
        else
            (( consecutive_failures++ )) || true
            echo "WARNING: describe-instances query failed (attempt $consecutive_failures/$WAIT_MAX_CONSECUTIVE_FAILURES)." >&2
            if (( consecutive_failures >= WAIT_MAX_CONSECUTIVE_FAILURES )); then
                echo "ERROR: Too many consecutive query failures for instance $instance_id." >&2
                return 1
            fi
        fi

        sleep "$WAIT_POLL_INTERVAL"
        (( elapsed += WAIT_POLL_INTERVAL )) || true
    done

    echo "ERROR: Timed out after ${WAIT_TIMEOUT_SECONDS}s waiting for instance $instance_id." >&2
    return 1
}

# ------------------------------------------------------------------
# Create EC2 instance
# ------------------------------------------------------------------

create_ec2_instance() {
    local ami_id="$1"
    local instance_type="$2"
    local key_name="$3"
    local subnet_id="$4"
    local security_group_ids="$5"
    local instance_name="$6"

    # Validate required parameters before any AWS call
    if ! validate_params "$ami_id" "$key_name" "$subnet_id" "$security_group_ids"; then
        echo "ERROR: Aborting EC2 creation due to missing parameters." >&2
        return 1
    fi

    echo "Launching EC2 instance (ami=$ami_id, type=$instance_type, key=$key_name)..."

    local instance_id
    if ! instance_id=$(aws ec2 run-instances \
            --image-id "$ami_id" \
            --instance-type "$instance_type" \
            --key-name "$key_name" \
            --subnet-id "$subnet_id" \
            --security-group-ids "$security_group_ids" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" \
            --query 'Instances[0].InstanceId' \
            --output text 2>&1); then
        echo "ERROR: aws ec2 run-instances failed:" >&2
        echo "$instance_id" >&2
        return 1
    fi

    if [[ -z "$instance_id" || "$instance_id" == "None" ]]; then
        echo "ERROR: run-instances returned no instance ID." >&2
        return 1
    fi

    echo "Instance $instance_id created successfully."

    # Wait only when we have a valid instance ID from a successful launch
    if ! wait_for_instance "$instance_id"; then
        echo "ERROR: Instance $instance_id did not reach running state." >&2
        return 1
    fi

    return 0
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

main() {
    # Ensure AWS CLI is available (check → install → fail-fast)
    if ! ensure_awscli; then
        echo "FATAL: Cannot proceed without AWS CLI." >&2
        exit 1
    fi

    echo "Creating EC2 instance..."

    # Specify the parameters for creating the EC2 instance
    AMI_ID="${AMI_ID:-}"
    INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
    KEY_NAME="${KEY_NAME:-}"
    SUBNET_ID="${SUBNET_ID:-}"
    SECURITY_GROUP_IDS="${SECURITY_GROUP_IDS:-}"  # Add your security group IDs separated by space
    INSTANCE_NAME="${INSTANCE_NAME:-Shell-Script-EC2-Demo}"

    # Call the function to create the EC2 instance
    if ! create_ec2_instance "$AMI_ID" "$INSTANCE_TYPE" "$KEY_NAME" \
                             "$SUBNET_ID" "$SECURITY_GROUP_IDS" "$INSTANCE_NAME"; then
        echo "FATAL: EC2 instance creation failed." >&2
        exit 1
    fi

    echo "EC2 instance creation completed."
}

# Only run main() when executed directly, not when sourced by tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
