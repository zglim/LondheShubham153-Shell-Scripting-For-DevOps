#!/bin/bash
# Regression test for the 14 <- source -> 15 pair.
#
# Covers the three guarantees we care about:
#   A) 14 run directly STILL shows its parameterized-function demo output.
#   B) 14, when *sourced*, defines its functions but produces NO demo output
#      (no top-level side effects leak into the caller).
#   C) 15 can be run from ANY working directory; it sources 14 reliably and emits
#      only its own calls (popatlal/docker), never 14's demo (jethalal/babita/nginx).
#
# Deliberately does NOT use `set -e`: this is a test runner, so it must keep going
# after a failure to report every result, then exit non-zero if anything failed.

# Resolve paths from this file's own location so the test works from any CWD.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${TEST_DIR}")"
FOURTEEN="${TEST_DIR}/14_function_with_args.sh"
FIFTEEN="${TEST_DIR}/15_source_and_call.sh"

PASS=0
FAIL=0
ok()  { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

assert_eq() { # actual expected desc
    if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi
}
assert_contains() { # haystack needle desc
    if [[ "$1" == *"$2"* ]]; then ok "$3"; else bad "$3 (missing '$2')"; fi
}
assert_not_contains() { # haystack needle desc
    if [[ "$1" != *"$2"* ]]; then ok "$3"; else bad "$3 (unexpected '$2')"; fi
}

# --- A) 14 executed directly still demos its functions ---
out="$(bash "${FOURTEEN}" 2>&1)"; rc=$?
assert_eq "${rc}" 0 "14 direct run exits 0"
assert_contains "${out}" "Namaste jethalal ji!" "14 direct run shows greet jethalal"
assert_contains "${out}" "Namaste babita ji!"   "14 direct run shows greet babita"
assert_contains "${out}" "Installing: nginx"    "14 direct run shows install nginx"

# --- B) 14 sourced defines functions but prints nothing ---
# Source in a subshell, then emit a marker only if BOTH functions are defined.
sourced="$( source "${FOURTEEN}" >/tmp/_src_out.$$ 2>&1; \
            declare -F greet install_package >/dev/null 2>&1 && echo "__FUNCS_OK__" )"
demo_leak="$(cat /tmp/_src_out.$$ 2>/dev/null)"; rm -f "/tmp/_src_out.$$"
assert_contains     "${sourced}"  "__FUNCS_OK__"        "14 sourced defines greet & install_package"
assert_eq           "${demo_leak}" ""                   "14 sourced prints no demo output"
assert_not_contains "${demo_leak}" "Namaste"            "14 sourced does not run greet"
assert_not_contains "${demo_leak}" "Installing"         "14 sourced does not run install_package"

# --- C) 15 runs from any CWD, sources 14 reliably, emits only its own calls ---
check_15() { # label   run-output   exit-code
    local label="$1" out="$2" rc="$3"
    assert_eq           "${rc}" 0          "15 from ${label}: exits 0"
    assert_contains     "${out}" "Namaste popatlal ji!" "15 from ${label}: greets popatlal"
    assert_contains     "${out}" "Installing: docker"   "15 from ${label}: installs docker"
    # 14's demo must NOT leak through the source:
    assert_not_contains "${out}" "jethalal" "15 from ${label}: no leaked 14 demo (jethalal)"
    assert_not_contains "${out}" "babita"   "15 from ${label}: no leaked 14 demo (babita)"
    assert_not_contains "${out}" "nginx"    "15 from ${label}: no leaked 14 demo (nginx)"
}

# 1) repo root, using the relative path the user reported as broken
o="$(cd "${REPO_ROOT}"  && bash practice-scripts/15_source_and_call.sh 2>&1)"; check_15 "repo root (relative path)" "${o}" "$?"
# 2) practice-scripts dir, bare filename
o="$(cd "${TEST_DIR}"   && bash 15_source_and_call.sh 2>&1)";                   check_15 "practice-scripts dir" "${o}" "$?"
# 3) an unrelated dir (/tmp), absolute path
o="$(cd /tmp            && bash "${FIFTEEN}" 2>&1)";                             check_15 "/tmp (absolute path)" "${o}" "$?"

echo "-----------------------------------------"
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "${FAIL}" -eq 0 ]] || exit 1
