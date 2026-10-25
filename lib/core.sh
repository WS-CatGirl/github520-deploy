#!/usr/bin/env bash
# =============================================================================
# core.sh
#
# Core state, output helpers, traps, privileges, OS checks and terminal
# helpers.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

: "${PLATFORM:=generic}"

case "${GITHUB520_PACKAGED:-0}" in
    1|yes|true|on) PACKAGED_MODE=1 ;;
    *) PACKAGED_MODE=0 ;;
esac

case "$PLATFORM" in
    arch)
        PROGRAM_NAME="github520-arch"
        PROGRAM_LABEL="GitHub520-Arch"
        PLATFORM_DESC="Arch Linux"
        PLATFORM_CHECK_DESC="Arch Linux check"
        REPO_SCRIPT_NAME="Github520-Arch.sh"
        USAGE_TITLE="GitHub520-Arch.sh"
        BACKUP_DIR="/var/backups/github520"
        LOG_DIR="/var/log/github520"
        INSTALL_PATH="/usr/local/bin/github520-arch"
        LEGACY_INSTALL_PATH="/usr/local/bin/github520-arch.sh"
        SERVICE_NAME="github520-update.service"
        TIMER_NAME="github520-update.timer"
        SNAPSHOT_PREFIX="github520-arch"
        TMP_PREFIX="github520-arch"
        ELEVATED_MARKER="GITHUB520_ARCH_ELEVATED"
        ;;
    generic)
        PROGRAM_NAME="github520-deploy"
        PROGRAM_LABEL="GitHub520-Deploy"
        PLATFORM_DESC="Linux"
        PLATFORM_CHECK_DESC="Linux / container / VM check"
        REPO_SCRIPT_NAME="github520-deploy.sh"
        USAGE_TITLE="github520-deploy.sh"
        BACKUP_DIR="/var/backups/github520-deploy"
        LOG_DIR="/var/log/github520-deploy"
        INSTALL_PATH="/usr/local/bin/github520-deploy"
        LEGACY_INSTALL_PATH="/usr/local/bin/github520-deploy.sh"
        SERVICE_NAME="github520-deploy-update.service"
        TIMER_NAME="github520-deploy-update.timer"
        SNAPSHOT_PREFIX="github520-deploy"
        TMP_PREFIX="github520-deploy"
        ELEVATED_MARKER="GITHUB520_DEPLOY_ELEVATED"
        ;;
    *)
        printf '[ FAIL ] Unknown platform: %s\n' "$PLATFORM" >&2
        exit 2
        ;;
esac

