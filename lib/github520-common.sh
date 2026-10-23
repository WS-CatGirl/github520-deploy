#!/usr/bin/env bash
# =============================================================================
# github520-common.sh
#
# Loader for the shared modules; all implementation lives in lib/*.sh.
#
# Version : v1.2-milestone.1
#
# Platform-specific entry points:
#   lib/platform-arch.sh     Arch Linux (ID=arch)
#   lib/platform-generic.sh  Other systemd Linux distributions
#
# The thin wrappers set PLATFORM, locate this file, source it, then call main.
# Modules are sourced from this directory in a fixed order.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022
export LC_ALL=C

_github520_common_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
_github520_modules=(
    core.sh
    snapshots.sh
    network.sh
    ssh.sh
    hosts.sh
    systemd.sh
    uninstall.sh
    installer.sh
    cli.sh
)
for _github520_module in "${_github520_modules[@]}"; do
    if [ ! -f "$_github520_common_dir/$_github520_module" ]; then
        printf '[ FAIL ] Shared module not found: %s/%s\n' "$_github520_common_dir" "$_github520_module" >&2
        printf '        Reinstall the package or re-clone the repository.\n' >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$_github520_common_dir/$_github520_module"
done
unset _github520_module _github520_modules _github520_common_dir
