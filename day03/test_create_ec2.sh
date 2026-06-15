#!/bin/bash
#
# Minimal regression tests for create_ec2.sh.
#
# These tests source create_ec2.sh (the source-guard keeps main() from running)
# and exercise the individual functions with a mocked `aws` command, so nothing
# touches real AWS. Run with: bash day03/test_create_ec2.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/create_ec2.sh"

# The script enables `set -euo pipefail`; relax it here so the harness can
# inspect non-zero return codes without aborting. The functions under test use
# explicit `return`s, so their behavior does not depend on these options.
set +e +u +o pipefail

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "FAIL: $1"; FAIL=$(( FAIL + 1 )); }

check() {
    # check <description> <actual> <expected>
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1 (expected '$3', got '$2')"
    fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "== check_awscli does not exit early when aws is missing =="
# With an empty PATH the `aws` binary cannot be found. The fix means
# check_awscli must RETURN 1 (not call `exit`), so the subshell survives.
( PATH=""; check_awscli ); rc=$?
check "check_awscli returns 1 when aws is absent" "$rc" "1"

echo
echo "== ensure_awscli three-state matrix =="
# Already installed: check succeeds -> install must NOT be attempted.
(
    INSTALL_LOG="$TMPDIR_TEST/install_a.log"; : > "$INSTALL_LOG"
    check_awscli() { return 0; }
    install_awscli() { echo called >> "$INSTALL_LOG"; return 0; }
    ensure_awscli
); rc=$?
check "ensure_awscli returns 0 when already installed" "$rc" "0"
check "install not attempted when already installed" "$(cat "$TMPDIR_TEST/install_a.log" 2>/dev/null)" ""

# Missing aws + install succeeds -> install IS attempted, ensure returns 0.
(
    INSTALL_LOG="$TMPDIR_TEST/install_b.log"; : > "$INSTALL_LOG"
    check_awscli() { return 1; }
    install_awscli() { echo called >> "$INSTALL_LOG"; return 0; }
    ensure_awscli
); rc=$?
check "ensure_awscli returns 0 when install succeeds" "$rc" "0"
check "install branch entered when aws missing" "$(cat "$TMPDIR_TEST/install_b.log" 2>/dev/null)" "called"

# Missing aws + install fails -> ensure surfaces failure (return 1).
(
    check_awscli() { return 1; }
    install_awscli() { return 1; }
    ensure_awscli
); rc=$?
check "ensure_awscli returns 1 when install fails" "$rc" "1"

echo
echo "== create_ec2_instance validates params before calling AWS =="
# Mock aws to record any invocation; with a missing AMI_ID it must never run.
(
    AWS_LOG="$TMPDIR_TEST/aws_missing.log"; : > "$AWS_LOG"
    aws() { echo "$*" >> "$AWS_LOG"; }
    create_ec2_instance "" "t2.micro" "my-key" "subnet-123" "sg-123" "demo"
); rc=$?
check "create fails (rc=1) when AMI_ID is empty" "$rc" "1"
check "aws never called when a required param is missing" \
    "$(cat "$TMPDIR_TEST/aws_missing.log" 2>/dev/null)" ""

# All params present + run-instances returns an ID + wait sees running -> success.
(
    aws() {
        case "$1 $2" in
            "ec2 run-instances") echo "i-0123456789abcdef0" ;;
            "ec2 describe-instances") echo "running" ;;
        esac
    }
    WAIT_INTERVAL=0 WAIT_MAX_ATTEMPTS=3 \
        create_ec2_instance "ami-123" "t2.micro" "my-key" "subnet-123" "sg-123" "demo"
); rc=$?
check "create succeeds (rc=0) when params valid and instance runs" "$rc" "0"

echo
echo "== wait_for_instance success and bounded-exit scenarios =="
# Success: instance reports running immediately.
(
    aws() { echo "running"; }
    WAIT_INTERVAL=0 WAIT_MAX_ATTEMPTS=3 wait_for_instance "i-success"
); rc=$?
check "wait returns 0 when instance is running" "$rc" "0"

# Timeout: instance is stuck pending; must give up (and quickly) instead of hanging.
(
    aws() { echo "pending"; }
    WAIT_INTERVAL=0 WAIT_MAX_ATTEMPTS=3 wait_for_instance "i-stuck"
); rc=$?
check "wait returns 1 on timeout (stuck pending)" "$rc" "1"

# Repeated query failures (e.g. bad id / permissions): must abort, not loop forever.
(
    aws() { return 1; }
    WAIT_INTERVAL=0 WAIT_MAX_ATTEMPTS=10 WAIT_MAX_FAILURES=2 wait_for_instance "i-bad"
); rc=$?
check "wait returns 1 after repeated query failures" "$rc" "1"

# Terminal state: instance went to a dead state; must error out immediately.
(
    aws() { echo "terminated"; }
    WAIT_INTERVAL=0 WAIT_MAX_ATTEMPTS=5 wait_for_instance "i-dead"
); rc=$?
check "wait returns 1 when instance enters terminal state" "$rc" "1"

echo
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
echo "==============================="
[[ "$FAIL" -eq 0 ]]
