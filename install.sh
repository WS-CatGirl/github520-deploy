#!/usr/bin/env bash
# =============================================================================
# install.sh
#
# Unified installer entry point for:
#   - Github520-Arch.sh    (Arch Linux, ID=arch)
#   - github520-deploy.sh  (other systemd Linux)
#
# The user clones the repository manually, then runs:
#   bash ./install.sh
#
# install.sh requests sudo, detects the platform, shows a short summary,
# asks for confirmation with a 60-second countdown, checks the shared library
# and selected script with "bash -n", and finally launches it. The selected
# script runs its own platform/container/VM checks again, so the original
# welcome and error messages stay unchanged.
#
# Version : v1.1-milestone.1
# Author  : 白丝小猫娘 (WS-CatGirl)
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022
export LC_ALL=C

VERSION="v1.1-milestone.1"
RELEASE_CHANNEL="milestone"
SCRIPT_NAME=${0##*/}
SELF=""
SCRIPT_DIR=""
CHILD_SCRIPT=""
CHILD_PATH=""
OS_ID=""
OS_NAME="Linux"
OS_VERSION=""
OS_LIKE=""
KERNEL=""
ARCH_LABEL=""
SYSTEMD_STATE="no"
STTY_STATE=""
HOST_NAME=""
USER_NAME=""
ROOT_FS=""
VIRT=""

_color_enabled() {
    [ -z "${NO_COLOR:-}" ] &&
    [ "${TERM:-dumb}" != "dumb" ] &&
    [ -t "$1" ]
}

if _color_enabled 1; then
    C_RESET=$'\033[0m'
    C_INFO=$'\033[1;36m'
    C_OK=$'\033[1;32m'
    C_WARN=$'\033[1;33m'
    C_ERR=$'\033[1;31m'
    C_ALERT=$'\033[1;91m'
    C_PINK=$'\033[1;35m'
else
    C_RESET=""
    C_INFO=""
    C_OK=""
    C_WARN=""
    C_ERR=""
    C_ALERT=""
    C_PINK=""
fi

if _color_enabled 2; then
    C_RESET_ERR=$'\033[0m'
    C_WARN_ERR=$'\033[1;33m'
    C_FAIL_ERR=$'\033[1;31m'
else
    C_RESET_ERR=""
    C_WARN_ERR=""
    C_FAIL_ERR=""
fi

log() {
    printf '%s[ INFO ]%s %s\n' "$C_INFO" "$C_RESET" "$*"
}

ok() {
    printf '%s[  OK  ]%s %s\n' "$C_OK" "$C_RESET" "$*"
}

warn() {
    printf '%s[ WARN ]%s %s\n' "$C_WARN_ERR" "$C_RESET_ERR" "$*" >&2
}

err() {
    printf '%s[ FAIL ]%s %s\n' "$C_FAIL_ERR" "$C_RESET_ERR" "$*" >&2
}

die() {
    err "$*"
    exit 1
}

show_prerelease_notice() {
    printf '\n%s' "$C_ALERT"
    printf '============================================================\n'
    printf '[ WARN ] PRE-RELEASE BUILD: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf 'This is not a Stable release. Keep backups and test before use.\n'
    printf 'Stable v1.1 is expected after RC validation.\n'
    printf '============================================================\n'
    printf '%s\n' "$C_RESET"
}

show_welcome() {
    printf '\n'
    printf '%s' "$C_PINK"
    cat <<'EOF'
      /\_/\
     ( o.o )   < Ciallo～(∠・ω< )⌒★
      > ^ <
EOF
    printf '%s' "$C_RESET"
    printf '\n'
    printf '  %s欢迎使用 GitHub520 安装引导 / Welcome to the GitHub520 installer%s\n' \
        "$C_INFO" "$C_RESET"
    printf '  猫娘会先检查系统，再帮你选择正确的脚本，喵～\n'
    printf '  This catgirl will check your system and pick the right script.\n'
    printf '  Version: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf '\n'
}

usage() {
    cat <<'EOF'
install.sh - GitHub520 unified installer

Usage:
  bash ./install.sh
  sudo bash ./install.sh

The installer must be run from the cloned repository. It requests sudo,
detects the distribution/kernel/architecture/systemd, shows a summary,
asks for confirmation with a 60-second countdown, checks the shared library
and selected script with "bash -n", and then launches it.

Direct installation through repository copies of Github520-Arch.sh or
github520-deploy.sh is rejected. Use this installer instead.
EOF
}

resolve_self() {
    SELF=$(readlink -f -- "$0" 2>/dev/null || true)
    if [ -z "$SELF" ]; then
        case "$0" in
            */*) SELF=$0 ;;
            *) SELF=$(command -v "$0" 2>/dev/null || true) ;;
        esac
    fi
    [ -n "$SELF" ] || SELF=${0:-install.sh}

    if [ -f "$SELF" ]; then
        SCRIPT_DIR=$(cd -- "$(dirname -- "$SELF")" && pwd)
    else
        SCRIPT_DIR=""
    fi
}

require_root() {
    if [ "$(id -u)" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            log "Running as root via sudo (invoked by $SUDO_USER)."
        else
            log "Running as root."
        fi
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "sudo is required to install GitHub520."
    fi

    log "Root privileges are required; sudo may ask for your password."
    if ! sudo -v; then
        die "sudo authentication failed, or this account cannot use sudo."
    fi

    exec sudo -- bash "$SELF" "$@"
}

detect_platform() {
    local machine

    HOST_NAME=$(hostname 2>/dev/null || true)
    [ -n "$HOST_NAME" ] || HOST_NAME=$(cat /etc/hostname 2>/dev/null || true)
    [ -n "$HOST_NAME" ] || HOST_NAME="unknown"

    USER_NAME=${SUDO_USER:-}
    if [ -z "$USER_NAME" ]; then
        USER_NAME=$(id -un 2>/dev/null || printf 'unknown')
    fi

    ROOT_FS=$(findmnt -n -o FSTYPE -T / 2>/dev/null || true)
    [ -n "$ROOT_FS" ] || ROOT_FS=$(stat -f -c '%T' / 2>/dev/null || true)
    [ -n "$ROOT_FS" ] || ROOT_FS="unknown"

    VIRT=$(systemd-detect-virt 2>/dev/null || true)
    if [ -z "$VIRT" ] || [ "$VIRT" = "none" ]; then
        VIRT="none"
    fi

    if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
        die "This installer only supports Linux."
    fi

    if [ -r /etc/os-release ]; then
        # Parse in a subshell so /etc/os-release cannot overwrite our globals.
        OS_ID=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${ID:-}"
        )
        OS_NAME=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${PRETTY_NAME:-Linux}"
        )
        OS_VERSION=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${VERSION_ID:-}"
        )
        OS_LIKE=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${ID_LIKE:-}"
        )
    else
        warn "/etc/os-release is missing; the distribution may not be detected correctly."
    fi

    [ -n "$OS_NAME" ] || OS_NAME="Linux"
    KERNEL=$(uname -r 2>/dev/null || printf 'unknown')
    machine=$(uname -m 2>/dev/null || printf 'unknown')

    case "$machine" in
        x86_64|amd64) ARCH_LABEL="x86_64 (x86)" ;;
        aarch64|arm64) ARCH_LABEL="aarch64 (ARM64)" ;;
        armv7l|armv6l) ARCH_LABEL="$machine (ARM32)" ;;
        riscv64) ARCH_LABEL="riscv64 (RISC-V)" ;;
        *) ARCH_LABEL=$machine ;;
    esac

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        SYSTEMD_STATE="yes"
    else
        SYSTEMD_STATE="no"
        warn "systemd was not detected; the selected script will perform the authoritative check."
    fi

    if [ "$OS_ID" = "arch" ]; then
        CHILD_SCRIPT="Github520-Arch.sh"
    else
        CHILD_SCRIPT="github520-deploy.sh"
        if [ -z "$OS_ID" ]; then
            warn "Could not identify the distribution; the generic script will be used."
        fi
        case " $OS_LIKE " in
            *" arch "*)
                warn "Arch-based distribution detected; using the generic script because Github520-Arch.sh requires ID=arch."
                ;;
        esac
    fi
}

show_info() {
    printf '\n%sSystem information%s\n' "$C_INFO" "$C_RESET"
    printf '  OS      : %s\n' "$OS_NAME"
    printf '  HostName: %s\n' "$HOST_NAME"
    printf '  UserName: %s\n' "$USER_NAME"
    if [ -n "$OS_VERSION" ]; then
        printf '  Version : %s\n' "$OS_VERSION"
    fi
    printf '  Kernel  : %s\n' "$KERNEL"
    printf '  Arch    : %s\n' "$ARCH_LABEL"
    printf '  Root FS : %s\n' "$ROOT_FS"
    printf '  Virt    : %s\n' "$VIRT"
    printf '  systemd : %s\n' "$SYSTEMD_STATE"
    printf '  Script  : %s\n' "$CHILD_SCRIPT"
    printf '  Repo    : %s\n' "$SCRIPT_DIR"
    printf '\n'
}

restore_tty() {
    if [ -n "${STTY_STATE:-}" ]; then
        stty "$STTY_STATE" 2>/dev/null || true
        STTY_STATE=""
    fi
}

drain_tty() {
    while IFS= read -r -n 1 -t 0.05 _ 2>/dev/null; do
        :
    done
}

confirm_install() {
    local key deadline remaining

    if [ ! -t 0 ]; then
        die "An interactive terminal is required. Run: bash ./install.sh"
    fi

    STTY_STATE=$(stty -g 2>/dev/null) || die "Unable to read the terminal settings."
    trap 'restore_tty; exit 130' INT TERM HUP
    trap restore_tty EXIT

    if ! stty -icanon -echo; then
        restore_tty
        die "Unable to configure the terminal for the countdown."
    fi

    deadline=$((SECONDS + 60))
    while :; do
        remaining=$((deadline - SECONDS))
        if [ "$remaining" -le 0 ]; then
            restore_tty
            printf '\n'
            warn "Timed out after 60 seconds; installation cancelled."
            return 1
        fi

        printf '\r[%2ds] Install GitHub520 now? [y/N] ' "$remaining"

        if IFS= read -r -n 1 -t 1 key; then
            case "$key" in
                y|Y)
                    drain_tty
                    restore_tty
                    printf '\n'
                    return 0
                    ;;
                n|N|'')
                    drain_tty
                    restore_tty
                    printf '\n'
                    return 1
                    ;;
            esac
        fi
    done
}

check_libraries() {
    local file

    for file in github520-common.sh platform-arch.sh platform-generic.sh; do
        if [ ! -f "$SCRIPT_DIR/lib/$file" ]; then
            die "Shared library is missing: $SCRIPT_DIR/lib/$file"
        fi

        log "Checking syntax: lib/$file"
        if ! bash -n "$SCRIPT_DIR/lib/$file"; then
            die "Syntax check failed: $SCRIPT_DIR/lib/$file"
        fi
    done
    ok "Shared library checks passed."
}

check_script() {
    CHILD_PATH="$SCRIPT_DIR/$CHILD_SCRIPT"

    if [ ! -f "$CHILD_PATH" ]; then
        die "Selected script is missing: $CHILD_PATH"
    fi

    log "Checking syntax: $CHILD_SCRIPT"
    if ! bash -n "$CHILD_PATH"; then
        die "Syntax check failed: $CHILD_PATH"
    fi
    ok "Syntax check passed: $CHILD_SCRIPT"
}

launch_child() {
    log "Launching $CHILD_SCRIPT ..."
    log "The selected script will perform its own platform/container/VM checks."

    # Keep install.sh alive after the child exits so its EXIT trap can restore
    # the terminal. The environment marker allows the child's install command.
    set +e
    GITHUB520_FROM_INSTALLER=1 bash "$CHILD_PATH" install
    local rc=$?
    set -e

    exit "$rc"
}

main() {
    show_prerelease_notice

    case "${1:-}" in
        -h|--help|help)
            usage
            exit 0
            ;;
        -V|--version|version)
            printf '%s %s (%s)\n' "$SCRIPT_NAME" "$VERSION" "$RELEASE_CHANNEL"
            exit 0
            ;;
    esac

    if [ "$#" -gt 0 ]; then
        die "Unknown argument: $1"
    fi

    if [ -z "${BASH_VERSION:-}" ]; then
        die "Run this installer with bash: bash ./install.sh"
    fi

    resolve_self

    if [ ! -f "$SELF" ] || [ -z "$SCRIPT_DIR" ]; then
        die "Run this installer from the cloned repository: bash ./install.sh"
    fi

    if [ ! -f "$SCRIPT_DIR/Github520-Arch.sh" ] || [ ! -f "$SCRIPT_DIR/github520-deploy.sh" ]; then
        die "Missing Github520-Arch.sh or github520-deploy.sh. Clone the full repository first."
    fi

    require_root "$@"

    show_welcome
    log "Detecting platform."
    detect_platform
    ok "Platform detection complete: $OS_NAME ($ARCH_LABEL)."
    show_info

    log "Waiting for installation confirmation (60-second timeout)."
    if ! confirm_install; then
        log "Installation cancelled."
        exit 0
    fi
    ok "Installation confirmed."

    check_libraries
    check_script
    launch_child
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
