#!/bin/bash
#
# Regression tests for deploy_django_app.sh
#
# These tests focus on the code-clone / enter-project-directory call chain that was
# previously inverted. External commands (git, docker, docker-compose, sudo, apt-get)
# are replaced by lightweight stubs on PATH so nothing touches the network or the host.
#
# Covered scenarios:
#   T1: a fresh clone leaves us inside the project directory
#   T2: an existing valid directory is reused (clone skipped) and still entered
#   T3: a clone failure does NOT cd into a missing dir and does NOT reach deploy
#   T4: an existing-but-incomplete directory fails explicitly and does NOT reach deploy
#   T5: the full happy path reaches deploy from inside the project directory

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy_django_app.sh"

if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo "Cannot find deploy script at $DEPLOY_SCRIPT" >&2
    exit 1
fi

# --- Build a PATH shim with controllable command stubs -----------------------
SHIM_BIN="$(mktemp -d)"
trap 'rm -rf "$SHIM_BIN"' EXIT

cat > "$SHIM_BIN/git" <<'EOF'
#!/bin/sh
# git stub: records that it ran, and either fails or creates a deployable repo dir.
if [ "$1" = "clone" ]; then
    [ -n "${GIT_CALLED_MARKER:-}" ] && : > "$GIT_CALLED_MARKER"
    if [ "${GIT_FAIL:-0}" = "1" ]; then
        echo "stub git: clone failed" >&2
        exit 1
    fi
    mkdir -p django-notes-app
    : > django-notes-app/Dockerfile
    : > django-notes-app/docker-compose.yml
    exit 0
fi
exit 0
EOF

cat > "$SHIM_BIN/docker" <<'EOF'
#!/bin/sh
# docker stub: records that the deploy step was reached.
[ -n "${DEPLOY_MARKER:-}" ] && : > "$DEPLOY_MARKER"
exit 0
EOF

cat > "$SHIM_BIN/docker-compose" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$SHIM_BIN/sudo" <<'EOF'
#!/bin/sh
# sudo stub: succeed without touching the host (covers apt-get and chown calls).
exit 0
EOF

cat > "$SHIM_BIN/apt-get" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod +x "$SHIM_BIN"/git "$SHIM_BIN"/docker "$SHIM_BIN"/docker-compose "$SHIM_BIN"/sudo "$SHIM_BIN"/apt-get

# --- Tiny assertion framework ------------------------------------------------
PASS=0
FAIL=0

check() {
    local name="$1"; shift
    if "$@"; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

# --- Tests (each runs in its own subshell for isolation) ---------------------

# T1: fresh clone -> code_clone succeeds and cwd is the project directory.
test_fresh_clone_enters_dir() {
    (
        WORK="$(mktemp -d)"
        cd "$WORK" || return 1
        export PATH="$SHIM_BIN:$PATH"
        export GIT_FAIL=0
        export GIT_CALLED_MARKER="$WORK/git_called"
        # shellcheck disable=SC1090
        source "$DEPLOY_SCRIPT"

        if ! code_clone >/dev/null; then
            echo "  code_clone returned non-zero on a fresh clone" >&2
            rm -rf "$WORK"; return 1
        fi
        case "$(pwd)" in
            */django-notes-app) : ;;
            *) echo "  expected cwd .../django-notes-app, got $(pwd)" >&2; rm -rf "$WORK"; return 1 ;;
        esac
        [ -f "$WORK/git_called" ] || { echo "  expected git clone to be invoked" >&2; rm -rf "$WORK"; return 1; }
        rm -rf "$WORK"
    )
}

