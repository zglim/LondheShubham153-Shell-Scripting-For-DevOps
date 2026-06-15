#!/bin/bash
# Minimal regression tests for 16_create_user.sh
#
# Hum script ko `source` karte hain (interactive read trigger nahi hota kyunki
# script me BASH_SOURCE/$0 guard hai), phir `user_exists` aur `run_useradd` ko
# mock karke har branch ka exit code + useradd call hua ya nahi verify karte hain.
# Koi real `id` / `sudo useradd` yahan nahi chalta.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/16_create_user.sh"

# shellcheck source=/dev/null
source "$TARGET"

TMP_T="$(mktemp -d)"
trap 'rm -rf "$TMP_T"' EXIT
MARKER="$TMP_T/useradd_called"

fail=0

check_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $name (exit=$actual)"
    else
        echo "FAIL: $name (expected exit=$expected, got=$actual)"
        fail=1
    fi
}

assert_useradd_called() {
    local name="$1"
    if [[ -f "$MARKER" ]]; then
        echo "PASS: $name (useradd was called)"
    else
        echo "FAIL: $name (useradd was NOT called)"
        fail=1
    fi
}

assert_useradd_not_called() {
    local name="$1"
    if [[ ! -f "$MARKER" ]]; then
        echo "PASS: $name (useradd correctly skipped)"
    else
        echo "FAIL: $name (useradd should NOT have been called)"
        fail=1
    fi
}

# ---- Case 1: legal new username -> success (exit 0), useradd called ----
user_exists() { return 1; }                     # user does NOT exist
run_useradd() { touch "$MARKER"; return 0; }     # creation succeeds
rm -f "$MARKER"
create_user <<< "alice" >/dev/null 2>&1
check_exit "valid new user creates successfully" 0 $?
assert_useradd_called "valid new user"

# ---- Case 2: existing user -> stable block (exit 1), useradd NOT called ----
user_exists() { return 0; }                     # user EXISTS
run_useradd() { touch "$MARKER"; return 0; }
rm -f "$MARKER"
create_user <<< "bob" >/dev/null 2>&1
check_exit "existing user is blocked" 1 $?
assert_useradd_not_called "existing user"

# ---- Case 3: empty username -> exit 2, useradd NOT called ----
user_exists() { return 1; }
run_useradd() { touch "$MARKER"; return 0; }
rm -f "$MARKER"
create_user <<< "" >/dev/null 2>&1
check_exit "empty username rejected" 2 $?
assert_useradd_not_called "empty username"

# ---- Case 4: whitespace-only username -> exit 2, useradd NOT called ----
rm -f "$MARKER"
create_user <<< "   " >/dev/null 2>&1
check_exit "whitespace-only username rejected" 2 $?
assert_useradd_not_called "whitespace-only username"

# ---- Case 5: invalid username format -> exit 3, useradd NOT called ----
rm -f "$MARKER"
create_user <<< "1Bad Name!" >/dev/null 2>&1
check_exit "invalid username rejected" 3 $?
assert_useradd_not_called "invalid username"

# ---- Case 6: useradd/sudo execution failure -> non-zero (exit 4) ----
user_exists() { return 1; }
run_useradd() { return 8; }                      # simulate sudo/useradd failure
create_user <<< "charlie" >/dev/null 2>&1
rc=$?
check_exit "useradd failure maps to code 4" 4 "$rc"
if [[ "$rc" -ne 0 ]]; then
    echo "PASS: failure path returns non-zero status"
else
    echo "FAIL: failure path returned success status"
    fail=1
fi

echo "----------------------------------------"
if [[ $fail -eq 0 ]]; then
    echo "ALL TESTS PASSED"
    exit 0
fi
echo "SOME TESTS FAILED"
exit 1
