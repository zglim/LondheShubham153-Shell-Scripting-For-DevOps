#!/bin/bash
# source another script to reuse its functions
#
# `source` (aka `.`) is bash's "import": it runs another file *in this same shell*,
# so any functions that file defines become callable right here. The classic trap is
# locating that file reliably -- a bare `source ./14_...sh` only works when your current
# directory happens to be practice-scripts/. We avoid that by resolving an absolute path.
set -euo pipefail

# Directory of THIS script, resolved to an absolute path so it does not depend on the
# caller's current working directory. ${BASH_SOURCE[0]} is this file's path; dirname
# strips the filename; cd+pwd turns it into a stable absolute directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_SCRIPT="${SCRIPT_DIR}/14_function_with_args.sh"

# Fail loudly and early if the file we depend on is missing...
if [[ ! -f "${LIB_SCRIPT}" ]]; then
    echo "ERROR: cannot find library script to source: ${LIB_SCRIPT}" >&2
    exit 1
fi

# ...or if sourcing it fails for any reason (e.g. a syntax error inside it).
if ! source "${LIB_SCRIPT}"; then
    echo "ERROR: failed to source ${LIB_SCRIPT}" >&2
    exit 1
fi

# Sourcing should have defined these functions. Verify up front so a missing/renamed
# function gives a clear message here instead of a confusing "command not found" later.
for fn in greet install_package; do
    if ! declare -F "${fn}" >/dev/null; then
        echo "ERROR: expected function '${fn}' was not loaded from ${LIB_SCRIPT}" >&2
        exit 1
    fi
done

echo "---"
echo "Ab dusre script se function call kar rahe hain:"
greet "popatlal"
install_package "docker"
