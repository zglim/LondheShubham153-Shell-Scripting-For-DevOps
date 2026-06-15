#!/bin/bash
set -euo pipefail

# Returns 0 when the AWS CLI is available, 1 otherwise.
# It must NOT exit, so callers can decide whether to install.
check_awscli() {
    if command -v aws &> /dev/null; then
        return 0
    fi
    return 1
}

# Installs AWS CLI v2 on Linux.
# Returns 0 only when the `aws` binary is actually available afterwards,
# non-zero on any failure, so callers can distinguish success from failure.
install_awscli() {
    echo "Installing AWS CLI v2 on Linux..." >&2
    local tmp_zip="awscliv2.zip"

    if ! curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp_zip"; then
        echo "Error: failed to download AWS CLI installer." >&2
        rm -rf "$tmp_zip" ./aws
        return 1
    fi

    # unzip may already be present; treat its install as best-effort.
    sudo apt-get install -y unzip &> /dev/null || true

    if ! unzip -q "$tmp_zip"; then
        echo "Error: failed to unzip AWS CLI installer." >&2
        rm -rf "$tmp_zip" ./aws
        return 1
    fi

    if ! sudo ./aws/install; then
        echo "Error: AWS CLI install command failed." >&2
        rm -rf "$tmp_zip" ./aws
        return 1
    fi

    rm -rf "$tmp_zip" ./aws

    # Confirm the binary is actually usable before reporting success.
    if command -v aws &> /dev/null; then
        aws --version >&2 || true
        return 0
    fi

    echo "Error: AWS CLI not found after installation." >&2
    return 1
}

# Ensures the AWS CLI is present, installing it if needed.
# Cleanly separates the three states for the main flow:
#   - already installed  -> return 0 (no install attempted)
#   - install succeeded   -> return 0
#   - install failed      -> return 1
ensure_awscli() {
    if check_awscli; then
        return 0
    fi

    echo "AWS CLI not found. Attempting to install it..." >&2
    if install_awscli; then
        echo "AWS CLI installed successfully." >&2
        return 0
    fi

    echo "Error: AWS CLI installation failed." >&2
    return 1
}

# Waits for an instance to reach the running state.
# Bounded by a maximum number of attempts and a cap on consecutive query
# failures, so it can never loop forever on bad params, permission errors,
# or terminal instance states. Intervals/limits are overridable via env vars
# (primarily to keep tests fast).
wait_for_instance() {
    local instance_id="$1"
    local max_attempts="${WAIT_MAX_ATTEMPTS:-30}"
    local interval="${WAIT_INTERVAL:-10}"
    local max_failures="${WAIT_MAX_FAILURES:-5}"
    local attempt=0
    local failures=0
    local state=""

    echo "Waiting for instance $instance_id to be in running state..."

    while (( attempt < max_attempts )); do
        attempt=$(( attempt + 1 ))

        if ! state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2> /dev/null); then
            failures=$(( failures + 1 ))
            echo "Warning: failed to query instance state (attempt ${attempt}, failure ${failures}/${max_failures})." >&2
            if (( failures >= max_failures )); then
                echo "Error: repeated failures querying instance ${instance_id}. Aborting." >&2
                return 1
            fi
            sleep "$interval"
            continue
        fi

        # A successful query resets the consecutive-failure counter.
        failures=0

        case "$state" in
            running)
                echo "Instance $instance_id is now running."
                return 0
                ;;
            pending)
                echo "Instance $instance_id is pending (attempt ${attempt}/${max_attempts})."
                ;;
            terminated|shutting-down|stopping|stopped)
                echo "Error: instance ${instance_id} entered terminal state '${state}'." >&2
                return 1
                ;;
            *)
                echo "Instance $instance_id state: '${state}' (attempt ${attempt}/${max_attempts})."
                ;;
        esac

        sleep "$interval"
    done

    echo "Error: timed out waiting for instance ${instance_id} to reach running state after ${max_attempts} attempts." >&2
    return 1
}

# Creates an EC2 instance. Validates required parameters BEFORE calling AWS,
# fails fast on missing values, and only proceeds to wait on a confirmed
# successful run-instances result.
create_ec2_instance() {
    local ami_id="$1"
    local instance_type="$2"
    local key_name="$3"
    local subnet_id="$4"
    local security_group_ids="$5"
    local instance_name="$6"

    # Validate required parameters before touching AWS. Each `[[ -n ]] || ...`
    # line always returns 0, so it is safe under `set -e`.
    local missing=()
    [[ -n "$ami_id" ]] || missing+=("AMI_ID")
    [[ -n "$instance_type" ]] || missing+=("INSTANCE_TYPE")
    [[ -n "$key_name" ]] || missing+=("KEY_NAME")
    [[ -n "$subnet_id" ]] || missing+=("SUBNET_ID")
    [[ -n "$security_group_ids" ]] || missing+=("SECURITY_GROUP_IDS")

    if (( ${#missing[@]} > 0 )); then
        echo "Error: missing required parameter(s): ${missing[*]}." >&2
        echo "Set these values before running the script." >&2
        return 1
    fi

    echo "Creating EC2 instance..."

    local instance_id
    if ! instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --key-name "$key_name" \
        --subnet-id "$subnet_id" \
        --security-group-ids "$security_group_ids" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" \
        --query 'Instances[0].InstanceId' \
        --output text); then
        echo "Error: 'aws ec2 run-instances' failed." >&2
        return 1
    fi

    if [[ -z "$instance_id" || "$instance_id" == "None" ]]; then
        echo "Error: failed to obtain a valid instance ID from AWS." >&2
        return 1
    fi

    echo "Instance $instance_id created successfully."

    # Wait on the same successful result; a failed create never reaches here.
    wait_for_instance "$instance_id"
}

main() {
    if ! ensure_awscli; then
        exit 1
    fi

    # Specify the parameters for creating the EC2 instance.
    # These are intentionally left blank placeholders; create_ec2_instance
    # will fail fast (before calling AWS) until they are filled in.
    local AMI_ID=""
    local INSTANCE_TYPE="t2.micro"
    local KEY_NAME=""
    local SUBNET_ID=""
    local SECURITY_GROUP_IDS=""  # Add your security group IDs separated by space
    local INSTANCE_NAME="Shell-Script-EC2-Demo"

    if ! create_ec2_instance "$AMI_ID" "$INSTANCE_TYPE" "$KEY_NAME" "$SUBNET_ID" "$SECURITY_GROUP_IDS" "$INSTANCE_NAME"; then
        echo "EC2 instance creation failed." >&2
        exit 1
    fi

    echo "EC2 instance creation completed."
}

# Only auto-run when executed directly, so the functions can be sourced
# (e.g. by the regression tests) without triggering a real provisioning run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
