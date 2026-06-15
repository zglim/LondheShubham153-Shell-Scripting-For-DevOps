#!/bin/bash
#
# Regression tests for day03/deploy_django_app.sh
#
# These tests validate the code_clone / enter_project_dir / deploy call chain
# without actually running git clone, apt-get, docker, or sudo.
#
# Usage:  bash day03/test_deploy_django_app.sh
#

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/deploy_django_app.sh"

PASSED=0
FAILED=0
TEST_WORKDIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

setup_test_workdir() {
    TEST_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy_test.XXXXXX")"
}

cleanup_test_workdir() {
    [ -n "$TEST_WORKDIR" ] && rm -rf "$TEST_WORKDIR"
    TEST_WORKDIR=""
}

# Create a minimal project directory with the required files
create_valid_project_dir() {
    local base="${1:-$TEST_WORKDIR}"
    mkdir -p "$base/django-notes-app"
    touch "$base/django-notes-app/Dockerfile"
    touch "$base/django-notes-app/docker-compose.yml"
}

# Create a directory that is missing required files (invalid/incomplete)
create_invalid_project_dir() {
    local base="${1:-$TEST_WORKDIR}"
    mkdir -p "$base/django-notes-app"
    # Intentionally leave out Dockerfile and docker-compose.yml
}

# Extract functions from the deploy script so we can call them in isolation.
# We override external commands (git, sudo, docker, docker-compose, apt-get)
# via wrapper functions defined in the same subshell.
source_functions() {
    # shellcheck disable=SC1090
    # Source the script but stop before the main flow executes.
    # We achieve this by overriding 'echo' to intercept the main-flow marker,
    # but a simpler approach: we re-define the functions inline by extracting them.
    #
    # Simplest robust approach: source the file, but wrap it so the main flow
    # never actually runs.  We do this by defining `exit` as a no-op marker
    # and breaking out when we hit the main flow.
    #
    # Actually the cleanest approach: just copy the function definitions.
    # We use `declare -f` after sourcing in a subshell that skips main flow.

    # We'll extract functions using sed from the script
    local tmp_funcs
    tmp_funcs="$(mktemp)"

    # Extract everything from start of file up to (but not including) the
    # "# Main deployment script" comment.
    sed -n '1,/^# Main deployment script/p' "$SCRIPT_PATH" | sed '$d' > "$tmp_funcs"

    # Append stub overrides for external commands
    cat >> "$tmp_funcs" <<'STUBS'
# Stub overrides — prevent real side effects during tests
git()      { command git "$@" 2>/dev/null || return 1; }
sudo()     { return 0; }
apt-get()  { return 0; }
docker()   { return 0; }
docker-compose() { return 0; }
STUBS

    # Source the extracted functions in the current shell
    # shellcheck disable=SC1090
    source "$tmp_funcs"
    rm -f "$tmp_funcs"
}

# Run a test scenario inside an isolated subshell that:
#   - has its own cwd (TEST_WORKDIR)
#   - has stubbed external commands
#   - sources the deploy script's functions
# The test body is passed as a single argument (eval string).
run_test() {
    local name="$1"
    local body="$2"

    setup_test_workdir

    local result
    result="$(
        cd "$TEST_WORKDIR" || exit 99
        source_functions

        # Make git clone a controllable fake
        # By default: fake clone creates the expected directory structure
        git() {
            if [ "$1" = "clone" ]; then
                # Simulate successful clone
                local repo_name="django-notes-app"
                mkdir -p "$repo_name"
                touch "$repo_name/Dockerfile"
                touch "$repo_name/docker-compose.yml"
                return 0
            fi
            command git "$@" 2>/dev/null || return 1
        }

        # Evaluate the test body; capture exit code
        eval "$body"
    )"
    local rc=$?

    cleanup_test_workdir

    if [ $rc -eq 0 ]; then
        echo "  PASS: $name"
        PASSED=$((PASSED + 1))
    else
        echo "  FAIL: $name (rc=$rc)"
        [ -n "$result" ] && echo "        output: $result"
        FAILED=$((FAILED + 1))
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "=== Regression tests for deploy_django_app.sh ==="
echo ""

# Test 1: Fresh clone — code_clone succeeds, directory created, can enter it
run_test "fresh clone creates directory and can enter it" '
    # No pre-existing directory
    code_clone || exit 1
    enter_project_dir || exit 2
    # Verify we are inside the project directory
    [ -f "Dockerfile" ] || { echo "Dockerfile missing after enter_project_dir"; exit 3; }
    [ -f "docker-compose.yml" ] || { echo "docker-compose.yml missing"; exit 4; }
    exit 0
'

# Test 2: Directory already exists and is valid — skip clone, still enter
run_test "existing valid directory skips clone and enters correctly" '
    # Pre-create a valid project directory
    mkdir -p "django-notes-app"
    touch "django-notes-app/Dockerfile"
    touch "django-notes-app/docker-compose.yml"

    # git clone should NOT be called (redefine to fail if called)
    git() { echo "git should not be called"; exit 99; }

    code_clone || exit 1
    enter_project_dir || exit 2
    [ -f "Dockerfile" ] || { echo "Dockerfile missing"; exit 3; }
    exit 0
'

# Test 3: Clone failure — code_clone returns non-zero, deployment must not continue
run_test "clone failure causes code_clone to fail and blocks deployment" '
    # Override git to simulate clone failure
    git() { return 1; }

    code_clone
    rc=$?
    [ $rc -ne 0 ] || { echo "code_clone should have failed"; exit 1; }
    # Directory should not exist
    [ -d "django-notes-app" ] && { echo "directory should not exist after failed clone"; exit 2; }
    exit 0
'

# Test 4: Existing directory is incomplete (missing required files) — must fail
run_test "existing invalid/incomplete directory causes code_clone to fail" '
    # Create an incomplete directory
    mkdir -p "django-notes-app"
    # Do NOT create Dockerfile or docker-compose.yml

    code_clone
    rc=$?
    [ $rc -ne 0 ] || { echo "code_clone should have failed for invalid directory"; exit 1; }
    exit 0
'

# Test 5: deploy() refuses to run in wrong directory
run_test "deploy() refuses to run when Dockerfile is missing" '
    # Do NOT create any files — simulate being in wrong directory
    deploy
    rc=$?
    [ $rc -ne 0 ] || { echo "deploy() should have refused to run"; exit 1; }
    exit 0
'

# Test 6: deploy() succeeds in a valid project directory
run_test "deploy() succeeds when called inside valid project directory" '
    mkdir -p "django-notes-app"
    touch "django-notes-app/Dockerfile"
    touch "django-notes-app/docker-compose.yml"
    cd "django-notes-app" || exit 1

    deploy || exit 2
    exit 0
'

# Test 7: Main flow integration — fresh clone goes through clone → enter → deploy chain
run_test "main flow: fresh clone then enter_project_dir reaches project directory" '
    code_clone || exit 1
    enter_project_dir || exit 2
    # At this point we should be in django-notes-app with required files
    [ "$(basename "$(pwd)")" = "django-notes-app" ] || { echo "wrong directory: $(pwd)"; exit 3; }
    [ -f "Dockerfile" ] || { echo "Dockerfile missing"; exit 4; }
    exit 0
'

# Test 8: enter_project_dir fails when directory does not exist
run_test "enter_project_dir fails when project directory is missing" '
    # Do NOT create anything
    enter_project_dir
    rc=$?
    [ $rc -ne 0 ] || { echo "enter_project_dir should have failed"; exit 1; }
    exit 0
'

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