# T2: existing valid dir -> clone is skipped, cwd is still the project directory.
test_existing_dir_enters_dir() {
    (
        WORK="$(mktemp -d)"
        cd "$WORK" || return 1
        mkdir -p django-notes-app
        : > django-notes-app/Dockerfile
        : > django-notes-app/docker-compose.yml
        export PATH="$SHIM_BIN:$PATH"
        export GIT_FAIL=1   # if clone were attempted it would fail; proves it is skipped
        export GIT_CALLED_MARKER="$WORK/git_called"
        # shellcheck disable=SC1090
        source "$DEPLOY_SCRIPT"

        if ! code_clone >/dev/null; then
            echo "  code_clone returned non-zero for an existing valid dir" >&2
            rm -rf "$WORK"; return 1
        fi
        case "$(pwd)" in
            */django-notes-app) : ;;
            *) echo "  expected cwd .../django-notes-app, got $(pwd)" >&2; rm -rf "$WORK"; return 1 ;;
        esac
        if [ -f "$WORK/git_called" ]; then
            echo "  git clone should NOT have been invoked for an existing dir" >&2
            rm -rf "$WORK"; return 1
        fi
        rm -rf "$WORK"
    )
}

# T3: clone failure -> code_clone fails, cwd unchanged, deploy never reached.
test_clone_failure_does_not_continue() {
    (
        WORK="$(mktemp -d)"
        cd "$WORK" || return 1
        export PATH="$SHIM_BIN:$PATH"
        export GIT_FAIL=1
        export DEPLOY_MARKER="$WORK/deploy_ran"
        # shellcheck disable=SC1090
        source "$DEPLOY_SCRIPT"

        # code_clone must fail and must not have changed directory.
        if code_clone >/dev/null 2>&1; then
            echo "  code_clone unexpectedly succeeded when clone failed" >&2
            rm -rf "$WORK"; return 1
        fi
        if [ "$(pwd)" != "$WORK" ]; then
            echo "  cwd changed to $(pwd) after a failed clone (should stay $WORK)" >&2
            rm -rf "$WORK"; return 1
        fi

        # Running the whole flow must abort before deploy. main() calls exit, so run
        # it in a nested subshell and confirm the deploy marker was never written.
        ( main >/dev/null 2>&1 )
        if [ -f "$WORK/deploy_ran" ]; then
            echo "  deploy step was reached despite a clone failure" >&2
            rm -rf "$WORK"; return 1
        fi
        rm -rf "$WORK"
    )
}

# T4: existing but incomplete dir -> explicit failure, deploy never reached.
test_incomplete_dir_fails() {
    (
        WORK="$(mktemp -d)"
        cd "$WORK" || return 1
        mkdir -p django-notes-app   # exists but has no Dockerfile / docker-compose
        export PATH="$SHIM_BIN:$PATH"
        export GIT_FAIL=1           # clone is skipped because the dir already exists
        export DEPLOY_MARKER="$WORK/deploy_ran"
        # shellcheck disable=SC1090
        source "$DEPLOY_SCRIPT"

        if code_clone >/dev/null 2>&1; then
            echo "  code_clone succeeded on an incomplete dir (should fail)" >&2
            rm -rf "$WORK"; return 1
        fi

        ( main >/dev/null 2>&1 )
        if [ -f "$WORK/deploy_ran" ]; then
            echo "  deploy step was reached for an incomplete project dir" >&2
            rm -rf "$WORK"; return 1
        fi
        rm -rf "$WORK"
    )
}

# T5: happy path -> full flow reaches deploy from inside the project directory.
test_happy_path_reaches_deploy() {
    (
        WORK="$(mktemp -d)"
        cd "$WORK" || return 1
        export PATH="$SHIM_BIN:$PATH"
        export GIT_FAIL=0
        export DEPLOY_MARKER="$WORK/deploy_ran"
        # shellcheck disable=SC1090
        source "$DEPLOY_SCRIPT"

        ( main >/dev/null 2>&1 )
        if [ ! -f "$WORK/deploy_ran" ]; then
            echo "  deploy step was not reached on the happy path" >&2
            rm -rf "$WORK"; return 1
        fi
        rm -rf "$WORK"
    )
}

# --- Run ---------------------------------------------------------------------
echo "Running deploy_django_app.sh regression tests..."
check "fresh clone enters project directory"            test_fresh_clone_enters_dir
check "existing valid dir is reused and entered"        test_existing_dir_enters_dir
check "clone failure does not continue to deploy"       test_clone_failure_does_not_continue
check "incomplete existing dir fails before deploy"     test_incomplete_dir_fails
check "happy path reaches deploy in project directory"  test_happy_path_reaches_deploy

echo "-------------------------------------------"
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