VERSION="v1.0.1-rc"
RELEASE_CHANNEL="rc"
# Files copied by install_script_copy and checked by package/source validation.
GITHUB520_LIB_FILES=(
    "github520-common.sh"
    "core.sh"
    "snapshots.sh"
    "network.sh"
    "ssh.sh"
    "hosts.sh"
    "systemd.sh"
    "uninstall.sh"
    "installer.sh"
    "cli.sh"
)
SCRIPT_NAME=${0##*/}
SELF=""
if [ "$PACKAGED_MODE" -eq 1 ] && { [ "$PLATFORM" = "arch" ] || [ "$PLATFORM" = "generic" ]; }; then
    INSTALL_PATH="/usr/bin/$PROGRAM_NAME"
    LEGACY_INSTALL_PATH=""
    LIB_INSTALL_DIR="/usr/lib/$PROGRAM_NAME"
    if [ "$PLATFORM" = "generic" ]; then
        UNIT_DIR="/lib/systemd/system"
    else
        UNIT_DIR="/usr/lib/systemd/system"
    fi
else
    LIB_INSTALL_DIR="/usr/local/lib/$PROGRAM_NAME"
    UNIT_DIR="/etc/systemd/system"
fi
HOSTS_FILE="/etc/hosts"
RESOLV_FILE="/etc/resolv.conf"
UPDATE_LOG="$LOG_DIR/update.log"
ORIGINAL_HOSTS_BACKUP="$BACKUP_DIR/hosts.original"
SNAPSHOT_TIMEOUT=30
MAX_HOSTS_BACKUPS=24
LOCK_FILE="/run/github520-hosts.lock"

COMMAND=""
SYSTEMD_MODE=0
MANUAL_UPDATE=0
FOLLOW_LOG=0
FORCE=0
REINSTALL=0
EXISTING_INSTALL_CLI=0
EXISTING_INSTALL_TIMER=0
EXISTING_INSTALL_HOSTS=0
EXISTING_INSTALL_REASONS=()
RESTORE_TARGET=""

GITHUB520_REPO_URL="https://github.com/521xueweihan/GitHub520"
# Project repository links for the final summary; hosts data uses HOSTS_SOURCES.
REPO_URLS=(
    "https://github.com/WS-CatGirl/github520-deploy"
    "https://gitee.com/wscatgirl/github520-deploy"
    "https://gitcode.com/WS_CatGirl/github520-deploy"
    "https://codeberg.org/WS_CatGirl/github520-deploy"
    "https://gitea.com/WS-CatGirl/github520-deploy"
)
HOSTS_SOURCES=(
    "https://raw.hellogithub.com/hosts"
    "https://fastly.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://gcore.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://testingcf.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://quantil.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://cdn.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"
)

UPDATE_MODE=0
TMP_DIR=""
HOSTS_BACKUP=""
HOSTS_WRITTEN=0
HOSTS_COMMITTED=0
HOSTS_ENTRY_COUNT=0
HOSTS_DOWNLOAD_ENTRIES=0
SELECTED_HOSTS_URL=""
SNAPSHOT_DONE="skipped"
SNAPSHOT_TTY_STATE=""
NET_BACKUP_DIR=""
NETWORK_CONFIGURED=0
BACKEND=""
BACKEND_ID=""
BACKEND_FILE=""
IFACE=""
GATEWAY=""
CURRENT_CIDR=""
STATIC_CIDR=""
STATIC_ADDR=""
STATIC_PREFIX=""
DNS_SERVERS=()
NET_BACKEND_DESC=""
NETWORK_ROLLBACK_PENDING=0
NM_OLD_METHOD=""
NM_OLD_ADDR=""
NM_OLD_GATEWAY=""
NM_OLD_DNS=""
NM_OLD_IGNORE_DNS=""
NETWORKD_FILE=""
NETWORKD_OLD=""
IFUPDOWN_SRC=""
IFUPDOWN_OLD=""
RESOLV_BACKUP=""
DNS_VIA_RESOLVECTL=0
DNS_VIA_RESOLVCONF=0
DNS_VALIDATION_RESTORED=0

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
    C_SSH_ALERT=$'\033[1;97;41m'
    C_PINK=$'\033[1;35m'
else
    C_RESET=""
    C_INFO=""
    C_OK=""
    C_WARN=""
    C_ERR=""
    C_ALERT=""
    C_SSH_ALERT=""
    C_PINK=""
fi

if _color_enabled 2; then
    C_RESET_ERR=$'\033[0m'
    C_INFO_ERR=$'\033[1;36m'
    C_OK_ERR=$'\033[1;32m'
    C_WARN_ERR=$'\033[1;33m'
    C_FAIL_ERR=$'\033[1;31m'
    C_ALERT_ERR=$'\033[1;91m'
else
    C_RESET_ERR=""
    C_INFO_ERR=""
    C_OK_ERR=""
    C_WARN_ERR=""
    C_FAIL_ERR=""
    C_ALERT_ERR=""
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
_log_line() {
    local level=$1
    local fd=$2
    local label color reset
    shift 2

    case "$level" in
        INFO) label=" INFO " ;;
        OK) label="  OK  " ;;
        WARN) label=" WARN " ;;
        FAIL) label=" FAIL " ;;
        ALERT) label=" ALERT " ;;
        *) label=" INFO " ;;
    esac

    if [ "$fd" -eq 2 ]; then
        reset=$C_RESET_ERR
        case "$level" in
            INFO) color=$C_INFO_ERR ;;
            OK) color=$C_OK_ERR ;;
            WARN) color=$C_WARN_ERR ;;
            FAIL) color=$C_FAIL_ERR ;;
            ALERT) color=$C_ALERT_ERR ;;
            *) color=$C_INFO_ERR ;;
        esac
    else
        reset=$C_RESET
        case "$level" in
            INFO) color=$C_INFO ;;
            OK) color=$C_OK ;;
            WARN) color=$C_WARN ;;
            FAIL) color=$C_ERR ;;
            ALERT) color=$C_ALERT ;;
            *) color=$C_INFO ;;
        esac
    fi

    if [ "$UPDATE_MODE" -eq 1 ]; then
        printf '[%s] [%s] %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$label" "$*" >&"$fd"
    else
        printf '%s[%s]%s %s\n' "$color" "$label" "$reset" "$*" >&"$fd"
    fi
}

