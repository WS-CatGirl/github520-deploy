#!/usr/bin/env bash
# =============================================================================
# github520-common.sh
#
# Version : v1.0-milestone.2
#
# Shared implementation for both GitHub520 Linux managers.
#
# Platform-specific entry points:
#   lib/platform-arch.sh     Arch Linux (ID=arch)
#   lib/platform-generic.sh  Other systemd Linux distributions
#
# The thin wrappers set PLATFORM, locate this file, source it, then call main.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022
export LC_ALL=C

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

VERSION="v1.0-milestone.2"
RELEASE_CHANNEL="milestone"
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
RESTORE_TARGET=""

GITHUB520_REPO_URL="https://github.com/521xueweihan/GitHub520"
# Project repository links for the final summary; hosts data uses HOSTS_SOURCES.
REPO_URLS=(
    "https://github.com/WS-CatGirl/github520-deploy"
    "https://gitee.com/wscatgirl/github520-deploy"
    "https://gitcode.com/WS_CatGirl/github520-deploy"
    "https://codeberg.org/WS_CatGirl/github520-deploy"
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
    printf '[ WARN ] PRE-RELEASE BUILD: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf 'This is not a Stable release. Keep backups and test before use.\n'
    printf 'Stable v1.0 is expected on 2026-10-25.\n'
    printf '============================================================\n'
    printf '%s\n' "$C_RESET"
}

usage() {
    cat <<EOF
${USAGE_TITLE} - GitHub520 manager for ${PLATFORM_DESC} (milestone)

Usage:
  sudo ${PROGRAM_NAME} [command]
  sudo ./${REPO_SCRIPT_NAME} [command]
  ${PROGRAM_NAME}                 # show status and a short help hint

Installation:
  Source checkout : run ./install.sh from the cloned repository.
  Package         : run sudo ${PROGRAM_NAME} install.
  Direct installation through a repository copy of this script is rejected.

Commands:
  install, --install             Apply hosts, optional network settings and
                                 enable the timer. Source copies must use
                                 ./install.sh; the installed CLI may redeploy.
  reinstall                      Re-run the installer using the installed
                                 script (same as install).
  update, refresh, --update      Immediately download and refresh /etc/hosts.
  status                         Show version, hosts count, timer state,
                                 last log line and backup count.
  logs [-f]                      Show the update log; -f follows it.
  restore [latest|original|FILE] Restore /etc/hosts from a backup.
  --uninstall                    Disable the timer and remove the CLI/units
                                 for a source install; package files remain.
  --uninstall-completely         Restore the original /etc/hosts, then remove
                                 logs, backups and temp files. Package files
                                 remain and must be removed with the system
                                 package manager.
  version, --version             Show version.
  help, --help                   Show this help.

Internal:
  --update --systemd             Used by ${SERVICE_NAME}. Redirects
                                 all output to ${LOG_DIR}/update.log.

Options:
  -f, --follow                   Follow the log (with logs).
      --force                    Skip the confirmation for --uninstall-completely.

Install flow (started by install.sh or the installed CLI):
  1. Welcome
  2. Root/sudo check
  3. ${PLATFORM_CHECK_DESC}
  4. Optional Btrfs/snapper snapshot
  5. Network backend detection
  6. GitHub520 download and /etc/hosts update
  7. Optional static IPv4/DNS configuration
  8. DNS validation and recovery
  9. Install and enable ${TIMER_NAME} (hourly)
 10. Final summary

Timer:
  systemctl status ${TIMER_NAME}
  systemctl list-timers ${TIMER_NAME}
  journalctl -u ${SERVICE_NAME}
  tail -f ${LOG_DIR}/update.log
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                usage
                exit 0
                ;;
            -V|--version|version)
                printf '%s %s (%s)\n' "$SCRIPT_NAME" "$VERSION" "$RELEASE_CHANNEL"
                exit 0
                ;;
            install|--install|reinstall)
                COMMAND="install"
                ;;
            update|refresh|--update|--refresh)
                COMMAND="update"
                ;;
            status|--status)
                COMMAND="status"
                ;;
            logs|--logs)
                COMMAND="logs"
                ;;
            uninstall|--uninstall)
                COMMAND="uninstall"
                ;;
            uninstall-completely|--uninstall-completely)
                COMMAND="uninstall-complete"
                ;;
            restore|--restore)
                COMMAND="restore"
                if [ "$#" -gt 1 ]; then
                    case "$2" in
                        -*) ;;
                        *)
                            RESTORE_TARGET=$2
                            shift
                            ;;
                    esac
                fi
                ;;
            --systemd)
                SYSTEMD_MODE=1
                ;;
            -f|--follow)
                FOLLOW_LOG=1
                ;;
            --force)
                FORCE=1
                ;;
            --)
                shift
                if [ "$#" -gt 0 ]; then
                    err "Unexpected argument: $*"
                    exit 2
                fi
                break
                ;;
            *)
                err "Unknown command or option: $1"
                err "Run '$SCRIPT_NAME --help' for usage."
                exit 2
                ;;
        esac
        shift
    done

    [ -n "$COMMAND" ] || COMMAND="status"
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
# Btrfs / snapper
# -----------------------------------------------------------------------------
snapshot_all_configs() {
    local csv=$1 cfg sub

    while IFS=, read -r cfg sub; do
        cfg=${cfg%$'\r'}
        sub=${sub%$'\r'}
        cfg=${cfg//\"/}
        sub=${sub//\"/}
        [ -n "$cfg" ] || continue
        log "Creating snapshot for snapper config '$cfg' (subvolume: ${sub:-unknown})..."
        if ! snapper --config "$cfg" create \
            --description "$SNAPSHOT_PREFIX $(date '+%Y-%m-%d %H:%M:%S')" \
            --cleanup-algorithm number; then
            die "Failed to create a snapshot for snapper config '$cfg'."
        fi
    done <<< "$csv"

    SNAPSHOT_DONE="all snapper configs"
}

snapshot_root_config() {
    local csv=$1 cfg sub root_cfg="" root_name=""

    while IFS=, read -r cfg sub; do
        cfg=${cfg%$'\r'}
        sub=${sub%$'\r'}
        cfg=${cfg//\"/}
        sub=${sub//\"/}
        if [ "$sub" = "/" ] && [ -n "$cfg" ]; then
            root_cfg=$cfg
            break
        fi
    done <<< "$csv"

    if [ -z "$root_cfg" ]; then
        while IFS=, read -r cfg sub; do
            cfg=${cfg%$'\r'}
            cfg=${cfg//\"/}
            if [ "$cfg" = "root" ]; then
                root_cfg=$cfg
                break
            fi
        done <<< "$csv"
    fi

    if [ -z "$root_cfg" ]; then
        die "Could not identify the snapper config for '/' (the @ subvolume)."
    fi

    root_name=$(btrfs subvolume show / 2>/dev/null |
        awk -F: '/^[[:space:]]*Name:/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' || true)
    if [ "$root_name" != "@" ]; then
        warn "The root subvolume is named '${root_name:-unknown}', not '@'."
    fi

    log "Creating snapshot for the root subvolume via snapper config '$root_cfg'..."
    if ! snapper --config "$root_cfg" create \
        --description "$SNAPSHOT_PREFIX $(date '+%Y-%m-%d %H:%M:%S')" \
        --cleanup-algorithm number; then
        die "Failed to create a snapshot for the root subvolume."
    fi

    SNAPSHOT_DONE="root subvolume (@) via snapper config '$root_cfg'"
}

confirm_non_btrfs() {
    local root_fs=${1:-unknown}
    local answer=""

    require_tty

    printf '\n%s' "$C_ALERT"
    cat <<EOF
============================================================
[ WARN ] NON-BTRFS ROOT FILESYSTEM DETECTED: ${root_fs}
============================================================
NO BTRFS SNAPSHOT WILL BE CREATED.

Without a snapshot there is no automatic rollback point for:
  - /etc/hosts
  - network configuration
  - the installed systemd timer

Back up important files before continuing.

Continue installation without a snapshot? [y/N]:
EOF
    printf '%s' "$C_RESET"

    while true; do
        if ! IFS= read -r answer; then
            printf '\n'
            die "Failed to read the confirmation."
        fi

        answer=${answer//[[:space:]]/}
        case "${answer,,}" in
            y|yes)
                printf '\n'
                warn "Continuing without a Btrfs snapshot; no rollback point will be created."
                return 0
                ;;
            n|no|'')
                printf '\n'
                die "Installation cancelled by user; no snapshot was created."
                ;;
            *)
                warn "Enter y or n."
                printf 'Continue installation without a snapshot? [y/N]: '
                ;;
        esac
    done
}

confirm_no_snapshot() {
    local state answer="" key rc remaining

    require_tty

    printf '\n%s' "$C_ALERT"
    cat <<'EOF'
[ ALERT ] NO SNAPSHOT WILL BE CREATED.
Continuing without a Btrfs snapshot means there is no rollback point
for /etc/hosts, network settings, or the installed timer.
Type YES (uppercase) and press Enter within 30 seconds to continue.
Press Ctrl-C to cancel.
EOF
    printf '%s' "$C_RESET"

    state=$(stty -g 2>/dev/null) || die "Unable to read the terminal settings."
    SNAPSHOT_TTY_STATE=$state
    if ! stty -icanon -echo; then
        SNAPSHOT_TTY_STATE=""
        die "Unable to configure the terminal for the confirmation."
    fi

    deadline=$((SECONDS + SNAPSHOT_TIMEOUT))
    while true; do
        remaining=$((deadline - SECONDS))
        if [ "$remaining" -le 0 ]; then
            printf '\n'
            stty "$state" 2>/dev/null || true
            SNAPSHOT_TTY_STATE=""
            die "No confirmation within ${SNAPSHOT_TIMEOUT} seconds; deployment cancelled."
        fi

        printf '\r[%2ds] Type YES (uppercase) and press Enter: %-3s' "$remaining" "$answer"

        rc=0
        if IFS= read -r -n 1 -t 1 key; then
            case "$key" in
                $'\177'|$'\b') answer=${answer%?} ;;
                $'\n'|$'\r'|'')
                    if [ "$answer" = "YES" ]; then
                        printf '\r%*s\r' 80 ''
                        drain_tty
                        stty "$state" 2>/dev/null || true
                        SNAPSHOT_TTY_STATE=""
                        printf '\n'
                        warn "No snapshot will be created; continuing without a rollback point."
                        return 0
                    fi
                    answer=""
                    printf '\r%*s\r' 80 ''
                    warn "Confirmation must be exactly YES (uppercase)."
                    ;;
                [A-Za-z]) answer+=$key ;;
                *) : ;;
            esac

            if [ "${#answer}" -gt 3 ]; then
                answer=""
                printf '\r%*s\r' 80 ''
                warn "Confirmation must be exactly YES (uppercase)."
            fi
        else
            rc=$?
            if [ "$rc" -le 128 ]; then
                printf '\n'
                stty "$state" 2>/dev/null || true
                SNAPSHOT_TTY_STATE=""
                die "Failed to read the confirmation."
            fi
        fi
    done
}

