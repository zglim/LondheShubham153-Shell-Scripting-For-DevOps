#!/bin/bash
# Regression tests for source path fix and side-effect isolation
# Run: bash tests/test_source_fix.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRACTICE_DIR="${PROJECT_ROOT}/practice-scripts"
SCRIPT_14="${PRACTICE_DIR}/14_function_with_args.sh"
SCRIPT_15="${PRACTICE_DIR}/15_source_and_call.sh"

PASS=0
FAIL=0

pass() { echo "✓ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "✗ FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

# ---------- Test 1: Script 15 from repo root ----------
echo "=== Test 1: Run script 15 from repo root ==="
OUTPUT=$(cd "${PROJECT_ROOT}" && bash practice-scripts/15_source_and_call.sh 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
    fail "Script 15 exited with code $RC when run from repo root"
elif echo "${OUTPUT}" | grep -q "Namaste popatlal" && echo "${OUTPUT}" | grep -q "Installing: docker"; then
    pass "Script 15 runs from repo root and calls greet + install_package"
else
    fail "Script 15 output missing expected calls (from repo root)"
fi

# Must NOT contain demo output from script 14
if echo "${OUTPUT}" | grep -q "jethalal\|babita\|nginx"; then
    fail "Script 15 leaked demo output from script 14 (jethalal/babita/nginx)"
else
    pass "Script 15 does NOT leak demo output from script 14"
fi

# ---------- Test 2: Script 15 from practice-scripts/ ----------
echo "=== Test 2: Run script 15 from practice-scripts/ ==="
OUTPUT=$(cd "${PRACTICE_DIR}" && bash 15_source_and_call.sh 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
    fail "Script 15 exited with code $RC when run from practice-scripts/"
elif echo "${OUTPUT}" | grep -q "Namaste popatlal" && echo "${OUTPUT}" | grep -q "Installing: docker"; then
    pass "Script 15 runs from practice-scripts/ and calls greet + install_package"
else
    fail "Script 15 output missing expected calls (from practice-scripts/)"
fi

# ---------- Test 3: Script 15 from an arbitrary directory ----------
echo "=== Test 3: Run script 15 from /tmp (arbitrary directory) ==="
OUTPUT=$(cd /tmp && bash "${SCRIPT_15}" 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
    fail "Script 15 exited with code $RC when run from /tmp"
elif echo "${OUTPUT}" | grep -q "Namaste popatlal" && echo "${OUTPUT}" | grep -q "Installing: docker"; then
    pass "Script 15 runs from /tmp and calls greet + install_package"
else
    fail "Script 15 output missing expected calls (from /tmp)"
fi

# ---------- Test 4: Script 14 direct execution retains demo output ----------
echo "=== Test 4: Script 14 direct execution retains demo output ==="
OUTPUT=$(bash "${SCRIPT_14}" 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
    fail "Script 14 exited with code $RC"
elif echo "${OUTPUT}" | grep -q "Namaste jethalal" && \
     echo "${OUTPUT}" | grep -q "Namaste babita" && \
     echo "${OUTPUT}" | grep -q "Installing: nginx"; then
    pass "Script 14 direct execution shows all demo output"
else
    fail "Script 14 direct execution missing demo output (jethalal/babita/nginx)"
fi

# ---------- Test 5: Sourcing script 14 does NOT trigger demo output ----------
echo "=== Test 5: Sourcing script 14 does NOT trigger demo output ==="
OUTPUT=$(bash -c "source '${SCRIPT_14}'; echo 'source_test_marker_ok'" 2>&1)
if echo "${OUTPUT}" | grep -q "jethalal\|babita\|nginx"; then
    fail "Sourcing script 14 triggered demo output (should be silent)"
else
    pass "Sourcing script 14 does NOT trigger demo output"
fi

# Verify functions are available after sourcing
if echo "${OUTPUT}" | grep -q "source_test_marker_ok"; then
    pass "Functions loaded successfully after sourcing script 14"
else
    fail "Something went wrong when sourcing script 14"
fi

# ---------- Test 6: Script 15 fails gracefully if target script missing ----------
echo "=== Test 6: Script 15 fails gracefully if target script is missing ==="
TMPDIR_TEST=$(mktemp -d)
cp "${SCRIPT_15}" "${TMPDIR_TEST}/"
OUTPUT=$(cd "${TMPDIR_TEST}" && bash 15_source_and_call.sh 2>&1) || true
RC=$?
if echo "${OUTPUT}" | grep -qi "error.*not found\|error.*no such"; then
    pass "Script 15 reports clear error when target script is missing"
else
    fail "Script 15 did not report clear error for missing target script"
fi
rm -rf "${TMPDIR_TEST}"

# ---------- Summary ----------
echo ""
echo "=========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