log() {
    _log_line INFO 1 "$*"
}

ok() {
    _log_line OK 1 "$*"
}

warn() {
    _log_line WARN 2 "$*"
}

err() {
    _log_line FAIL 2 "$*"
}

die() {
    err "$*"
    # In systemd mode stdout/stderr already go to UPDATE_LOG; only manual
    # updates need an explicit log entry.
    if [ "$MANUAL_UPDATE" -eq 1 ] && [ "$UPDATE_MODE" -ne 1 ]; then
        append_update_log "[ FAIL ] ${*}"
    fi
    exit 1
}

append_update_log() {
    local message=$1

    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$UPDATE_LOG" 2>/dev/null || true
}

ensure_dir() {
    local dir=$1 mode=$2

    [ -d "$dir" ] && return 0

    if ! install -d -m "$mode" "$dir" 2>/dev/null; then
        mkdir -p "$dir" 2>/dev/null || die "Failed to create directory: $dir"
        chmod "$mode" "$dir" 2>/dev/null || true
    fi

    [ -d "$dir" ] || die "Failed to create directory: $dir"
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
    printf '  %s欢迎使用 / Welcome to %s%s\n' "$C_INFO" "$PROGRAM_LABEL" "$C_RESET"
    printf '  猫娘已经把 %s 的 hosts 工具准备好啦，喵～\n' "$PLATFORM_DESC"
    printf '  This catgirl is ready to make GitHub purr on %s.\n' "$PLATFORM_DESC"
    printf '  Version: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf '\n'
}

show_prerelease_notice() {
    printf '\n%s' "$C_ALERT"
    printf '============================================================\n'
    printf '[ WARN ] RELEASE CANDIDATE: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf 'This is not a Stable release. Keep backups and test before use.\n'
    printf 'Stable v1.0.1 is expected after RC validation.\n'
    printf '============================================================\n'
    printf '%s\n' "$C_RESET"
}

# -----------------------------------------------------------------------------
# Cleanup / rollback
# -----------------------------------------------------------------------------
cleanup() {
    local rc=$?
    trap - ERR

    if [ -n "${SNAPSHOT_TTY_STATE:-}" ]; then
        stty "$SNAPSHOT_TTY_STATE" 2>/dev/null || true
        SNAPSHOT_TTY_STATE=""
    fi

    if [ "${NETWORK_ROLLBACK_PENDING:-0}" -eq 1 ]; then
        NETWORK_ROLLBACK_PENDING=0
        warn "Deployment did not complete; rolling back network changes."
        if rollback_network_config; then
            log "Previous network configuration restored."
        else
            warn "Network rollback was incomplete. Check '$NET_BACKUP_DIR'."
        fi
    fi

    if [ "$HOSTS_WRITTEN" -eq 1 ] && [ "$HOSTS_COMMITTED" -ne 1 ] &&
       [ -n "$HOSTS_BACKUP" ] && [ -f "$HOSTS_BACKUP" ]; then
        warn "Deployment did not complete; restoring $HOSTS_FILE."
        if cat -- "$HOSTS_BACKUP" > "$HOSTS_FILE" 2>/dev/null; then
            log "Restored $HOSTS_FILE."
        else
            err "Could not restore $HOSTS_FILE. Restore it manually:"
            err "  cp '$HOSTS_BACKUP' '$HOSTS_FILE'"
        fi
    fi

    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR" 2>/dev/null || true
    fi

    exit "$rc"
}