read_snapshot_choice() {
    local deadline choice="" rc remaining

    require_tty

    printf '\nSnapshot options (Btrfs with snapper detected):\n'
    printf '  1) Snapshot all snapper configs\n'
    printf '  2) Snapshot only the @ subvolume (root config)\n'
    printf '  3) Continue without a snapshot (requires YES confirmation)\n'
    printf '  4) Abort deployment\n'

    deadline=$((SECONDS + SNAPSHOT_TIMEOUT))
    while true; do
        remaining=$((deadline - SECONDS))
        if [ "$remaining" -le 0 ]; then
            printf '\r%*s\r' 60 ''
            die "Snapshot selection timed out after ${SNAPSHOT_TIMEOUT} seconds."
        fi
        printf '\r[%2ds] Select 1, 2, 3 or 4: ' "$remaining"

        rc=0
        if IFS= read -r -t 1 choice; then
            printf '\r%*s\r' 60 ''
            choice=${choice//[[:space:]]/}
            case "$choice" in
                1|2|3|4)
                    printf 'Selection: %s\n' "$choice"
                    SNAPSHOT_CHOICE=$choice
                    return 0
                    ;;
                '')
                    ;;
                *)
                    warn "Invalid selection '$choice'; enter 1, 2, 3 or 4."
                    ;;
            esac
        else
            rc=$?
            if [ "$rc" -le 128 ]; then
                printf '\n'
                die "Failed to read the snapshot selection."
            fi
        fi
    done
}

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

detect_filesystem_and_snapshot() {
    local root_fs cfg_csv subvol_count

    root_fs=$(findmnt -n -o FSTYPE -T / 2>/dev/null || true)
    if [ -z "$root_fs" ]; then
        root_fs=$(stat -f -c '%T' / 2>/dev/null || true)
    fi
    if [ -z "$root_fs" ]; then
        die "Unable to determine the root filesystem type."
    fi

    if [ "$root_fs" != "btrfs" ]; then
        confirm_non_btrfs "$root_fs"
        SNAPSHOT_DONE="not applicable ($root_fs; no snapshot)"
        return 0
    fi

    log "Root filesystem is Btrfs."

    if ! command -v snapper >/dev/null 2>&1; then
        log "snapper is not installed; snapshot skipped."
        SNAPSHOT_DONE="skipped (snapper not installed)"
        return 0
    fi

    if ! command -v btrfs >/dev/null 2>&1; then
        die "btrfs-progs is required to list Btrfs subvolumes."
    fi

    if ! btrfs subvolume list / > "$TMP_DIR/btrfs-subvolumes.txt" 2> "$TMP_DIR/btrfs.err"; then
        die "Failed to list Btrfs subvolumes: $(tr '\n' ' ' < "$TMP_DIR/btrfs.err")"
    fi

    if snapper --csvout list-configs >/dev/null 2>&1; then
        if ! cfg_csv=$(snapper --csvout list-configs 2>/dev/null | tail -n +2); then
            die "Failed to query snapper configurations."
        fi
    else
        if ! cfg_csv=$(snapper list-configs 2>/dev/null | tail -n +3 | awk 'NF >= 2 {print $1 "," $2}'); then
            die "Failed to query snapper configurations."
        fi
    fi

    if [ -z "$cfg_csv" ]; then
        log "snapper has no configurations; snapshot skipped."
        SNAPSHOT_DONE="skipped (no snapper configs)"
        return 0
    fi

    log "Snapper configurations:"
    while IFS=, read -r cfg_name sub; do
        cfg_name=${cfg_name%$'\r'}
        sub=${sub%$'\r'}
        cfg_name=${cfg_name//\"/}
        sub=${sub//\"/}
        [ -n "$cfg_name" ] || continue
        printf '  config: %-12s subvolume: %s\n' "$cfg_name" "${sub:-unknown}"
    done <<< "$cfg_csv"

    subvol_count=$(wc -l < "$TMP_DIR/btrfs-subvolumes.txt")
    subvol_count=${subvol_count//[[:space:]]/}
    log "Btrfs subvolumes reported under /: ${subvol_count:-0}"
    if [ "${subvol_count:-0}" -gt 0 ]; then
        head -n 20 "$TMP_DIR/btrfs-subvolumes.txt" | sed 's/^/  /'
        if [ "$subvol_count" -gt 20 ]; then
            printf '  ... (%s more)\n' "$((subvol_count - 20))"
        fi
    fi

    SNAPSHOT_CHOICE=""
    read_snapshot_choice
    case "$SNAPSHOT_CHOICE" in
        1) snapshot_all_configs "$cfg_csv" ;;
        2) snapshot_root_config "$cfg_csv" ;;
        3)
            confirm_no_snapshot
            SNAPSHOT_DONE="skipped by user (no snapshot)"
            return 0
            ;;
        4) die "Deployment cancelled by user." ;;
        *) die "Invalid snapshot selection." ;;
    esac
    SNAPSHOT_CHOICE=""

    ok "Snapshot created: $SNAPSHOT_DONE."
}

# -----------------------------------------------------------------------------
# Network detection and optional static configuration
# -----------------------------------------------------------------------------
detect_network_backends() {
    local -a managers=()

    command -v ip >/dev/null 2>&1 || die "iproute2 (the 'ip' command) is required."

    if [ -f /etc/network/interfaces ]; then
        managers+=("ifupdown")
    fi
    if command -v nmcli >/dev/null 2>&1; then
        if systemctl is-active --quiet NetworkManager 2>/dev/null; then
            managers+=("NetworkManager(active)")
        else
            managers+=("NetworkManager(installed)")
        fi
    fi
    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        managers+=("systemd-networkd")
    fi
    if command -v dhcpcd >/dev/null 2>&1; then
        managers+=("dhcpcd")
    fi
    if command -v connmanctl >/dev/null 2>&1; then
        managers+=("ConnMan")
    fi
    if command -v iwctl >/dev/null 2>&1; then
        managers+=("iwd")
    fi
    if command -v netctl >/dev/null 2>&1; then
        managers+=("netctl")
    fi

    if [ "${#managers[@]}" -gt 0 ]; then
        log "Network backends detected: $(join_words "${managers[@]}")"
    else
        warn "No known network management backend was detected."
    fi
    log "ifupdown is preferred for static IP/DNS changes; NetworkManager is the next fallback."
}

