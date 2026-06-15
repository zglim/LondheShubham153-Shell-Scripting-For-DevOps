#!/bin/bash
# Minimal regression test for 19_backup.sh.
#
# Covers the edge cases that previously broke under `set -e`:
#   1. First run (only a brand-new backup) completes without error.
#   2. With more than KEEP backups, only the newest KEEP are retained
#      and the freshly created one survives cleanup.
#   3. A BACKUP_DIR whose path contains spaces still backs up, cleans up,
#      and lists results correctly.
#
# Run:  bash practice-scripts/19_backup_test.sh
#
# `set -u` catches mistakes in the test itself; we deliberately do NOT use
# `set -e` so every assertion runs and we get a full pass/fail report.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$SCRIPT_DIR/19_backup.sh"
KEEP=7

fail=0
note() { printf '%s\n' "$*"; }
check() {  # check <status> <description>
    if [[ "$1" -eq 0 ]]; then
        note "PASS: $2"
    else
        note "FAIL: $2"
        fail=1
    fi
}

# A fresh temp dir whose name contains a space, to exercise quoting throughout.
make_tmp() {
    mktemp -d "${TMPDIR:-/tmp}/backup test.XXXXXX"
}

count_backups() {  # count_backups <dir> -> prints integer
    local d="$1" n=0 f
    shopt -s nullglob
    for f in "$d"/practice-scripts_*.tar.gz; do n=$((n + 1)); done
    shopt -u nullglob
    printf '%s' "$n"
}

created_archive() {  # created_archive <captured-output> -> path the script reported
    printf '%s\n' "$1" | sed -n 's/^Backup created: //p'
}

# ---------------------------------------------------------------------------
# Scenario 1: first run, backup dir does not exist yet, only the new backup.
# The nested spaced path must be created and the run must exit 0.
# ---------------------------------------------------------------------------
base1="$(make_tmp)"
dir1="$base1/dest dir"            # does not exist yet -> tests prepare_backup_dir
out1="$(BACKUP_DIR="$dir1" bash "$TARGET" 2>&1)"; rc1=$?
check "$rc1" "scenario 1: first run exits 0 (rc=$rc1)"
n1="$(count_backups "$dir1")"
[[ "$n1" -eq 1 ]]; check "$?" "scenario 1: exactly 1 backup created (got $n1)"

# ---------------------------------------------------------------------------
# Scenario 2: more than KEEP backups -> keep only the newest KEEP.
# Seed 8 old (2020) archives; the script adds 1 fresh one => 9 total => trim 2.
# ---------------------------------------------------------------------------
base2="$(make_tmp)"
dir2="$base2/dest dir"
mkdir -p "$dir2"
for i in 1 2 3 4 5 6 7 8; do
    : > "$dir2/practice-scripts_2020-01-01_00-00-0$i.tar.gz"
done
out2="$(BACKUP_DIR="$dir2" bash "$TARGET" 2>&1)"; rc2=$?
check "$rc2" "scenario 2: run with many backups exits 0 (rc=$rc2)"
n2="$(count_backups "$dir2")"
[[ "$n2" -eq "$KEEP" ]]; check "$?" "scenario 2: only newest $KEEP retained (got $n2)"
[[ ! -e "$dir2/practice-scripts_2020-01-01_00-00-01.tar.gz" ]]; check "$?" "scenario 2: oldest backup removed"
[[ ! -e "$dir2/practice-scripts_2020-01-01_00-00-02.tar.gz" ]]; check "$?" "scenario 2: 2nd-oldest backup removed"
[[ -e "$dir2/practice-scripts_2020-01-01_00-00-08.tar.gz" ]]; check "$?" "scenario 2: most-recent old backup kept"
new2="$(created_archive "$out2")"
[[ -n "$new2" && -e "$new2" ]]; check "$?" "scenario 2: freshly created backup survives cleanup"

# ---------------------------------------------------------------------------
# Scenario 3: spaced backup dir -> cleanup AND summary must both work.
# Seed 9 old archives; script adds 1 => 10 total => trim to KEEP.
# ---------------------------------------------------------------------------
base3="$(make_tmp)"
dir3="$base3/my backups"
mkdir -p "$dir3"
for i in 1 2 3 4 5 6 7 8 9; do
    : > "$dir3/practice-scripts_2019-01-01_00-00-0$i.tar.gz"
done
out3="$(BACKUP_DIR="$dir3" bash "$TARGET" 2>&1)"; rc3=$?
check "$rc3" "scenario 3: run with spaced dir exits 0 (rc=$rc3)"
n3="$(count_backups "$dir3")"
[[ "$n3" -eq "$KEEP" ]]; check "$?" "scenario 3: spaced dir kept newest $KEEP (got $n3)"
printf '%s\n' "$out3" | grep -Fq -- "$dir3"; check "$?" "scenario 3: summary lists the spaced backup dir"

# ---------------------------------------------------------------------------
# Cleanup temp dirs (best effort).
# ---------------------------------------------------------------------------
rm -rf "$base1" "$base2" "$base3" 2>/dev/null || true

if [[ "$fail" -eq 0 ]]; then
    note "ALL TESTS PASSED"
    exit 0
fi
note "SOME TESTS FAILED"
exit 1
