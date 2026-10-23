#!/usr/bin/env bash
# =============================================================================
# github520-deploy.sh
#
# Thin generic Linux entry point for github520-common.sh.
#
# Version : v1.1-milestone.1-2
# Author  : 白丝小猫娘 (WS-CatGirl)
#
# Repositories:
#   https://github.com/WS-CatGirl/github520-deploy
#   https://gitee.com/wscatgirl/github520-deploy
#   https://gitcode.com/WS_CatGirl/github520-deploy
#   https://codeberg.org/WS_CatGirl/github520-deploy
#   https://gitea.com/WS-CatGirl/github520-deploy
# =============================================================================

set -Eeuo pipefail

PLATFORM=generic

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
[ -n "$SCRIPT_PATH" ] || SCRIPT_PATH=${0:-}
SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)

# The Debian package installs a marker so the same wrapper can switch to
# package-managed paths without changing the source-checkout behaviour.
: "${GITHUB520_PACKAGED:=0}"
if [ "$GITHUB520_PACKAGED" != "1" ] &&
   [ "$SCRIPT_PATH" = "/usr/bin/github520-deploy" ] &&
   [ -f "/usr/lib/github520-deploy/.packaged" ]; then
    GITHUB520_PACKAGED=1
fi
export GITHUB520_PACKAGED

LIB_DIR=""
for candidate in "$SCRIPT_DIR/lib" "${GITHUB520_LIB_DIR:-/usr/lib/github520-deploy}" "/usr/local/lib/github520-deploy"; do
    if [ -f "$candidate/github520-common.sh" ]; then
        LIB_DIR=$candidate
        break
    fi
done

if [ -z "$LIB_DIR" ]; then
    printf '[ FAIL ] Shared library not found (github520-common.sh).\n' >&2
    printf '        Run this script from the cloned repository, install the Debian package, or reinstall it.\n' >&2
    exit 1
fi

# shellcheck source=lib/github520-common.sh
source "$LIB_DIR/github520-common.sh"
# shellcheck source=lib/platform-generic.sh
source "$LIB_DIR/platform-generic.sh"

main "$@"