detect_default_route() {
    local route i
    local -a fields=()

    if ! route=$(ip -4 route show default 2>/dev/null); then
        warn "Failed to read the IPv4 routing table."
        return 1
    fi
    route=${route%%$'\n'*}
    if [ -z "$route" ]; then
        warn "No IPv4 default route is present."
        return 1
    fi

    IFS=' ' read -r -a fields <<< "$route"
    for ((i = 0; i < ${#fields[@]}; i++)); do
        case "${fields[i]}" in
            via) GATEWAY=${fields[i + 1]:-} ;;
            dev) IFACE=${fields[i + 1]:-} ;;
        esac
    done

    if [ -z "$IFACE" ]; then
        warn "Could not determine the default network interface."
        return 1
    fi

    CURRENT_CIDR=$(ip -o -4 addr show dev "$IFACE" scope global 2>/dev/null |
        awk '{print $4; exit}' || true)

    log "Default route: interface=$IFACE gateway=${GATEWAY:-unknown} address=${CURRENT_CIDR:-unknown}"

    if [ -n "$GATEWAY" ] && ! valid_ipv4 "$GATEWAY"; then
        warn "Detected gateway '$GATEWAY' is not a valid IPv4 address."
        GATEWAY=""
    fi
}

find_ifupdown_file() {
    local f
    for f in /etc/network/interfaces /etc/network/interfaces.d/*; do
        [ -f "$f" ] || continue
        if grep -qE "^[[:space:]]*iface[[:space:]]+${IFACE}[[:space:]]" "$f"; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

select_config_backend() {
    local uuid src

    BACKEND=""
    BACKEND_ID=""
    BACKEND_FILE=""

    if command -v ifup >/dev/null 2>&1 && src=$(find_ifupdown_file); then
        if command -v nmcli >/dev/null 2>&1 &&
           systemctl is-active --quiet NetworkManager 2>/dev/null &&
           nmcli -t -f DEVICE connection show --active 2>/dev/null |
               grep -Fx "$IFACE" >/dev/null; then
            warn "ifupdown and an active NetworkManager connection both exist for $IFACE."
            warn "ifupdown has priority, but NetworkManager may override it. Cancel and use nmcli if unsure."
        fi
        BACKEND="ifupdown"
        BACKEND_ID=$IFACE
        BACKEND_FILE=$src
        NET_BACKEND_DESC="ifupdown ($src)"
        log "Selected backend: ifupdown (preferred)."
        return 0
    fi

    if command -v nmcli >/dev/null 2>&1 &&
       systemctl is-active --quiet NetworkManager 2>/dev/null; then
        uuid=$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null |
            awk -F: -v dev="$IFACE" '$2 == dev {print $1; exit}' || true)
        if [ -n "$uuid" ]; then
            BACKEND="networkmanager"
            BACKEND_ID=$uuid
            NET_BACKEND_DESC="NetworkManager"
            log "Selected backend: NetworkManager."
            return 0
        fi
        warn "NetworkManager is active but has no active connection for $IFACE."
    fi

    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        BACKEND="networkd"
        BACKEND_ID=$IFACE
        NET_BACKEND_DESC="systemd-networkd"
        log "Selected backend: systemd-networkd."
        return 0
    fi

    die "No supported backend for static configuration (ifupdown, NetworkManager, systemd-networkd)."
}

valid_ipv4() {
    local ip=$1 octet
    local -a parts=()

    [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a parts <<< "$ip"
    for octet in "${parts[@]}"; do
        if [ "$((10#$octet))" -gt 255 ]; then
            return 1
        fi
    done
    return 0
}

valid_ipv6() {
    local ip=$1 left right colons left_groups=0 right_groups=0

    [[ $ip == *:* ]] || return 1
    [[ $ip =~ ^[0-9A-Fa-f:]+$ ]] || return 1

    if [[ $ip == *::* ]]; then
        # At most one "::" is allowed.
        [[ ${ip#*::} != *::* ]] || return 1

        left=${ip%%::*}
        right=${ip#*::}

        if [ -n "$left" ]; then
            [[ $left =~ ^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4})*$ ]] || return 1
            colons=${left//[^:]/}
            left_groups=$(( ${#colons} + 1 ))
        fi
        if [ -n "$right" ]; then
            [[ $right =~ ^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4})*$ ]] || return 1
            colons=${right//[^:]/}
            right_groups=$(( ${#colons} + 1 ))
        fi

        [ $((left_groups + right_groups)) -le 7 ]
        return
    fi

    [[ $ip =~ ^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){7}$ ]]
}

valid_ip() {
    valid_ipv4 "$1" || valid_ipv6 "$1"
}

valid_cidr() {
    local cidr=$1 addr prefix prefix_num

    [[ $cidr == */* ]] || return 1
    addr=${cidr%/*}
    prefix=${cidr#*/}

    valid_ipv4 "$addr" || return 1
    [[ $prefix =~ ^[0-9]{1,2}$ ]] || return 1
    prefix_num=$((10#$prefix))
    [ "$prefix_num" -ge 1 ] && [ "$prefix_num" -le 32 ]
}

prefix_to_netmask() {
    local prefix=$1 mask
    mask=$(( (0xffffffff << (32 - prefix)) & 0xffffffff ))
    printf '%d.%d.%d.%d\n' \
        $(( (mask >> 24) & 255 )) \
        $(( (mask >> 16) & 255 )) \
        $(( (mask >> 8) & 255 )) \
        $(( mask & 255 ))
}

prompt_read() {
    local __var=$1 __text=$2 __value=""

    printf '%s' "$__text"
    if ! IFS= read -r __value; then
        printf '\n'
        die "Failed to read input."
    fi
    printf -v "$__var" '%s' "$__value"
}

collect_dns_servers() {
    local use_defaults=${1:-1}
    local dns1="" dns2="" def1="" def2=""
    local -a cur_dns=()

    if [ "$use_defaults" -eq 1 ]; then
        mapfile -t cur_dns < <(current_dns_servers)
        def1=${cur_dns[0]:-}
        def2=${cur_dns[1]:-}

        if [ -n "$def1" ]; then
            printf 'Current DNS servers: %s\n' "$(join_words "${cur_dns[@]}")"
        fi
    fi

    read_dns_value dns1 "DNS server 1" "$def1"
    read_dns_value dns2 "DNS server 2" "$def2"

    if [ -z "$dns1" ] && [ -n "$dns2" ]; then
        die "DNS server 1 is required when DNS server 2 is provided."
    fi

    DNS_SERVERS=()
    if [ -n "$dns1" ]; then
        DNS_SERVERS+=("$dns1")
    fi
    if [ -n "$dns2" ] && [ "$dns2" != "$dns1" ]; then
        DNS_SERVERS+=("$dns2")
    fi

    if [ "${#DNS_SERVERS[@]}" -eq 0 ]; then
        warn "No DNS servers provided; only the static address will be changed."
    fi
}

read_dns_value() {
    local __var=$1 __label=$2 __default=$3 __val=""

    while true; do
        if [ -n "$__default" ]; then
            prompt_read __val "$__label [$__default]: "
            [ -n "$__val" ] || __val=$__default
        else
            prompt_read __val "$__label (optional, Enter to skip): "
        fi

        if [ -z "$__val" ]; then
            printf -v "$__var" '%s' ""
            return 0
        fi
        if valid_ip "$__val"; then
            printf -v "$__var" '%s' "$__val"
            return 0
        fi
        warn "Invalid DNS server address: $__val"
    done
}

current_dns_servers() {
    if command -v resolvectl >/dev/null 2>&1 &&
       systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        resolvectl dns "$IFACE" 2>/dev/null |
            sed -n 's/^.*):[[:space:]]*//p' |
            tr ' ' '\n' |
            awk 'NF' |
            grep -vE '^(127\.0\.0\.53|127\.0\.0\.1|::1)$' || true
    else
        awk '/^[[:space:]]*nameserver[[:space:]]/{print $2}' "$RESOLV_FILE" 2>/dev/null || true
    fi
}

join_dns_csv() {
    local out="" d
    for d in "${DNS_SERVERS[@]}"; do
        out+="${out:+,}$d"
    done
    printf '%s' "$out"
}

join_dns_space() {
    local out="" d
    for d in "${DNS_SERVERS[@]}"; do
        out+="${out:+ }$d"
    done
    printf '%s' "$out"
}

# IFS is newline/tab in this script, so "${array[*]}" would join with a
# newline. Use this helper for one-line display.
join_words() {
    local IFS=' '
    printf '%s' "$*"
}

create_network_backup_dir() {
    local stamp
    stamp=$(date '+%Y%m%d-%H%M%S')
    NET_BACKUP_DIR="$BACKUP_DIR/net-${stamp}.$$"
    ensure_dir "$NET_BACKUP_DIR" 0700
    log "Network backups: $NET_BACKUP_DIR"
}

nm_connection_name() {
    local uuid=$1
    nmcli -t -f UUID,NAME connection show 2>/dev/null |
        awk -F: -v u="$uuid" '$1 == u {print $2; exit}' || true
}

nm_get() {
    local uuid=$1 field=$2 out=""
    out=$(nmcli -g "$field" connection show "$uuid" 2>/dev/null || true)
    out=${out//$'\n'/,}
    out=${out// | /,}
    out=${out//\\:/:}
    out=${out%,}
    printf '%s' "$out"
}

capture_nm_state() {
    local uuid=$1
    NM_OLD_METHOD=$(nm_get "$uuid" ipv4.method)
    NM_OLD_ADDR=$(nm_get "$uuid" ipv4.addresses)
    NM_OLD_GATEWAY=$(nm_get "$uuid" ipv4.gateway)
    NM_OLD_DNS=$(nm_get "$uuid" ipv4.dns)
    NM_OLD_IGNORE_DNS=$(nm_get "$uuid" ipv4.ignore-auto-dns)
}

restore_networkmanager() {
    local uuid=$BACKEND_ID

    if [ -z "$uuid" ] || [ -z "$NM_OLD_METHOD" ]; then
        warn "No saved NetworkManager state."
        return 1
    fi

    log "Restoring NetworkManager connection '$uuid'..."
    # Restore every saved field, including addresses/gateway that may have
    # existed while the connection was still in automatic mode.
    nmcli connection modify "$uuid" \
        ipv4.method "$NM_OLD_METHOD" \
        ipv4.addresses "$NM_OLD_ADDR" \
        ipv4.gateway "$NM_OLD_GATEWAY" \
        ipv4.dns "$NM_OLD_DNS" \
        ipv4.ignore-auto-dns "${NM_OLD_IGNORE_DNS:-no}" || return 1
    nmcli connection up "$uuid" || return 1
}

apply_networkmanager() {
    local uuid=$1 dns_csv
    local -a cmd=()

    capture_nm_state "$uuid"
    nmcli -t -f ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns \
        connection show "$uuid" > "$NET_BACKUP_DIR/NetworkManager-${uuid}.txt" 2>&1 || \
        warn "Could not save previous NetworkManager settings."

    log "Configuring NetworkManager connection '$(nm_connection_name "$uuid")'..."
    cmd=(connection modify "$uuid" ipv4.method manual
        ipv4.addresses "$STATIC_CIDR" ipv4.gateway "$GATEWAY")

    if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
        dns_csv=$(join_dns_csv)
        cmd+=(ipv4.dns "$dns_csv" ipv4.ignore-auto-dns yes)
    fi

    nmcli "${cmd[@]}" || die "Failed to modify NetworkManager connection '$uuid'."
    nmcli connection up "$uuid" || die "Failed to activate NetworkManager connection '$uuid'."
    NET_BACKEND_DESC="NetworkManager ($(nm_connection_name "$uuid"))"
}

restore_networkd_file() {
    local file=$1 old=$2

    if [ -n "$old" ] && [ -f "$old" ]; then
        cp -a -- "$old" "$file" || warn "Failed to restore $file."
    else
        rm -f -- "$file"
    fi

    if command -v networkctl >/dev/null 2>&1; then
        networkctl reload >/dev/null 2>&1 || true
        networkctl reconfigure "$IFACE" >/dev/null 2>&1 || true
    else
        systemctl reload systemd-networkd >/dev/null 2>&1 || true
    fi
}

apply_networkd() {
    local dir="/etc/systemd/network"
    local file="$dir/99-github520-${IFACE}.network"
    local old=""
    local d

    [ -d "$dir" ] || die "systemd-networkd is active but $dir is missing."

    if [ -e "$file" ]; then
        old="$NET_BACKUP_DIR/99-github520-${IFACE}.network"
        cp -a -- "$file" "$old" || die "Failed to back up $file."
    fi
    NETWORKD_FILE=$file
    NETWORKD_OLD=$old

    log "Writing systemd-networkd config: $file"
    {
        printf '[Match]\nName=%s\n\n' "$IFACE"
        printf '[Network]\nDHCP=no\n'
        printf 'Address=%s\n' "$STATIC_CIDR"
        printf 'Gateway=%s\n' "$GATEWAY"
        for d in "${DNS_SERVERS[@]}"; do
            printf 'DNS=%s\n' "$d"
        done
    } > "$file"
    chmod 644 "$file"

    if command -v networkctl >/dev/null 2>&1; then
        networkctl reload || { restore_networkd_file "$file" "$old"; die "networkctl reload failed."; }
        networkctl reconfigure "$IFACE" || { restore_networkd_file "$file" "$old"; die "networkctl reconfigure failed."; }
    else
        systemctl reload systemd-networkd || { restore_networkd_file "$file" "$old"; die "Failed to reload systemd-networkd."; }
    fi

    NET_BACKEND_DESC="systemd-networkd ($file)"
}

restore_ifupdown() {
    if [ -z "$IFUPDOWN_SRC" ] || [ -z "$IFUPDOWN_OLD" ] || [ ! -f "$IFUPDOWN_OLD" ]; then
        warn "No saved ifupdown configuration."
        return 1
    fi
    log "Restoring $IFUPDOWN_SRC..."
    cp -a -- "$IFUPDOWN_OLD" "$IFUPDOWN_SRC" || return 1
    ifdown "$IFACE" >/dev/null 2>&1 || true
    ifup "$IFACE" >/dev/null 2>&1 || return 1
    return 0
}

apply_ifupdown() {
    local src=$BACKEND_FILE
    local base="$TMP_DIR/interfaces.base"
    local new="$TMP_DIR/interfaces.new"
    local old="$NET_BACKUP_DIR/$(basename -- "$src")"
    local netmask dns_space=""

    [ -n "$src" ] && [ -f "$src" ] || die "ifupdown configuration was not found."
    cp -a -- "$src" "$old" || die "Failed to back up $src."
    IFUPDOWN_SRC=$src
    IFUPDOWN_OLD=$old

    netmask=$(prefix_to_netmask "$STATIC_PREFIX")
    dns_space=$(join_dns_space)

    log "Rewriting ifupdown stanza for $IFACE in $src"
    awk -v iface="$IFACE" '
        BEGIN { skip = 0 }
        {
            if (skip) {
                if ($0 ~ /^[[:space:]]*(iface|auto|allow-|source|mapping)/ ||
                    $0 ~ /^[[:space:]]*$/) {
                    skip = 0
                } else {
                    next
                }
            }
            # Only replace the IPv4 stanza; keep any inet6 stanza intact.
            if ($0 ~ /^[[:space:]]*iface[[:space:]]+/ && $2 == iface &&
                ($3 == "inet" || $3 == "")) {
                skip = 1
                next
            }
            print
        }
    ' "$src" > "$base" || die "Failed to parse $src."

    {
        cat "$base"
        printf '\n'
        if ! awk -v i="$IFACE" '
            $1 == "auto" || $1 == "allow-auto" || $1 == "allow-hotplug" {
                for (n = 2; n <= NF; n++) if ($n == i) found = 1
            }
            END { exit(found ? 0 : 1) }
        ' "$base"; then
            printf 'auto %s\n' "$IFACE"
        fi
        printf 'iface %s inet static\n' "$IFACE"
        printf '    address %s\n' "$STATIC_ADDR"
        printf '    netmask %s\n' "$netmask"
        printf '    gateway %s\n' "$GATEWAY"
        if [ -n "$dns_space" ]; then
            printf '    dns-nameservers %s\n' "$dns_space"
        fi
    } > "$new"

    cat -- "$new" > "$src" || { cp -a -- "$old" "$src"; die "Failed to write $src."; }

    if command -v ifquery >/dev/null 2>&1; then
        ifquery "$IFACE" >/dev/null 2>&1 || {
            cp -a -- "$old" "$src"
            die "ifquery rejected the new configuration."
        }
    fi

    ifdown "$IFACE" >/dev/null 2>&1 || true
    if ! ifup "$IFACE"; then
        cp -a -- "$old" "$src" 2>/dev/null || true
        ifup "$IFACE" >/dev/null 2>&1 || true
        die "ifup failed; previous configuration restored."
    fi

    NET_BACKEND_DESC="ifupdown ($src)"
}

write_resolv_conf() {
    local backup new d

    if [ -L "$RESOLV_FILE" ]; then
        warn "$RESOLV_FILE is a symlink; refusing to overwrite it."
        return 0
    fi

    backup="$BACKUP_DIR/resolv.conf.$(date '+%Y%m%d-%H%M%S').$$"
    if [ -z "$RESOLV_BACKUP" ]; then
        cp -L -p -- "$RESOLV_FILE" "$backup" 2>/dev/null || {
            warn "Could not back up $RESOLV_FILE."
            backup=""
        }
        RESOLV_BACKUP=$backup
    fi

    new="$TMP_DIR/resolv.new"
    {
        grep -vE '^[[:space:]]*nameserver[[:space:]]' "$RESOLV_FILE" 2>/dev/null || true
        for d in "${DNS_SERVERS[@]}"; do
            printf 'nameserver %s\n' "$d"
        done
    } > "$new"

    cat -- "$new" > "$RESOLV_FILE" || die "Failed to write $RESOLV_FILE."
}

apply_dns_settings() {
    local d

    [ "${#DNS_SERVERS[@]}" -gt 0 ] || return 0

    if command -v resolvectl >/dev/null 2>&1 &&
       systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if resolvectl dns "$IFACE" "${DNS_SERVERS[@]}"; then
            DNS_VIA_RESOLVECTL=1
        else
            warn "resolvectl could not set DNS."
        fi
        resolvectl flush-caches >/dev/null 2>&1 || true
        return 0
    fi

    if command -v resolvconf >/dev/null 2>&1; then
        if {
            for d in "${DNS_SERVERS[@]}"; do
                printf 'nameserver %s\n' "$d"
            done
        } | resolvconf -a "github520-$IFACE"; then
            DNS_VIA_RESOLVCONF=1
        else
            warn "resolvconf could not apply DNS."
        fi
        return 0
    fi

    write_resolv_conf
}

reapply_dns_networkmanager() {
    local dns_csv

    [ -n "$BACKEND_ID" ] || return 1
    dns_csv=$(join_dns_csv)
    [ -n "$dns_csv" ] || return 1

    nmcli connection modify "$BACKEND_ID" \
        ipv4.dns "$dns_csv" ipv4.ignore-auto-dns yes || return 1
    nmcli connection up "$BACKEND_ID" || return 1
}

reapply_dns_networkd() {
    local file=$NETWORKD_FILE d tmp

    [ -n "$file" ] && [ -f "$file" ] || return 1
    tmp=$(mktemp "${TMPDIR:-/tmp}/github520-networkd.XXXXXX") || return 1
    awk '!/^[[:space:]]*DNS=/' "$file" > "$tmp" || {
        rm -f -- "$tmp"
        return 1
    }
    for d in "${DNS_SERVERS[@]}"; do
        printf 'DNS=%s\n' "$d" >> "$tmp"
    done
    cat -- "$tmp" > "$file" || {
        rm -f -- "$tmp"
        return 1
    }
    rm -f -- "$tmp"

    if command -v networkctl >/dev/null 2>&1; then
        networkctl reload || return 1
        networkctl reconfigure "$IFACE" || return 1
    else
        systemctl reload systemd-networkd || return 1
    fi
}

reapply_dns_ifupdown() {
    local src=$IFUPDOWN_SRC dns_space tmp

    [ -n "$src" ] && [ -f "$src" ] || return 1
    dns_space=$(join_dns_space)
    [ -n "$dns_space" ] || return 1

    tmp=$(mktemp "${TMPDIR:-/tmp}/github520-interfaces.XXXXXX") || return 1
    awk -v iface="$IFACE" -v dns="$dns_space" '
        function add_dns() {
            if (in_target && !dns_done && dns != "") {
                print "    dns-nameservers " dns
                dns_done = 1
            }
        }
        /^[[:space:]]*iface[[:space:]]+/ {
            add_dns()
            in_target = ($2 == iface && ($3 == "inet" || $3 == ""))
            if (in_target) found = 1
            dns_done = 0
            print
            next
        }
        in_target && /^[[:space:]]*dns-nameservers[[:space:]]/ { next }
        { print }
        END {
            add_dns()
            if (!found) exit 1
        }
    ' "$src" > "$tmp" || {
        rm -f -- "$tmp"
        return 1
    }
    cat -- "$tmp" > "$src" || {
        rm -f -- "$tmp"
        return 1
    }
    rm -f -- "$tmp"

    ifdown "$IFACE" >/dev/null 2>&1 || true
    if ! ifup "$IFACE"; then
        if [ -n "$IFUPDOWN_OLD" ] && [ -f "$IFUPDOWN_OLD" ]; then
            cp -a -- "$IFUPDOWN_OLD" "$src" 2>/dev/null || true
            ifup "$IFACE" >/dev/null 2>&1 || true
        fi
        return 1
    fi
}

reapply_dns_backend() {
    case "$BACKEND" in
        networkmanager) reapply_dns_networkmanager ;;
        networkd) reapply_dns_networkd ;;
        ifupdown) reapply_dns_ifupdown ;;
        *) return 1 ;;
    esac || return 1

    apply_dns_settings
}

