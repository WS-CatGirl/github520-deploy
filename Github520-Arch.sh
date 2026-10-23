#!/usr/bin/env bash
# =============================================================================
# Github520-Arch.sh
#
# Thin Arch Linux entry point for github520-common.sh.
#
# Version : v1.1-milestone.1
# Author  : 白丝小猫娘 (WS-CatGirl)
#
# Repositories:
#   https://github.com/WS-CatGirl/github520-deploy
#   https://gitee.com/wscatgirl/github520-deploy
#   https://gitcode.com/WS_CatGirl/github520-deploy
#   https://codeberg.org/WS_CatGirl/github520-deploy
# =============================================================================

set -Eeuo pipefail

PLATFORM=arch

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH=${0:-}
SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)

# The Arch package installs a marker so the same wrapper can switch to
# package-managed paths without changing the source-checkout behaviour.
: "${GITHUB520_PACKAGED:=0}"
if [ "$GITHUB520_PACKAGED" != "1" ] &&
   [ "$SCRIPT_PATH" = "/usr/bin/github520-arch" ] &&
   [ -f "/usr/lib/github520-arch/.packaged" ]; then
    GITHUB520_PACKAGED=1
fi
export GITHUB520_PACKAGED

LIB_DIR=""
for candidate in "$SCRIPT_DIR/lib" "${GITHUB520_LIB_DIR:-/usr/lib/github520-arch}" "/usr/local/lib/github520-arch"; do
    if [ -f "$candidate/github520-common.sh" ]; then
        LIB_DIR=$candidate
        break
    fi
done

if [ -z "$LIB_DIR" ]; then
    printf '[ FAIL ] Shared library not found (github520-common.sh).\n' >&2
    printf '        Run this script from the cloned repository, install the Arch package, or reinstall it.\n' >&2
    exit 1
fi

# shellcheck source=lib/github520-common.sh
source "$LIB_DIR/github520-common.sh"
# shellcheck source=lib/platform-arch.sh
source "$LIB_DIR/platform-arch.sh"

main "$@"
