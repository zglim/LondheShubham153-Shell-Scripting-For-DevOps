#!/bin/bash
# Regression tests for day03/create_ec2.sh
# Usage: bash day03/test_create_ec2.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/create_ec2.sh"

PASS=0
FAIL=0

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

# Source only the function definitions (main is guarded by BASH_SOURCE check)
source_functions() {
    source "$SCRIPT_PATH"
}

pass() { (( PASS++ )) || true; echo "  PASS: $1"; }
fail() { (( FAIL++ )) || true; echo "  FAIL: $1" >&2; }

# ------------------------------------------------------------------
# Test 1: check_awscli returns 1 (not exit) when aws is missing
# ------------------------------------------------------------------
test_check_awscli_missing() {
    echo "[Test 1] check_awscli returns 1 when aws is not on PATH"
    (
        source_functions

        # Empty PATH so 'aws' cannot be found
        PATH=""
        if check_awscli 2>/dev/null; then
            exit 10  # unexpected success
        else
            rc=$?
            # Should return 1, not call exit (subshell would exit with that code)
            [[ $rc -eq 1 ]] && exit 0 || exit 11
        fi
    )
    local rc=$?
    if [[ $rc -eq 0 ]]; then pass "check_awscli returned 1 without exiting"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 2: check_awscli returns 0 when aws is present
# ------------------------------------------------------------------
test_check_awscli_present() {
    echo "[Test 2] check_awscli returns 0 when aws is on PATH"
    (
        source_functions

        # Create a mock aws binary
        local mock_dir
        mock_dir="$(mktemp -d)"
        cat > "$mock_dir/aws" <<'MOCK'
#!/bin/bash
echo "aws-cli/2.0.0 mock"
MOCK
        chmod +x "$mock_dir/aws"
        PATH="$mock_dir:$PATH"

        check_awscli >/dev/null 2>&1
        rc=$?
        rm -rf "$mock_dir"
        exit $rc
    )
    local rc=$?
    if [[ $rc -eq 0 ]]; then pass "check_awscli returned 0 for present aws"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 3: ensure_awscli enters install branch when aws is missing
# ------------------------------------------------------------------
test_ensure_awscli_enters_install() {
    echo "[Test 3] ensure_awscli enters install_awscli when aws is missing"
    (
        source_functions

        # Override check_awscli to simulate missing aws
        check_awscli() { return 1; }

        # Override install_awscli to record it was called and succeed
        install_awscli() { echo "INSTALL_CALLED"; return 0; }

        output=$(ensure_awscli 2>&1)
        rc=$?
        if [[ $rc -eq 0 && "$output" == *"INSTALL_CALLED"* ]]; then
            exit 0
        else
            exit 1
        fi
    )
    local rc=$?
    if [[ $rc -eq 0 ]]; then pass "install branch was entered and succeeded"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 4: ensure_awscli returns 1 when install fails
# ------------------------------------------------------------------
test_ensure_awscli_install_fails() {
    echo "[Test 4] ensure_awscli returns 1 when install_awscli fails"
    (
        source_functions
        check_awscli() { return 1; }
        install_awscli() { return 1; }

        ensure_awscli >/dev/null 2>&1
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 1 ]]; then pass "ensure_awscli returned 1 on install failure"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 5: validate_params fails on empty required params
# ------------------------------------------------------------------
test_validate_params_empty() {
    echo "[Test 5] validate_params returns 1 when params are empty"
    (
        source_functions
        validate_params "" "key" "" "" 2>/dev/null
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 1 ]]; then pass "validate_params returned 1 for missing params"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 6: validate_params succeeds when all required params present
# ------------------------------------------------------------------
test_validate_params_complete() {
    echo "[Test 6] validate_params returns 0 when all params are set"
    (
        source_functions
        validate_params "ami-123" "mykey" "subnet-abc" "sg-001" >/dev/null 2>&1
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 0 ]]; then pass "validate_params returned 0 for complete params"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 7: create_ec2_instance aborts before calling aws when params missing
# ------------------------------------------------------------------
test_create_ec2_aborts_on_bad_params() {
    echo "[Test 7] create_ec2_instance fails early on missing params"
    (
        source_functions

        # Ensure aws is never called — override it to fail loudly
        aws() { echo "AWS_SHOULD_NOT_BE_CALLED" >&2; exit 99; }

        create_ec2_instance "" "t2.micro" "" "" "" "test" 2>/dev/null
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 1 ]]; then pass "create_ec2_instance aborted before aws call"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 8: wait_for_instance returns 0 when instance reaches running
# ------------------------------------------------------------------
test_wait_running() {
    echo "[Test 8] wait_for_instance returns 0 on 'running' state"
    (
        source_functions

        # Mock aws to return 'running'
        aws() {
            if [[ "$*" == *"describe-instances"* ]]; then
                echo "running"
            fi
        }

        WAIT_TIMEOUT_SECONDS=30
        WAIT_POLL_INTERVAL=0
        wait_for_instance "i-test123" >/dev/null 2>&1
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 0 ]]; then pass "wait_for_instance returned 0 for running"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 9: wait_for_instance returns 1 on timeout
# ------------------------------------------------------------------
test_wait_timeout() {
    echo "[Test 9] wait_for_instance returns 1 on timeout"
    (
        source_functions

        # Mock aws to always return 'pending'
        aws() {
            if [[ "$*" == *"describe-instances"* ]]; then
                echo "pending"
            fi
        }

        WAIT_TIMEOUT_SECONDS=1
        WAIT_POLL_INTERVAL=1
        wait_for_instance "i-test123" >/dev/null 2>&1
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 1 ]]; then pass "wait_for_instance returned 1 on timeout"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 10: wait_for_instance returns 1 on consecutive query failures
# ------------------------------------------------------------------
test_wait_query_failures() {
    echo "[Test 10] wait_for_instance returns 1 after consecutive query failures"
    (
        source_functions

        # Mock aws to always fail
        aws() {
            if [[ "$*" == *"describe-instances"* ]]; then
                echo "error" >&2
                return 1
            fi
        }

        WAIT_TIMEOUT_SECONDS=60
        WAIT_POLL_INTERVAL=0
        WAIT_MAX_CONSECUTIVE_FAILURES=3
        wait_for_instance "i-test123" >/dev/null 2>&1
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 1 ]]; then pass "wait_for_instance returned 1 on consecutive failures"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Test 11: wait_for_instance returns 1 on terminated state
# ------------------------------------------------------------------
test_wait_terminated() {
    echo "[Test 11] wait_for_instance returns 1 on 'terminated' state"
    (
        source_functions

        aws() {
            if [[ "$*" == *"describe-instances"* ]]; then
                echo "terminated"
            fi
        }

        WAIT_TIMEOUT_SECONDS=30
        WAIT_POLL_INTERVAL=0
        wait_for_instance "i-test123" >/dev/null 2>&1
        exit $?
    )
    local rc=$?
    if [[ $rc -eq 1 ]]; then pass "wait_for_instance returned 1 on terminated"; else fail "rc=$rc"; fi
}

# ------------------------------------------------------------------
# Run all tests
# ------------------------------------------------------------------
echo "========================================="
echo " Running regression tests for create_ec2"
echo "========================================="

test_check_awscli_missing
test_check_awscli_present
test_ensure_awscli_enters_install
test_ensure_awscli_install_fails
test_validate_params_empty
test_validate_params_complete
test_create_ec2_aborts_on_bad_params
test_wait_running
test_wait_timeout
test_wait_query_failures
test_wait_terminated

echo "========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