rollback_network_config() {
    local rc=0

    if [ "$DNS_VIA_RESOLVECTL" -eq 1 ] && [ -n "$IFACE" ] &&
       command -v resolvectl >/dev/null 2>&1; then
        resolvectl revert "$IFACE" >/dev/null 2>&1 || true
        DNS_VIA_RESOLVECTL=0
    fi

    if [ "$DNS_VIA_RESOLVCONF" -eq 1 ] && command -v resolvconf >/dev/null 2>&1; then
        resolvconf -d "github520-$IFACE" >/dev/null 2>&1 || true
        DNS_VIA_RESOLVCONF=0
    fi

    case "$BACKEND" in
        networkmanager) restore_networkmanager || rc=1 ;;
        networkd)
            if [ -n "$NETWORKD_FILE" ]; then
                restore_networkd_file "$NETWORKD_FILE" "$NETWORKD_OLD" || rc=1
            fi
            ;;
        ifupdown) restore_ifupdown || rc=1 ;;
        *) rc=1 ;;
    esac

    if [ -n "$RESOLV_BACKUP" ] && [ -f "$RESOLV_BACKUP" ]; then
        cat -- "$RESOLV_BACKUP" > "$RESOLV_FILE" 2>/dev/null || rc=1
    fi

    return "$rc"
}

