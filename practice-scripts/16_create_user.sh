#!/bin/bash
# real workflow: input -> validate -> check user exists with `id` -> create with useradd
#
# Exit codes:
#   0 - User created successfully
#   1 - User already exists
#   2 - Invalid input (empty, whitespace, or illegal username)
#   3 - useradd execution failed

create_user() {
    local username

    # Accept username as argument (testable) or read interactively
    if [[ $# -ge 1 ]]; then
        username="$1"
    else
        read -p "Naya username daalo: " username
    fi

    # --- Input validation ---

    # Empty or whitespace-only input
    if [[ -z "${username// /}" ]]; then
        echo "Error: Username khaali ya sirf whitespace hai" >&2
        return 2
    fi

    # Length check (Linux limit: 32 chars)
    if [[ ${#username} -gt 32 ]]; then
        echo "Error: Username 32 characters se lamba hai" >&2
        return 2
    fi

    # Must start with lowercase letter or underscore,
    # followed by lowercase letters, digits, underscores or hyphens
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Error: Username '$username' mein invalid characters hain" >&2
        return 2
    fi

    # --- Check if user already exists ---
    if id "$username" &>/dev/null; then
        echo "User '$username' pehle se hai" >&2
        return 1
    fi

    # --- Create user ---
    local useradd_rc=0
    sudo useradd -m "$username" || useradd_rc=$?

    if [[ $useradd_rc -ne 0 ]]; then
        echo "Error: Useradd fail ho gaya (exit code: $useradd_rc)" >&2
        return 3
    fi

    echo "User '$username' ban gaya"
    return 0
}

# Only call create_user when the script is executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_user
fi
