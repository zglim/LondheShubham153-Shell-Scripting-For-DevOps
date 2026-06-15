#!/bin/bash
# Regression tests for 19_backup.sh
# Covers: first-run (only new backup), >7 backups cleanup, dir with spaces.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/19_backup.sh"
PASS=0
FAIL=0

fail() { echo "  FAIL: $1" >&2; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# Helper: run the backup script with a custom BACKUP_DIR
run_backup() {
    local dir="$1"
    BACKUP_DIR="$dir" bash "$BACKUP_SCRIPT" >/dev/null 2>&1
}

# Helper: count backup files in a directory
count_backups() {
    local dir="$1"
    ( shopt -s nullglob; files=("$dir"/practice-scripts_*.tar.gz); echo "${#files[@]}" )
}

cleanup() { rm -rf "$1"; }

# ---------- Test 1: First run, only new backup, no error ----------
echo "Test 1: First run with empty backup dir"
TDIR="$(mktemp -d)"
trap "cleanup '$TDIR'" EXIT
run_backup "$TDIR"
cnt="$(count_backups "$TDIR")"
if [[ "$cnt" -eq 1 ]]; then pass "exactly 1 backup after first run"; else fail "expected 1 backup, got $cnt"; fi
cleanup "$TDIR"

# ---------- Test 2: More than 7 backups → only 7 kept ----------
echo "Test 2: >7 backups, only latest 7 retained"
TDIR="$(mktemp -d)"
trap "cleanup '$TDIR'" EXIT

# Create 9 fake old backups with distinct timestamps so cleanup has work to do
for i in $(seq 1 9); do
    ts="2025-01-01_00-00-0${i}"
    touch "$TDIR/practice-scripts_${ts}.tar.gz"
    sleep 0.1  # ensure distinct mtime
done
pre_count="$(count_backups "$TDIR")"
if [[ "$pre_count" -eq 9 ]]; then pass "9 fake backups created"; else fail "expected 9, got $pre_count"; fi

# Run script — adds 1 more (total 10), should keep only 7
run_backup "$TDIR"
post_count="$(count_backups "$TDIR")"
if [[ "$post_count" -eq 7 ]]; then pass "exactly 7 backups after cleanup (had 10)"; else fail "expected 7 backups after cleanup, got $post_count"; fi
cleanup "$TDIR"

# ---------- Test 3: Dir name with spaces ----------
echo "Test 3: Backup dir with spaces in path"
TDIR="$(mktemp -d)/my backup dir"
mkdir -p "$TDIR"
PARENT="$(dirname "$TDIR")"
trap "rm -rf '$PARENT'" EXIT

run_backup "$TDIR"
cnt="$(count_backups "$TDIR")"
if [[ "$cnt" -eq 1 ]]; then pass "backup created in dir with spaces"; else fail "expected 1 backup, got $cnt"; fi

# Add 8 more fake backups to test cleanup in space-path dir
for i in $(seq 1 8); do
    ts="2025-02-02_00-00-0${i}"
    touch "$TDIR/practice-scripts_${ts}.tar.gz"
    sleep 0.1
done
run_backup "$TDIR"
post_count="$(count_backups "$TDIR")"
if [[ "$post_count" -eq 7 ]]; then pass "cleanup works in dir with spaces (7 kept)"; else fail "expected 7, got $post_count"; fi
rm -rf "$PARENT"

# ---------- Test 4: Exactly 7 backups — no deletion ----------
echo "Test 4: Exactly 7 backups, nothing deleted"
TDIR="$(mktemp -d)"
trap "cleanup '$TDIR'" EXIT
for i in $(seq 1 7); do
    ts="2025-03-03_00-00-0${i}"
    touch "$TDIR/practice-scripts_${ts}.tar.gz"
    sleep 0.1
done
run_backup "$TDIR"
# Now 8 total → cleanup should remove 1 oldest
post_count="$(count_backups "$TDIR")"
if [[ "$post_count" -eq 7 ]]; then pass "8→7 after adding one to existing 7"; else fail "expected 7, got $post_count"; fi
cleanup "$TDIR"

# ---------- Summary ----------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