wait_for_static_ip() {
    local tries=${1:-12} i
    local -a addrs=()

    for ((i = 1; i <= tries; i++)); do
        addrs=()
        mapfile -t addrs < <(ip -o -4 addr show dev "$IFACE" 2>/dev/null | awk '{print $4}')
        if [ "${#addrs[@]}" -gt 0 ] &&
           printf '%s\n' "${addrs[@]}" | grep -Fxq "$STATIC_CIDR"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

verify_static_network() {
    log "Verifying static network configuration..."
    if ! wait_for_static_ip 12; then
        warn "Static address $STATIC_CIDR is not active on $IFACE."
        return 1
    fi

    if ! ip -4 route show default 2>/dev/null | grep -Fq "via $GATEWAY"; then
        warn "Default route via $GATEWAY was not confirmed."
    fi

    ok "Static IPv4 configuration is active on $IFACE."
    return 0
}

run_limited() {
    local seconds=$1

    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    else
        "$@"
    fi
}

check_dns_reachability() {
    local d

    if ! command -v ping >/dev/null 2>&1; then
        warn "ping is not installed; skipping DNS reachability check."
        return 0
    fi

    for d in "${DNS_SERVERS[@]}"; do
        if [ "${d#*:}" != "$d" ]; then
            if ping -6 -c 1 -W 2 "$d" >/dev/null 2>&1; then
                log "DNS server $d responded to ping."
            else
                warn "DNS server $d did not respond to ping; continuing with resolution test."
            fi
        else
            if ping -c 1 -W 2 "$d" >/dev/null 2>&1; then
                log "DNS server $d responded to ping."
            else
                warn "DNS server $d did not respond to ping; continuing with resolution test."
            fi
        fi
    done
    return 0
}

dns_lookup_check() {
    local d domain out
    local -a domains=(example.com www.example.com)

    for domain in "${domains[@]}"; do
        if command -v dig >/dev/null 2>&1; then
            for d in "${DNS_SERVERS[@]}"; do
                out=$(run_limited 5 dig +time=2 +tries=1 "@$d" "$domain" A +short 2>/dev/null || true)
                if [ -n "$out" ]; then
                    return 0
                fi
            done
        fi

        if command -v getent >/dev/null 2>&1; then
            if run_limited 5 getent ahostsv4 "$domain" >/dev/null 2>&1; then
                return 0
            fi
        fi

        if command -v resolvectl >/dev/null 2>&1; then
            if run_limited 5 resolvectl query "$domain" >/dev/null 2>&1; then
                return 0
            fi
        fi

        if command -v curl >/dev/null 2>&1; then
            if run_limited 8 curl -fsS --max-time 5 --noproxy '*' "https://$domain" \
                >/dev/null 2>&1; then
                return 0
            fi
        fi
    done

    return 1
}

dns_config_matches() {
    local current d found
    local -a active_dns=()

    mapfile -t active_dns < <(current_dns_servers)
    [ "${#active_dns[@]}" -gt 0 ] || return 1

    for d in "${DNS_SERVERS[@]}"; do
        found=0
        for current in "${active_dns[@]}"; do
            if [ "$current" = "$d" ]; then
                found=1
                break
            fi
        done
        [ "$found" -eq 1 ] || return 1
    done
    return 0
}

verify_dns_resolution() {
    local attempt

    [ "${#DNS_SERVERS[@]}" -gt 0 ] || return 0

    for attempt in 1 2 3; do
        log "DNS validation attempt $attempt/3..."
        flush_dns_caches

        if ! dns_config_matches; then
            warn "The configured DNS servers are not active yet."
        else
            check_dns_reachability

            if dns_lookup_check; then
                ok "DNS resolution succeeded."
                return 0
            fi
        fi

        warn "DNS validation attempt $attempt/3 failed."
        if [ "$attempt" -lt 3 ]; then
            sleep 2
        fi
    done

    return 1
}

handle_dns_failure() {
    local choice secondary

    while true; do
        printf '\n'
        warn "DNS validation failed after 3 attempts."
        printf '  [r] Retry DNS validation\n'
        printf '  [c] Change DNS servers and apply again\n'
        printf '  [a] Restore the previous network configuration\n'
        prompt_read choice "Select r, c or a: "
        choice=${choice,,}

        case "$choice" in
            r|retry)
                if verify_dns_resolution; then
                    DNS_VALIDATION_RESTORED=0
                    return 0
                fi
                ;;
            c|change)
                collect_dns_servers 0
                if [ "${#DNS_SERVERS[@]}" -eq 0 ]; then
                    warn "At least one DNS server is required when changing DNS."
                    continue
                fi
                if ! reapply_dns_backend; then
                    warn "Failed to apply the new DNS servers."
                    continue
                fi
                if verify_dns_resolution; then
                    DNS_VALIDATION_RESTORED=0
                    return 0
                fi
                ;;
            a|restore)
                if ! rollback_network_config; then
                    warn "Failed to restore the previous network configuration."
                    continue
                fi
                NETWORK_ROLLBACK_PENDING=0
                NETWORK_CONFIGURED=0

                while true; do
                    prompt_read secondary \
                        "Previous network restored. [k]eep and continue installation, or [a]bort: "
                    case "${secondary,,}" in
                        k|keep)
                            DNS_VALIDATION_RESTORED=1
                            return 0
                            ;;
                        a|abort)
                            die "Installation aborted by user."
                            ;;
                        *)
                            warn "Enter k or a."
                            ;;
                    esac
                done
                ;;
            *)
                warn "Enter r, c or a."
                ;;
        esac
    done
}

configure_static_network() {
    local ip_input="" pfx=24

    require_tty
    [ -n "$IFACE" ] || die "No default IPv4 interface; cannot configure static networking."
    select_config_backend

    while [ -z "$GATEWAY" ] || ! valid_ipv4 "$GATEWAY"; do
        prompt_read GATEWAY "Gateway IPv4 address: "
        if ! valid_ipv4 "$GATEWAY"; then
            warn "Invalid gateway: $GATEWAY"
            GATEWAY=""
        fi
    done

    printf '\nCurrent network configuration:\n'
    printf '  Interface : %s\n' "$IFACE"
    printf '  Address   : %s\n' "${CURRENT_CIDR:-unknown}"
    printf '  Gateway   : %s\n' "$GATEWAY"

    while true; do
        if [ -n "$CURRENT_CIDR" ]; then
            prompt_read ip_input "Static IPv4 address in CIDR form [$CURRENT_CIDR]: "
            [ -n "$ip_input" ] || ip_input=$CURRENT_CIDR
        else
            prompt_read ip_input "Static IPv4 address in CIDR form (e.g. 192.168.1.50/24): "
        fi

        if [[ $ip_input != */* ]]; then
            pfx=24
            if [[ $CURRENT_CIDR == */* ]]; then
                pfx=${CURRENT_CIDR#*/}
            fi
            ip_input="${ip_input}/${pfx}"
            log "No prefix supplied; using /$pfx."
        fi

        if valid_cidr "$ip_input"; then
            break
        fi
        warn "Invalid IPv4 CIDR: $ip_input"
    done

    STATIC_CIDR=$ip_input
    STATIC_ADDR=${ip_input%/*}
    STATIC_PREFIX=${ip_input#*/}

    collect_dns_servers

    printf '\nAbout to apply:\n'
    printf '  Interface : %s\n' "$IFACE"
    printf '  Address   : %s\n' "$STATIC_CIDR"
    printf '  Gateway   : %s\n' "$GATEWAY"
    if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
        printf '  DNS       : %s\n' "$(join_words "${DNS_SERVERS[@]}")"
    fi
    if ! confirm_action "Apply this static network configuration?"; then
        log "Network configuration cancelled."
        return 0
    fi

    create_network_backup_dir
    NETWORK_ROLLBACK_PENDING=1

    case "$BACKEND" in
        networkmanager) apply_networkmanager "$BACKEND_ID" ;;
        networkd) apply_networkd ;;
        ifupdown) apply_ifupdown ;;
        *) die "Unknown network backend: $BACKEND" ;;
    esac

    apply_dns_settings

    if ! verify_static_network; then
        rollback_network_config || warn "Network rollback was incomplete."
        NETWORK_ROLLBACK_PENDING=0
        die "Static network verification failed; previous configuration restored."
    fi

    DNS_VALIDATION_RESTORED=0
    if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
        if ! verify_dns_resolution; then
            handle_dns_failure
            if [ "$DNS_VALIDATION_RESTORED" -eq 1 ]; then
                return 0
            fi
        fi
    fi

    NETWORK_ROLLBACK_PENDING=0
    NETWORK_CONFIGURED=1
    ok "Static network configuration completed via $NET_BACKEND_DESC."
}

confirm_action() {
    local prompt=$1 answer=""

    require_tty
    prompt_read answer "$prompt [y/N]: "
    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

ask_network_change() {
    local answer=""

    if [ -z "$IFACE" ]; then
        log "No default IPv4 interface; skipping static network configuration."
        return 0
    fi

    printf '\n'
    prompt_read answer "Change the local static IPv4 address / DNS now? [y/N]: "
    case "$answer" in
        y|Y|yes|YES|Yes)
            configure_static_network
            ;;
        *)
            log "No network changes requested."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# GitHub520 sources, hosts update
# -----------------------------------------------------------------------------
acquire_update_lock() {
    local lock=$LOCK_FILE

    [ -d /run ] || lock="${TMPDIR:-/tmp}/github520-hosts.lock"
    command -v flock >/dev/null 2>&1 || return 0

    if ! exec 9>"$lock"; then
        warn "Could not open lock file $lock; continuing without locking."
        return 0
    fi
    if ! flock -w 120 9; then
        die "Another GitHub520 hosts update is still running."
    fi
}

release_update_lock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 9 >/dev/null 2>&1 || true
    fi
    exec 9>&- 2>/dev/null || true
}

prepare_github520_download() {
    command -v curl >/dev/null 2>&1 || die "curl is required."

    # fetch_hosts_block performs the real per-source probe and validation.
    # A separate probe here would download every source twice.
    log "Preparing GitHub520 download..."
    log "Upstream: $GITHUB520_REPO_URL"
}