on_error() {
    die "Unexpected command failure at line $1."
}

trap cleanup EXIT
trap 'on_error "$LINENO"' ERR
trap 'exit 130' INT TERM
trap 'exit 129' HUP

# -----------------------------------------------------------------------------
# Privileges
# -----------------------------------------------------------------------------
deny_access() {
    err "ACCESS DENIED: $*"
    err "Advice: run this script as root, or ask an administrator to grant"
    err "your account sudo privileges, then retry."
    exit 1
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
        deny_access "this account is not root and sudo is not available."
    fi

    SELF=$(readlink -f -- "$0" 2>/dev/null || true)
    if [ -z "$SELF" ]; then
        SELF="$PWD/$0"
    fi

    if [ "${!ELEVATED_MARKER:-0}" = "1" ]; then
        deny_access "root privileges are still unavailable after sudo."
    fi

    if sudo -n true 2>/dev/null; then
        log "Re-executing with cached sudo credentials."
        export "$ELEVATED_MARKER=1"
        exec sudo -n -- bash "$SELF" "$@"
    fi

    log "Root privileges are required; sudo may ask for your password."
    if ! sudo -v; then
        deny_access "sudo authentication failed, or this account cannot use sudo."
    fi

    export "$ELEVATED_MARKER=1"
    exec sudo -- bash "$SELF" "$@"
}

# -----------------------------------------------------------------------------
# Linux / container / virtual machine check
# -----------------------------------------------------------------------------
detect_system() {
    local virt="" dmi="" pretty="Linux" os_id=""

    if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
        die "This script only supports Linux."
    fi

    if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ] ||
       grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        die "Windows Subsystem for Linux (WSL) is not supported."
    fi

    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] ||
       grep -qaE '(docker|kubepods|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
        die "Container environment detected. Containers are not supported."
    fi

    if [ -r /etc/os-release ]; then
        # Parse in a subshell: sourcing os-release in this shell would
        # overwrite this script's VERSION and other global variables.
        os_id=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${ID:-}"
        )
        pretty=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${PRETTY_NAME:-Linux}"
        )

        if [ "$os_id" = "arch" ]; then
            err "Arch Linux detected. This is the generic Linux version."
            err "Use the Arch version instead: sudo ./Github520-Arch.sh install"
            err "After installation, manage it with: sudo github520-arch"
            die "Generic github520-deploy.sh does not support Arch Linux."
        fi
    fi

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt=$(systemd-detect-virt 2>/dev/null || true)
        case "$virt" in
            ""|none)
                ;;
            docker|podman|lxc|lxc-libvirt|systemd-nspawn|openvz|rkt|proot|pouch|wsl|container-other)
                die "Container environment detected: $virt. Containers are not supported."
                ;;
            *)
                warn "Virtual machine detected: $virt. Continuing, but network changes may affect the host."
                ;;
        esac
    fi

    if [ -z "$virt" ] || [ "$virt" = "none" ]; then
        dmi=$(
            {
                cat /sys/class/dmi/id/product_name 2>/dev/null || true
                cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true
            } | tr '\n' ' '
        )
        case "${dmi,,}" in
            *virtualbox*|*vmware*|*kvm*|*qemu*|*hyper-v*|*xen*|*parallels*|*bochs*)
                warn "Virtual machine detected through DMI: $dmi"
                warn "Continuing, but network changes may affect the host."
                ;;
        esac
    fi

    if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
        die "systemd is required to install the hourly update timer."
    fi

    ok "Linux detected: $pretty"
}

# Generic platform entry point; platform-arch.sh overrides this function.
detect_platform() {
    detect_system
}

# -----------------------------------------------------------------------------
# Terminal helpers
# -----------------------------------------------------------------------------
drain_tty() {
    while IFS= read -r -n 1 -t 0.05 _ 2>/dev/null; do
        :
    done
}

require_tty() {
    if [ ! -t 0 ]; then
        die "This step requires an interactive terminal."
    fi
}
