#!/bin/bash
# Regression tests for practice-scripts/16_create_user.sh
#
# Strategy:
#   - Source the script (source guard prevents create_user from running)
#   - Mock `id` via a script placed on PATH (in a temp dir prepended to PATH)
#   - Mock `sudo` as a shell function that just executes its arguments directly
#   - Mock `useradd` via a script placed on PATH
#   - Call create_user with explicit arguments and verify exit codes / output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_SCRIPT="$PROJECT_DIR/practice-scripts/16_create_user.sh"

PASS_COUNT=0
FAIL_COUNT=0
MOCK_DIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_mocks() {
    MOCK_DIR="$(mktemp -d)"

    # Mock `id` — behaviour controlled by MOCK_ID_FAIL / MOCK_ID_QUIET
    cat > "$MOCK_DIR/id" <<'IDEOF'
#!/bin/bash
if [[ "${MOCK_ID_QUIET:-}" == "1" ]]; then
    exit "${MOCK_ID_FAIL:-0}"
fi
if [[ "${MOCK_ID_FAIL:-0}" != "0" ]]; then
    echo "id: '$*': no such user" >&2
    exit "${MOCK_ID_FAIL}"
fi
exit 0
IDEOF
    chmod +x "$MOCK_DIR/id"

    # Mock `useradd` — behaviour controlled by MOCK_USERADD_EXIT
    cat > "$MOCK_DIR/useradd" <<'UAEOF'
#!/bin/bash
exit "${MOCK_USERADD_EXIT:-0}"
UAEOF
    chmod +x "$MOCK_DIR/useradd"

    # Mock `sudo` — just runs the command directly (no privilege escalation)
    sudo() {
        "$@"
    }

    export PATH="$MOCK_DIR:$PATH"
}

cleanup_mocks() {
    unset MOCK_ID_FAIL MOCK_ID_QUIET MOCK_USERADD_EXIT TEST_USERADD_FAIL 2>/dev/null || true
    if [[ -n "$MOCK_DIR" && -d "$MOCK_DIR" ]]; then
        rm -rf "$MOCK_DIR"
    fi
    MOCK_DIR=""
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $1"
}

assert_exit_code() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        pass "$test_name (exit=$actual)"
    else
        fail "$test_name (expected exit=$expected, got exit=$actual)"
    fi
}

assert_output_contains() {
    local test_name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$test_name (output contains '$needle')"
    else
        fail "$test_name (output missing '$needle', got: '$haystack')"
    fi
}

# ---------------------------------------------------------------------------
# Source the script (source guard prevents create_user from running)
# ---------------------------------------------------------------------------
# shellcheck source=practice-scripts/16_create_user.sh
source "$TARGET_SCRIPT"

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

test_valid_user_created() {
    echo "--- test_valid_user_created ---"
    setup_mocks
    # id returns 1 (user does not exist), useradd returns 0 (success)
    export MOCK_ID_FAIL=1
    export MOCK_USERADD_EXIT=0

    local output rc=0
    output=$(create_user "testuser" 2>&1) || rc=$?

    assert_exit_code "valid user: exit code 0" 0 "$rc"
    assert_output_contains "valid user: success message" "User 'testuser' ban gaya" "$output"
    cleanup_mocks
}

test_user_already_exists() {
    echo "--- test_user_already_exists ---"
    setup_mocks
    # id returns 0 (user exists)
    export MOCK_ID_FAIL=0

    local output rc=0
    output=$(create_user "existinguser" 2>&1) || rc=$?

    assert_exit_code "existing user: exit code 1" 1 "$rc"
    assert_output_contains "existing user: already-exists message" "pehle se hai" "$output"
    cleanup_mocks
}

test_empty_username() {
    echo "--- test_empty_username ---"
    setup_mocks
    export MOCK_ID_FAIL=1  # user doesn't exist (but useradd should never be called)

    local output rc=0
    output=$(create_user "" 2>&1) || rc=$?

    assert_exit_code "empty username: exit code 2" 2 "$rc"
    assert_output_contains "empty username: error message" "khaali" "$output"
    cleanup_mocks
}

test_whitespace_username() {
    echo "--- test_whitespace_username ---"
    setup_mocks
    export MOCK_ID_FAIL=1

    local output rc=0
    output=$(create_user "   " 2>&1) || rc=$?

    assert_exit_code "whitespace username: exit code 2" 2 "$rc"
    assert_output_contains "whitespace username: error message" "khaali" "$output"
    cleanup_mocks
}

test_illegal_username_uppercase() {
    echo "--- test_illegal_username_uppercase ---"
    setup_mocks
    export MOCK_ID_FAIL=1

    local output rc=0
    output=$(create_user "TestUser" 2>&1) || rc=$?

    assert_exit_code "uppercase username: exit code 2" 2 "$rc"
    assert_output_contains "uppercase username: invalid chars message" "invalid characters" "$output"
    cleanup_mocks
}

test_illegal_username_starts_with_digit() {
    echo "--- test_illegal_username_starts_with_digit ---"
    setup_mocks
    export MOCK_ID_FAIL=1

    local output rc=0
    output=$(create_user "9badname" 2>&1) || rc=$?

    assert_exit_code "digit-start username: exit code 2" 2 "$rc"
    assert_output_contains "digit-start username: invalid chars message" "invalid characters" "$output"
    cleanup_mocks
}

test_illegal_username_special_chars() {
    echo "--- test_illegal_username_special_chars ---"
    setup_mocks
    export MOCK_ID_FAIL=1

    local output rc=0
    output=$(create_user "user@name!" 2>&1) || rc=$?

    assert_exit_code "special-chars username: exit code 2" 2 "$rc"
    assert_output_contains "special-chars username: invalid chars message" "invalid characters" "$output"
    cleanup_mocks
}

test_username_too_long() {
    echo "--- test_username_too_long ---"
    setup_mocks
    export MOCK_ID_FAIL=1

    # 33 chars — over the 32-char Linux limit
    local long_name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    local output rc=0
    output=$(create_user "$long_name" 2>&1) || rc=$?

    assert_exit_code "too-long username: exit code 2" 2 "$rc"
    assert_output_contains "too-long username: length message" "32 characters" "$output"
    cleanup_mocks
}

test_useradd_failure() {
    echo "--- test_useradd_failure ---"
    setup_mocks
    export MOCK_ID_FAIL=1          # user doesn't exist
    export MOCK_USERADD_EXIT=1     # useradd fails

    local output rc=0
    output=$(create_user "failuser" 2>&1) || rc=$?

    assert_exit_code "useradd failure: exit code 3" 3 "$rc"
    assert_output_contains "useradd failure: error message" "Useradd fail ho gaya" "$output"
    cleanup_mocks
}

test_useradd_failure_nonzero_propagated() {
    echo "--- test_useradd_failure_nonzero_propagated ---"
    setup_mocks
    export MOCK_ID_FAIL=1
    export MOCK_USERADD_EXIT=7     # a non-standard failure code

    local output rc=0
    output=$(create_user "failuser7" 2>&1) || rc=$?

    assert_exit_code "useradd failure (rc=7): exit code 3" 3 "$rc"
    assert_output_contains "useradd failure (rc=7): mentions exit code" "exit code: 7" "$output"
    cleanup_mocks
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------

test_valid_user_created
test_user_already_exists
test_empty_username
test_whitespace_username
test_illegal_username_uppercase
test_illegal_username_starts_with_digit
test_illegal_username_special_chars
test_username_too_long
test_useradd_failure
test_useradd_failure_nonzero_propagated

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "===================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "===================================="

if [[ $FAIL_COUNT -ne 0 ]]; then
    exit 1
fi