validate_hosts_block() {
    local file=$1 start end entries start_line end_line

    [ -s "$file" ] || { warn "Downloaded content is empty."; return 1; }

    start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$file" || true)
    end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$file" || true)

    if [ "$start" -ne 1 ] || [ "$end" -ne 1 ]; then
        warn "Invalid GitHub520 block markers (start=$start end=$end)."
        return 1
    fi

    start_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$file" |
        head -n 1 | cut -d: -f1 || true)
    end_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$file" |
        head -n 1 | cut -d: -f1 || true)
    if [ -n "$start_line" ] && [ -n "$end_line" ] && [ "$start_line" -ge "$end_line" ]; then
        warn "Invalid GitHub520 block: end marker appears before start marker."
        return 1
    fi

    entries=$(grep -cE '^[[:space:]]*([0-9]{1,3}\.){3}[0-9]{1,3}[[:space:]]+[A-Za-z0-9._-]+' "$file" || true)
    if [ "$entries" -lt 5 ]; then
        warn "Too few host entries: $entries"
        return 1
    fi

    HOSTS_DOWNLOAD_ENTRIES=$entries
    ok "Valid GitHub520 block ($entries entries)."
    return 0
}

fetch_hosts_block() {
    local out="$TMP_DIR/hosts.remote"
    local try="$TMP_DIR/hosts.remote.try"
    local url code index=0 total=${#HOSTS_SOURCES[@]}

    log "Downloading GitHub520 hosts with source fallback..."

    for url in "${HOSTS_SOURCES[@]}"; do
        index=$((index + 1))
        log "Source $index/$total: $url"
        rm -f -- "$try"
        code=""

        if ! code=$(curl -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 8 --max-time 25 \
            --retry 1 --retry-delay 1 -o "$try" -w '%{http_code}' "$url"); then
            warn "Download failed${code:+ (HTTP $code)}; next source."
            continue
        fi
        if [ "$code" != "200" ]; then
            warn "HTTP $code; next source."
            continue
        fi
        if ! validate_hosts_block "$try"; then
            warn "Invalid content; next source."
            continue
        fi

        mv -f -- "$try" "$out" || die "Failed to stage hosts file."
        SELECTED_HOSTS_URL=$url
        ok "Using source $index/$total: $url"
        return 0
    done

    rm -f -- "$try"
    die "All GitHub520 sources failed. No changes were made to $HOSTS_FILE."
}

count_github520_entries() {
    local file=$1

    awk '
        {
            line = tolower($0)
            if (line ~ /^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start/) {
                in_block = 1
                next
            }
            if (line ~ /^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end/) {
                in_block = 0
                next
            }
        }
        in_block && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { count++ }
        END { print count + 0 }
    ' "$file" 2>/dev/null || printf '0\n'
}

prune_hosts_backups() {
    local -a files=()

    mapfile -t files < <(ls -1t "$BACKUP_DIR"/hosts.[0-9]* 2>/dev/null || true)
    if [ "${#files[@]}" -gt "$MAX_HOSTS_BACKUPS" ]; then
        rm -f -- "${files[@]:MAX_HOSTS_BACKUPS}"
    fi
}

ensure_original_hosts_backup() {
    [ -f "$HOSTS_FILE" ] || die "$HOSTS_FILE does not exist."
    ensure_dir "$BACKUP_DIR" 0700

    if [ -f "$ORIGINAL_HOSTS_BACKUP" ]; then
        log "Original hosts backup already exists: $ORIGINAL_HOSTS_BACKUP"
        return 0
    fi

    cp -L -p -- "$HOSTS_FILE" "$ORIGINAL_HOSTS_BACKUP" || \
        die "Failed to create original hosts backup."
    cmp -s -- "$HOSTS_FILE" "$ORIGINAL_HOSTS_BACKUP" || \
        die "Original hosts backup verification failed."
    chmod 0644 "$ORIGINAL_HOSTS_BACKUP" 2>/dev/null || true
    log "Original hosts backup: $ORIGINAL_HOSTS_BACKUP"
}

backup_hosts_file() {
    local stamp

    [ -f "$HOSTS_FILE" ] || die "$HOSTS_FILE does not exist."
    ensure_dir "$BACKUP_DIR" 0700

    stamp=$(date '+%Y%m%d-%H%M%S')
    HOSTS_BACKUP="$BACKUP_DIR/hosts.${stamp}.$$"

    cp -L -p -- "$HOSTS_FILE" "$HOSTS_BACKUP" || die "Failed to back up $HOSTS_FILE."
    cmp -s -- "$HOSTS_FILE" "$HOSTS_BACKUP" || die "Backup verification failed."
    log "Hosts backup: $HOSTS_BACKUP"
    prune_hosts_backups
}

build_new_hosts() {
    local base="$TMP_DIR/hosts.base"
    local trimmed="$TMP_DIR/hosts.base.trim"
    local new="$TMP_DIR/hosts.new"
    local existing_start existing_end new_start new_end
    local existing_start_line existing_end_line

    existing_start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" || true)
    existing_end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" || true)
    if [ "$existing_start" -ne "$existing_end" ]; then
        die "$HOSTS_FILE contains an unbalanced GitHub520 block."
    fi

    existing_start_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" |
        head -n 1 | cut -d: -f1 || true)
    existing_end_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" |
        head -n 1 | cut -d: -f1 || true)
    if [ -n "$existing_start_line" ] && [ -n "$existing_end_line" ] &&
       [ "$existing_start_line" -ge "$existing_end_line" ]; then
        die "$HOSTS_FILE has its GitHub520 end marker before the start marker."
    fi

    awk '
        {
            line = tolower($0)
            if (line ~ /^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start/) {
                skip = 1
                next
            }
            if (line ~ /^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end/) {
                skip = 0
                next
            }
            if (!skip) print
        }
    ' "$HOSTS_FILE" > "$base" || die "Failed to read $HOSTS_FILE."

    awk '
        { lines[NR] = $0 }
        END {
            last = NR
            while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
            for (i = 1; i <= last; i++) print lines[i]
        }
    ' "$base" > "$trimmed"

    {
        cat "$trimmed"
        printf '\n'
        cat "$TMP_DIR/hosts.remote"
        printf '\n'
    } > "$new"

    new_start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$new" || true)
    new_end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$new" || true)
    if [ "$new_start" -ne 1 ] || [ "$new_end" -ne 1 ]; then
        die "Generated hosts file is invalid."
    fi
}

install_new_hosts() {
    local attrs

    if cmp -s -- "$TMP_DIR/hosts.new" "$HOSTS_FILE"; then
        HOSTS_ENTRY_COUNT=$(count_github520_entries "$HOSTS_FILE")
        HOSTS_COMMITTED=1
        log "Hosts already up to date ($HOSTS_ENTRY_COUNT GitHub520 entries)."
        return 0
    fi

    [ -w "$HOSTS_FILE" ] || die "$HOSTS_FILE is not writable."

    if command -v lsattr >/dev/null 2>&1; then
        attrs=$(lsattr -d "$HOSTS_FILE" 2>/dev/null | awk '{print $1}' || true)
        case "$attrs" in
            *i*) die "$HOSTS_FILE has the immutable attribute; run 'chattr -i' first." ;;
        esac
    fi

    backup_hosts_file
    HOSTS_WRITTEN=1

    log "Writing $HOSTS_FILE..."
    cat -- "$TMP_DIR/hosts.new" > "$HOSTS_FILE" || die "Failed to write $HOSTS_FILE."

    HOSTS_ENTRY_COUNT=$(count_github520_entries "$HOSTS_FILE")
    if [ "$HOSTS_ENTRY_COUNT" -lt "$HOSTS_DOWNLOAD_ENTRIES" ]; then
        die "Verification failed: expected at least $HOSTS_DOWNLOAD_ENTRIES entries, found $HOSTS_ENTRY_COUNT."
    fi

    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$HOSTS_FILE" >/dev/null 2>&1 || true
    fi

    HOSTS_COMMITTED=1
    ok "$HOSTS_FILE updated with $HOSTS_ENTRY_COUNT GitHub520 entries."
}

flush_dns_caches() {
    log "Flushing DNS caches..."

    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
    fi
    if command -v nscd >/dev/null 2>&1; then
        nscd -i hosts >/dev/null 2>&1 || true
    fi
    if command -v dnsmasq >/dev/null 2>&1 &&
       systemctl is-active --quiet dnsmasq 2>/dev/null; then
        # SIGHUP reloads /etc/hosts without dropping DNS service briefly.
        systemctl reload dnsmasq >/dev/null 2>&1 ||
            systemctl restart dnsmasq >/dev/null 2>&1 || true
    fi
}

apply_hosts_update() {
    acquire_update_lock
    prepare_github520_download
    fetch_hosts_block
    build_new_hosts
    install_new_hosts
    release_update_lock
}

# -----------------------------------------------------------------------------
# systemd timer/service
# -----------------------------------------------------------------------------
install_script_copy() {
    local src lib_src lib_file

    if [ "$PACKAGED_MODE" -eq 1 ]; then
        [ -x "$INSTALL_PATH" ] || die "Package-managed CLI is missing: $INSTALL_PATH"
        [ -f "$LIB_INSTALL_DIR/github520-common.sh" ] || \
            die "Package-managed shared library is missing: $LIB_INSTALL_DIR"
        log "Using package-managed CLI: $INSTALL_PATH"
        return 0
    fi

    src=$(readlink -f -- "$0" 2>/dev/null || true)
    [ -n "$src" ] || src="$PWD/$0"

    if [ "$src" = "$INSTALL_PATH" ]; then
        log "CLI is already installed at $INSTALL_PATH."
    else
        lib_src=${LIB_DIR:-}
        if [ -z "$lib_src" ] || [ ! -d "$lib_src" ]; then
            die "Shared library directory is unavailable; cannot install the CLI."
        fi

        ensure_dir "$LIB_INSTALL_DIR" 0755
        for lib_file in github520-common.sh "platform-${PLATFORM}.sh"; do
            [ -f "$lib_src/$lib_file" ] || \
                die "Shared library file is missing: $lib_src/$lib_file"
            install -m 0644 -- "$lib_src/$lib_file" "$LIB_INSTALL_DIR/$lib_file" || \
                die "Failed to install $LIB_INSTALL_DIR/$lib_file."
        done
        ok "Installed shared library: $LIB_INSTALL_DIR"

        ensure_dir "$(dirname -- "$INSTALL_PATH")" 0755
        install -m 0755 -- "$src" "$INSTALL_PATH" || die "Failed to install $INSTALL_PATH."
        ok "Installed CLI: $INSTALL_PATH"
    fi

    ln -sfn "$INSTALL_PATH" "$LEGACY_INSTALL_PATH" || \
        warn "Could not create compatibility symlink: $LEGACY_INSTALL_PATH"
}

