#!/bin/bash
# Capstone: backup practice-scripts with tar + gzip, timestamped.
# Combines: set -e, variables, $(date), functions, if checks, conditionals.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$HOME/shell-backups}"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE="$BACKUP_DIR/practice-scripts_${TIMESTAMP}.tar.gz"
KEEP_COUNT=7

# --- shared helper: list backup files matching our glob, one per line, sorted newest-first ---
# Outputs absolute paths. Safe with spaces/special chars in BACKUP_DIR.
# Returns 0 even when no files match (prints nothing).
list_backups() {
    # Use a subshell so glob/printf failures never kill the caller.
    (
        shopt -s nullglob
        # Collect matching files into an array
        files=("$BACKUP_DIR"/practice-scripts_*.tar.gz)
        if [[ ${#files[@]} -eq 0 ]]; then
            exit 0
        fi
        # Sort by modification time, newest first, NUL-delimited for safety
        printf '%s\0' "${files[@]}" | xargs -0 ls -1t 2>/dev/null || true
    )
}

prepare_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR" || { echo "ERROR: cannot create backup dir: $BACKUP_DIR" >&2; return 1; }
        echo "Backup folder bana diya: $BACKUP_DIR"
    fi
    # Verify the directory is accessible
    if [[ ! -r "$BACKUP_DIR" ]] || [[ ! -w "$BACKUP_DIR" ]]; then
        echo "ERROR: backup dir not readable/writable: $BACKUP_DIR" >&2
        return 1
    fi
}

take_backup() {
    tar -czf "$ARCHIVE" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"
    echo "Backup ban gaya: $ARCHIVE"
    echo "Size: $(du -h "$ARCHIVE" | awk '{print $1}')"
}

cleanup_old_backups() {
    # rakho sirf last $KEEP_COUNT backups, baaki delete
    local all_backups
    all_backups="$(list_backups)"

    if [[ -z "$all_backups" ]]; then
        echo "Koi purana backup nahi mila, cleanup skip."
        return 0
    fi

    local count
    count="$(echo "$all_backups" | wc -l)"

    if [[ "$count" -le "$KEEP_COUNT" ]]; then
        echo "Sirf $count backup(s) hain (limit $KEEP_COUNT), cleanup skip."
        return 0
    fi

    # Delete everything after the first KEEP_COUNT entries.
    # list_backups outputs one path per line, newest first.
    echo "$all_backups" | tail -n +"$((KEEP_COUNT + 1))" | while IFS= read -r old_file; do
        if [[ -n "$old_file" ]] && [[ -f "$old_file" ]]; then
            rm -f "$old_file"
            echo "Purana backup hata diya: $old_file"
        fi
    done
}

prepare_backup_dir
take_backup
cleanup_old_backups

echo "Done. Saare backups:"
remaining="$(list_backups)"
if [[ -z "$remaining" ]]; then
    echo "  (koi backup nahi mila — yeh unexpected hai)"
else
    echo "$remaining" | while IFS= read -r f; do
        ls -lh "$f"
    done
fi
