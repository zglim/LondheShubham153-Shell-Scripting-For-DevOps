#!/bin/bash
# real workflow: input -> validate -> check user exists with `id` -> create with useradd
#
# create_user() exit status contract (har case ka apna code hai):
#   0 -> user ban gaya
#   1 -> user pehle se mojood hai
#   2 -> input khaali ya sirf whitespace tha
#   3 -> username valid format me nahi hai
#   4 -> useradd / sudo command fail ho gaya
#
# `user_exists` aur `run_useradd` alag functions hain taaki tests inhe
# override karke real system ko chhede bina behaviour check kar saken.

# Linux username rule: lowercase letter/underscore se start, phir
# lowercase/digit/underscore/hyphen, max 32 chars (trailing `$` allowed nahi).
USERNAME_REGEX='^[a-z_][a-z0-9_-]{0,31}$'

user_exists() {
    id "$1" &>/dev/null
}

run_useradd() {
    sudo useradd -m "$1"
}

create_user() {
    local username
    read -r -p "Naya username daalo: " username

    # 1) khaali input -> useradd tak pahunchne se pehle hi rok do
    if [[ -z "$username" ]]; then
        echo "Error: username khaali nahi ho sakta" >&2
        return 2
    fi

    # 2) sirf whitespace (space/tab) -> bhi khaali hi maana jaayega
    if [[ -z "${username//[[:space:]]/}" ]]; then
        echo "Error: username sirf whitespace nahi ho sakta" >&2
        return 2
    fi

    # 3) format galat (digit se start, capital, space, special chars, >32 chars)
    if ! [[ "$username" =~ $USERNAME_REGEX ]]; then
        echo "Error: '$username' valid username nahi hai (lowercase letter/_ se start karein)" >&2
        return 3
    fi

    # 4) pehle se mojood user -> stable rok
    if user_exists "$username"; then
        echo "User '$username' pehle se hai" >&2
        return 1
    fi

    # 5) actual creation — exit code ko explicitly capture karo, na ki
    #    `&& echo || echo` me usko nigal jao.
    run_useradd "$username"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "User '$username' ban gaya"
        return 0
    fi

    echo "Error: useradd fail ho gaya (exit code $rc) — user '$username' nahi bana" >&2
    return 4
}

# Sirf direct run par hi interactive flow chalao; source hone par (tests) nahi.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_user
    exit $?
fi