install_timer() {
    local service_file="$UNIT_DIR/$SERVICE_NAME"
    local timer_file="$UNIT_DIR/$TIMER_NAME"

    install_script_copy

    if [ "$PACKAGED_MODE" -eq 1 ]; then
        [ -f "$service_file" ] || die "Packaged service unit is missing: $service_file"
        [ -f "$timer_file" ] || die "Packaged timer unit is missing: $timer_file"
        log "Using packaged systemd units from $UNIT_DIR."
    else
        log "Writing systemd units..."
        cat > "$service_file" <<EOF
[Unit]
Description=Update GitHub520 hosts entries
Documentation=https://github.com/WS-CatGirl/github520-deploy
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --update --systemd
Environment=LC_ALL=C
Nice=10
TimeoutStartSec=900
EOF

        cat > "$timer_file" <<EOF
[Unit]
Description=Hourly GitHub520 hosts update

[Timer]
OnActiveSec=5min
OnUnitActiveSec=1h
AccuracySec=1min
RandomizedDelaySec=30s
Persistent=true
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF

        chmod 0644 "$service_file" "$timer_file"
    fi

    systemctl daemon-reload || die "systemctl daemon-reload failed."
    systemctl enable "$TIMER_NAME" >/dev/null || die "Failed to enable $TIMER_NAME."
    systemctl restart "$TIMER_NAME" || die "Failed to start $TIMER_NAME."

    systemctl is-enabled --quiet "$TIMER_NAME" || die "$TIMER_NAME is not enabled."
    systemctl is-active --quiet "$TIMER_NAME" || die "$TIMER_NAME is not active."

    ensure_dir "$LOG_DIR" 0755
    printf '[%s] [ INFO ] Timer installed and enabled (hourly updates).\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >> "$UPDATE_LOG"
    chmod 0644 "$UPDATE_LOG" 2>/dev/null || true

    ok "Hourly timer enabled: $TIMER_NAME"
}

# -----------------------------------------------------------------------------
# CLI management: status, logs, restore, uninstall
# -----------------------------------------------------------------------------
latest_hosts_backup() {
    local latest=""

    latest=$(ls -1t "$BACKUP_DIR"/hosts.[0-9]* 2>/dev/null | head -n 1 || true)
    printf '%s' "$latest"
}

strip_github520_block_from_hosts() {
    local tmp starts ends first_start first_end

    [ -f "$HOSTS_FILE" ] || return 1

    starts=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" || true)
    ends=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" || true)
    if [ "$starts" -ne "$ends" ]; then
        warn "$HOSTS_FILE contains an unbalanced GitHub520 block (start=$starts end=$ends); refusing to strip it."
        return 1
    fi
    if [ "$starts" -eq 0 ]; then
        return 0
    fi

    first_start=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" |
        head -n 1 | cut -d: -f1 || true)
    first_end=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" |
        head -n 1 | cut -d: -f1 || true)
    if [ -n "$first_start" ] && [ -n "$first_end" ] && [ "$first_start" -ge "$first_end" ]; then
        warn "$HOSTS_FILE has its GitHub520 end marker before the start marker; refusing to strip it."
        return 1
    fi

    tmp=$(mktemp "${TMPDIR:-/tmp}/github520-strip.XXXXXX") || return 1

    if ! awk '
        {
            line = tolower($0)
            if (line ~ /^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start/) {
                skip = 1
                next
            }
            if (line ~ /^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end/) {
                skip = 0
                next
            }
            if (!skip) print
        }
    ' "$HOSTS_FILE" > "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi

    if ! cat -- "$tmp" > "$HOSTS_FILE"; then
        rm -f -- "$tmp"
        return 1
    fi

    rm -f -- "$tmp"
    return 0
}

restore_hosts_for_complete_uninstall() {
    local src=""

    if [ -f "$ORIGINAL_HOSTS_BACKUP" ]; then
        src=$ORIGINAL_HOSTS_BACKUP
    else
        src=$(latest_hosts_backup)
    fi

    if [ -n "$src" ] && [ -f "$src" ]; then
        log "Restoring $HOSTS_FILE from $src..."
        cp -L -p -- "$src" "$HOSTS_FILE" || return 1
    else
        warn "No hosts backup found; removing the GitHub520 block from the current file."
        [ -f "$HOSTS_FILE" ] || return 1
    fi

    strip_github520_block_from_hosts || return 1
    log "GitHub520 entries removed from $HOSTS_FILE."
    return 0
}

remove_systemd_units() {
    local service_file="$UNIT_DIR/$SERVICE_NAME"
    local timer_file="$UNIT_DIR/$TIMER_NAME"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "$TIMER_NAME" >/dev/null 2>&1 || true
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi

    if [ "$PACKAGED_MODE" -eq 1 ]; then
        rm -rf -- "/etc/systemd/system/$SERVICE_NAME.d" "/etc/systemd/system/$TIMER_NAME.d"
        rm -f -- "/etc/systemd/system/timers.target.wants/$TIMER_NAME"
        rm -f -- "/etc/systemd/system/multi-user.target.wants/$SERVICE_NAME"

        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload >/dev/null 2>&1 || true
        fi

        log "Disabled packaged systemd units: $TIMER_NAME, $SERVICE_NAME"
        return 0
    fi

    rm -f -- "$service_file" "$timer_file"
    rm -rf -- "/etc/systemd/system/$SERVICE_NAME.d" "/etc/systemd/system/$TIMER_NAME.d"
    rm -f -- "/etc/systemd/system/timers.target.wants/$TIMER_NAME"
    rm -f -- "/etc/systemd/system/multi-user.target.wants/$SERVICE_NAME"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    log "Removed systemd units: $TIMER_NAME, $SERVICE_NAME"
}

remove_installed_cli() {
    if [ "$PACKAGED_MODE" -eq 1 ]; then
        log "CLI and shared library are package-managed; leaving them in place."
        return 0
    fi

    rm -f -- "$INSTALL_PATH" "$LEGACY_INSTALL_PATH"
    log "Removed installed CLI: $INSTALL_PATH"

    if [ -d "$LIB_INSTALL_DIR" ]; then
        rm -rf -- "$LIB_INSTALL_DIR"
        log "Removed shared library: $LIB_INSTALL_DIR"
    fi
}

purge_installation_data() {
    rm -rf -- "$LOG_DIR" "$BACKUP_DIR"
    rm -f -- /etc/hosts.github520-backup.* 2>/dev/null || true
    rm -rf -- /tmp/${TMP_PREFIX}.* /tmp/${TMP_PREFIX}-update.* \
        /tmp/github520-strip.* /tmp/github520-restore.* 2>/dev/null || true
    log "Removed logs, backups and temporary files."
}

do_uninstall() {
    local mode=$1

    if [ "$mode" = "complete" ]; then
        if [ "$FORCE" -ne 1 ]; then
            warn "This will restore the original /etc/hosts and remove all GitHub520 data."
            if ! confirm_action "Completely uninstall $PROGRAM_LABEL?"; then
                log "Uninstall cancelled."
                exit 0
            fi
        fi
        log "Starting complete uninstall..."
    else
        log "Starting uninstall (hosts, logs and backups will be kept)..."
    fi

    remove_systemd_units

    if [ "$mode" = "complete" ]; then
        acquire_update_lock
        restore_hosts_for_complete_uninstall || \
            die "Could not restore $HOSTS_FILE; logs and backups were kept."
        release_update_lock
        remove_installed_cli
        purge_installation_data
        printf '\n%s data has been removed.\n' "$PROGRAM_LABEL"
        printf '/etc/hosts was restored and GitHub520 entries were removed.\n'
        if [ "$PACKAGED_MODE" -eq 1 ]; then
            printf 'Package files were left in place; remove them with:\n'
            if [ "$PLATFORM" = "arch" ]; then
                printf '  sudo pacman -Rns %s\n' "$PROGRAM_NAME"
            else
                printf '  sudo apt remove --purge %s\n' "$PROGRAM_NAME"
            fi
        fi
    else
        remove_installed_cli
        printf '\n%s systemd timer has been disabled.\n' "$PROGRAM_LABEL"
        printf 'Kept on purpose:\n'
        printf '  hosts file : %s\n' "$HOSTS_FILE"
        printf '  logs       : %s\n' "$LOG_DIR"
        printf '  backups    : %s\n' "$BACKUP_DIR"
        if [ "$PACKAGED_MODE" -eq 1 ]; then
            printf 'Package files were left in place; remove them with:\n'
            if [ "$PLATFORM" = "arch" ]; then
                printf '  sudo pacman -Rns %s\n' "$PROGRAM_NAME"
            else
                printf '  sudo apt remove --purge %s\n' "$PROGRAM_NAME"
            fi
        fi
        printf 'Use --uninstall-completely to restore hosts and purge all data.\n'
    fi
}

restore_hosts_command() {
    local target=$RESTORE_TARGET
    local tmp=""

    acquire_update_lock

    if [ -z "$target" ] || [ "$target" = "latest" ]; then
        target=$(latest_hosts_backup)
        if [ -z "$target" ]; then
            target=$ORIGINAL_HOSTS_BACKUP
        fi
    elif [ "$target" = "original" ]; then
        target=$ORIGINAL_HOSTS_BACKUP
    fi

    if [ -z "$target" ] || [ ! -f "$target" ]; then
        die "No matching hosts backup found: ${target:-none}"
    fi

    tmp=$(mktemp "${TMPDIR:-/tmp}/github520-restore.XXXXXX") || \
        die "Failed to create a temporary restore file."
    cp -L -p -- "$target" "$tmp" || {
        rm -f -- "$tmp"
        die "Failed to read $target."
    }

    backup_hosts_file
    if ! cat -- "$tmp" > "$HOSTS_FILE"; then
        rm -f -- "$tmp"
        die "Failed to restore $HOSTS_FILE."
    fi
    rm -f -- "$tmp"
    release_update_lock
    ok "Restored $HOSTS_FILE from $target"
}

