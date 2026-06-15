#!/bin/bash
# source another script to reuse its functions

# Resolve the directory where this script lives (works from any working directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/14_function_with_args.sh"

# Fail fast if the target script is missing or cannot be sourced
if [[ ! -f "${TARGET_SCRIPT}" ]]; then
    echo "ERROR: Required script not found: ${TARGET_SCRIPT}" >&2
    exit 1
fi

if ! source "${TARGET_SCRIPT}"; then
    echo "ERROR: Failed to source script: ${TARGET_SCRIPT}" >&2
    exit 1
fi

# Verify that expected functions are actually loaded
if ! declare -f greet >/dev/null || ! declare -f install_package >/dev/null; then
    echo "ERROR: Expected functions (greet, install_package) were not loaded from ${TARGET_SCRIPT}" >&2
    exit 1
fi

echo "---"
echo "Ab dusre script se function call kar rahe hain:"
greet "popatlal"
install_package "docker"
