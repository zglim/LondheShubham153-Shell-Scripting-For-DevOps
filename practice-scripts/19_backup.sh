#!/bin/bash
# Capstone: backup practice-scripts with tar + gzip, timestamped.
# Combines: set -e, variables, $(date), functions, if checks, conditionals.

set -e

# An unmatched glob expands to nothing (instead of the literal pattern), so an
# empty backup directory is handled cleanly even with `set -e` enabled. Every
# archive lookup in this script goes through this one behaviour.
shopt -s nullglob

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$HOME/shell-backups}"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Single matching rule shared by archive creation, cleanup, and the summary.
# The timestamp is zero-padded, so filenames sort chronologically -> a sorted
# glob (bash sorts glob results) is naturally ordered oldest -> newest.
ARCHIVE_GLOB="practice-scripts_*.tar.gz"
ARCHIVE="$BACKUP_DIR/practice-scripts_${TIMESTAMP}.tar.gz"

# How many of the most recent backups to keep.
KEEP=7

# Fill the global array BACKUPS with every archive in BACKUP_DIR, sorted
# oldest -> newest. An empty or unreadable directory yields an empty array
# rather than an error, so callers can treat "no backups" as a normal case.
list_backups() {
    BACKUPS=( "$BACKUP_DIR"/$ARCHIVE_GLOB )
}

prepare_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        echo "Backup folder created: $BACKUP_DIR"
    fi
}

take_backup() {
    tar -czf "$ARCHIVE" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"
    echo "Backup created: $ARCHIVE"
    echo "Size: $(du -h -- "$ARCHIVE" | awk '{print $1}')"
}

cleanup_old_backups() {
    # Keep only the newest $KEEP archives; delete the older ones. Uses the same
    # enumeration as everything else and never changes the working directory,
    # so it is safe regardless of where the script is run from.
    list_backups
    local total=${#BACKUPS[@]}

    if (( total <= KEEP )); then
        echo "Cleanup: $total backup(s) present (<= keep limit $KEEP), nothing to remove."
        return 0
    fi

    local remove_count=$(( total - KEEP ))
    echo "Cleanup: $total backups present, removing $remove_count old one(s), keeping newest $KEEP."

    # BACKUPS is oldest -> newest, so the first $remove_count entries are the
    # ones to delete. Quoting handles paths/filenames containing whitespace.
    local old
    for old in "${BACKUPS[@]:0:remove_count}"; do
        echo "  Removing: $old"
        rm -f -- "$old"
    done
}

print_summary() {
    # Re-enumerate after cleanup so the listing reflects the current state.
    # Built from the array (not `ls <glob>`), so an empty result is a clean
    # "(none)" instead of a `set -e` failure on an unmatched glob.
    list_backups
    echo "Done. All backups in: $BACKUP_DIR"
    if (( ${#BACKUPS[@]} == 0 )); then
        echo "  (none)"
        return 0
    fi
    local f
    for f in "${BACKUPS[@]}"; do
        printf '  %s\t%s\n' "$(du -h -- "$f" | awk '{print $1}')" "$f"
    done
}

prepare_backup_dir
take_backup
cleanup_old_backups
print_summary