show_status() {
    local pretty="unknown" timer_enabled="unknown" timer_active="unknown"
    local entries=0 backups=0 last_line="" installed="no"

    if [ -r /etc/os-release ]; then
        pretty=$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null |
            cut -d= -f2- | tr -d '"' || true)
        [ -n "$pretty" ] || pretty="unknown"
    fi

    if [ -x "$INSTALL_PATH" ]; then
        installed="yes"
    fi

    if [ -f "$HOSTS_FILE" ]; then
        entries=$(count_github520_entries "$HOSTS_FILE")
    fi

    if [ -f "$UPDATE_LOG" ]; then
        last_line=$(tail -n 1 "$UPDATE_LOG" 2>/dev/null || true)
    fi

    backups=$(ls -1 "$BACKUP_DIR"/hosts.[0-9]* 2>/dev/null | wc -l | tr -d ' ' || true)

    if command -v systemctl >/dev/null 2>&1; then
        timer_enabled=$(systemctl is-enabled "$TIMER_NAME" 2>/dev/null || true)
        timer_active=$(systemctl is-active "$TIMER_NAME" 2>/dev/null || true)
        [ -n "$timer_enabled" ] || timer_enabled="unknown"
        [ -n "$timer_active" ] || timer_active="unknown"
    fi

    printf '%s%s%s %s (%s)\n' "$C_INFO" "$PROGRAM_LABEL" "$C_RESET" "$VERSION" "$RELEASE_CHANNEL"
    printf '  System       : %s\n' "$pretty"
    printf '  CLI          : %s (%s)\n' "$INSTALL_PATH" "$installed"
    printf '  Hosts file   : %s\n' "$HOSTS_FILE"
    printf '  GitHub520    : %s entries\n' "$entries"
    printf '  Timer        : enabled=%s active=%s\n' "$timer_enabled" "$timer_active"
    printf '  Backups      : %s\n' "$backups"
    printf '  Update log   : %s\n' "$UPDATE_LOG"
    if [ -n "$last_line" ]; then
        printf '  Last update  : %s\n' "$last_line"
    fi
    printf '\nCommands: install | update | status | logs [-f] | restore | --uninstall | --uninstall-completely\n'
    printf 'Run '\''%s --help'\'' for full help.\n' "$SCRIPT_NAME"
}

show_logs() {
    [ -f "$UPDATE_LOG" ] || die "Update log not found: $UPDATE_LOG"

    if [ "$FOLLOW_LOG" -eq 1 ]; then
        tail -n 50 -f "$UPDATE_LOG"
    else
        tail -n 100 "$UPDATE_LOG"
    fi
}

# -----------------------------------------------------------------------------
# Update mode / installer summary
# -----------------------------------------------------------------------------
init_update_log() {
    local size=0

    install -d -m 0755 "$LOG_DIR" 2>/dev/null || ensure_dir "$LOG_DIR" 0755
    chmod 0755 "$LOG_DIR" 2>/dev/null || true

    if [ -f "$UPDATE_LOG" ]; then
        size=$(stat -c '%s' "$UPDATE_LOG" 2>/dev/null || printf '0')
        if [ "${size:-0}" -gt 1048576 ]; then
            mv -f "$UPDATE_LOG" "${UPDATE_LOG}.1" || true
        fi
    fi

    exec >> "$UPDATE_LOG" 2>&1
    printf '\n[%s] ===== GitHub520 hourly update start (%s) =====\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$VERSION"
}

run_install() {
    log "Starting installation workflow."
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${TMP_PREFIX}.XXXXXX") || \
        die "Failed to create a temporary directory."
    log "Temporary workspace: $TMP_DIR"

    ensure_original_hosts_backup

    log "Checking filesystem and snapshot options."
    detect_filesystem_and_snapshot
    log "Checking network configuration."
    detect_network_backends
    if ! detect_default_route; then
        log "Static network configuration will be skipped."
    fi

    log "Preparing GitHub520 hosts data."
    acquire_update_lock
    prepare_github520_download
    fetch_hosts_block
    build_new_hosts
    log "Applying hosts changes and DNS settings."
    install_new_hosts
    release_update_lock
    flush_dns_caches

    log "Configuring optional network changes and the update timer."
    ask_network_change
    install_timer

    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR" 2>/dev/null || true
        TMP_DIR=""
    fi

    log "Installation workflow finished."
    print_final_summary
}

run_manual_update() {
    MANUAL_UPDATE=1
    ensure_dir "$LOG_DIR" 0755
    append_update_log "[ INFO ] Manual update started."

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${TMP_PREFIX}-update.XXXXXX") || \
        die "Failed to create a temporary directory."

    log "Manual GitHub520 update started."
    apply_hosts_update
    flush_dns_caches

    append_update_log "[  OK  ] Manual update succeeded (source=${SELECTED_HOSTS_URL}, entries=${HOSTS_ENTRY_COUNT})."
    ok "Manual update completed. Hosts entries: $HOSTS_ENTRY_COUNT"
}

run_update_mode() {
    UPDATE_MODE=1
    init_update_log

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/${TMP_PREFIX}-update.XXXXXX") || \
        die "Failed to create a temporary directory."

    log "${PLATFORM_DESC} update started."
    apply_hosts_update
    flush_dns_caches

    printf '[%s] [  OK  ] GitHub520 hourly update succeeded.\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
}

print_final_summary() {
    printf '\n'
    printf '%s' "$C_PINK"
    cat <<'EOF'
      /\_/\
     ( o.o )   < 喵～ 都弄好啦！
      > ^ <
EOF
    printf '%s' "$C_RESET"
    printf '\n'
    printf '%s========================================================%s\n' "$C_OK" "$C_RESET"
    printf '%s %s 安装完成！ / Installation complete!%s\n' "$C_OK" "$PROGRAM_LABEL" "$C_RESET"
    printf '%s========================================================%s\n' "$C_OK" "$C_RESET"
    printf '  猫娘已经把 GitHub520 乖乖安置在 %s 里啦，喵～\n' "$PLATFORM_DESC"
    printf '  Your catgirl has tucked GitHub520 safely into %s.\n' "$PLATFORM_DESC"
    printf '\n'
    printf '  Version        : %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf '  CLI            : %s\n' "$INSTALL_PATH"
    printf '  Hosts file     : %s\n' "$HOSTS_FILE"
    printf '  Hosts source   : %s\n' "$SELECTED_HOSTS_URL"
    printf '  Hosts backup   : %s\n' "${HOSTS_BACKUP:-none}"
    printf '  Original hosts : %s\n' "$ORIGINAL_HOSTS_BACKUP"
    printf '  Snapshot       : %s\n' "$SNAPSHOT_DONE"
    printf '  Timer          : %s (hourly)\n' "$TIMER_NAME"
    printf '  Update log     : %s\n' "$UPDATE_LOG"
    if [ "$NETWORK_CONFIGURED" -eq 1 ]; then
        printf '  Network backend: %s\n' "$NET_BACKEND_DESC"
        printf '  Static address : %s\n' "$STATIC_CIDR"
        printf '  Gateway        : %s\n' "$GATEWAY"
        if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
            printf '  DNS servers    : %s\n' "$(join_words "${DNS_SERVERS[@]}")"
        fi
        printf '  Network backup : %s\n' "$NET_BACKUP_DIR"
    else
        printf '  Network changes: none\n'
    fi
    printf '\n'
    printf '  常用命令 / Useful commands:\n'
    printf '    sudo %s status\n' "$PROGRAM_NAME"
    printf '    sudo %s update\n' "$PROGRAM_NAME"
    printf '    sudo %s logs -f\n' "$PROGRAM_NAME"
    printf '    sudo %s restore\n' "$PROGRAM_NAME"
    printf '    sudo %s --uninstall\n' "$PROGRAM_NAME"
    printf '    sudo %s --uninstall-completely\n' "$PROGRAM_NAME"
    printf '    systemctl status %s\n' "$TIMER_NAME"
    printf '    journalctl -u %s\n' "$SERVICE_NAME"
    printf '\n'
    printf '  项目仓库 / Repositories:\n'
    printf '    GitHub : %s\n' "${REPO_URLS[0]}"
    printf '    Gitee  : %s\n' "${REPO_URLS[1]}"
    printf '    GitCode: %s\n' "${REPO_URLS[2]}"
    printf '    Codeberg: %s\n' "${REPO_URLS[3]}"
    printf '\n'
    printf '  作者 / Author: 白丝小猫娘 (WS-CatGirl)\n'
    printf '  临时文件已清理，备份和日志已保留。\n'
    printf '  Temporary files cleaned; backups and logs retained.\n'
    printf '  感谢安装和使用，喵～ Ciallo～(∠・ω< )⌒★\n'
    printf '  Thank you for installing %s!\n' "$PROGRAM_LABEL"
    printf '\n'
    printf '  提示：这是 v1.0-milestone.2 预发布版本，请先备份重要配置；遇到问题欢迎反馈。\n'
    printf '  Note: this is the v1.0-milestone.2 pre-release. Keep backups and report any issues.\n'
    printf '\n'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
is_installed_cli() {
    [ -n "${SELF:-}" ] && [ "$SELF" = "$INSTALL_PATH" ] && return 0
    [ "$(command -v "$0" 2>/dev/null || true)" = "$INSTALL_PATH" ] && return 0
    return 1
}

main() {
    local welcome_shown=0

    show_prerelease_notice

    SELF=$(readlink -f -- "$0" 2>/dev/null || true)
    [ -n "$SELF" ] || SELF=${0:-}

    parse_args "$@"

    if [ "$COMMAND" = "install" ] &&
       [ "${GITHUB520_FROM_INSTALLER:-0}" != "1" ] &&
       ! is_installed_cli; then
        err "Direct installation is not supported."
        err "Please run: bash ./install.sh"
        exit 2
    fi

    case "$COMMAND" in
        status)
            show_status
            exit 0
            ;;
        logs)
            show_logs
            exit 0
            ;;
        install)
            if [ "$(id -u)" -eq 0 ]; then
                show_welcome
                welcome_shown=1
            fi

            require_root "$@"

            if [ "$welcome_shown" -eq 0 ]; then
                show_welcome
            fi

            detect_platform
            run_install
            ;;
        update)
            require_root "$@"
            detect_platform
            if [ "$SYSTEMD_MODE" -eq 1 ]; then
                run_update_mode
            else
                run_manual_update
            fi
            ;;
        uninstall)
            require_root "$@"
            do_uninstall "retain"
            ;;
        uninstall-complete)
            require_root "$@"
            do_uninstall "complete"
            ;;
        restore)
            require_root "$@"
            restore_hosts_command
            ;;
        *)
            err "Unknown command: $COMMAND"
            usage
            exit 2
            ;;
    esac
}
