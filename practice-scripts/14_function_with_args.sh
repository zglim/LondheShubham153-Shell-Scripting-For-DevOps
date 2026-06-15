#!/bin/bash
# function with arguments; $1 inside a function refers to that function's first arg
#
# This file does double duty:
#   - run it directly  (bash 14_function_with_args.sh)  -> shows a demo of the functions
#   - `source` it       (from another script)           -> ONLY defines the functions,
#                                                           with no demo output, so the
#                                                           caller can reuse them cleanly.

greet() {
    echo "Namaste $1 ji!"
}

install_package() {
    echo "Installing: $1"
    # sudo apt-get install -y "$1"
}

# --- Demo (runs only on direct execution, NOT when sourced) ---
# When you run this file directly, bash sets $0 to this file's path, which equals
# ${BASH_SOURCE[0]}. When another script `source`s this file, ${BASH_SOURCE[0]} is
# still this file but $0 is the *caller's* path -> they differ, so the demo is skipped
# and only the function definitions above are imported.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    greet "jethalal"
    greet "babita"
    install_package "nginx"
fi
