#!/usr/bin/env bash
# =============================================================================
# github520-deploy.sh
#
# GitHub520 hosts manager for Linux.
#
# Version : v0.1-beta
# Author  : 白丝小猫娘 (WS-CatGirl)
#
# Repositories:
#   https://github.com/WS-CatGirl/github520-deploy
#   https://gitee.com/wscatgirl/github520-deploy
#   https://gitcode.com/WS_CatGirl/github520-deploy
#
# Installed CLI:
#   /usr/local/bin/github520-deploy
#
# Commands:
#   install / reinstall / update / refresh / status / logs / restore
#   --uninstall / --uninstall-completely
#
# The timer runs:
#   /usr/local/bin/github520-deploy --update --systemd
# and writes to /var/log/github520-deploy/update.log.
#
# Requirements: Linux, systemd, bash 4+, curl, iproute2, coreutils.
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022
export LC_ALL=C

VERSION="v0.1"
RELEASE_CHANNEL="beta"
SCRIPT_NAME=${0##*/}
SELF=""
HOSTS_FILE="/etc/hosts"
RESOLV_FILE="/etc/resolv.conf"
BACKUP_DIR="/var/backups/github520-deploy"
LOG_DIR="/var/log/github520-deploy"
UPDATE_LOG="$LOG_DIR/update.log"
INSTALL_PATH="/usr/local/bin/github520-deploy"
LEGACY_INSTALL_PATH="/usr/local/bin/github520-deploy.sh"
ORIGINAL_HOSTS_BACKUP="$BACKUP_DIR/hosts.original"
SERVICE_NAME="github520-deploy-update.service"
TIMER_NAME="github520-deploy-update.timer"
SNAPSHOT_TIMEOUT=30
MAX_HOSTS_BACKUPS=24

COMMAND=""
SYSTEMD_MODE=0
MANUAL_UPDATE=0
FOLLOW_LOG=0
FORCE=0
RESTORE_TARGET=""

GITHUB520_REPO_URL="https://github.com/521xueweihan/GitHub520"
REPO_URLS=(
    "https://github.com/WS-CatGirl/github520-deploy"
    "https://gitee.com/wscatgirl/github520-deploy"
    "https://gitcode.com/WS_CatGirl/github520-deploy"
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

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_INFO=$'\033[1;36m'
    C_OK=$'\033[1;32m'
    C_WARN=$'\033[1;33m'
    C_ERR=$'\033[1;31m'
    C_PINK=$'\033[1;35m'
else
    C_RESET=""
    C_INFO=""
    C_OK=""
    C_WARN=""
    C_ERR=""
    C_PINK=""
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
_log_line() {
    local level=$1
    shift

    if [ "$UPDATE_MODE" -eq 1 ]; then
        printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
    else
        printf '[%s] %s\n' "$level" "$*"
    fi
}

log() {
    _log_line INFO "$*"
}

ok() {
    _log_line OK "$*"
}

warn() {
    _log_line WARN "$*" >&2
}

err() {
    _log_line FAIL "$*" >&2
}

die() {
    err "$*"
    if [ "$UPDATE_MODE" -eq 1 ] || [ "$MANUAL_UPDATE" -eq 1 ]; then
        append_update_log "[FAIL] ${*}"
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
    printf '  %s欢迎使用 / Welcome to GitHub520-Deploy%s\n' "$C_INFO" "$C_RESET"
    printf '  猫娘已经把 Linux 的 hosts 工具准备好啦，喵～\n'
    printf '  This catgirl is ready to make GitHub purr on Linux.\n'
    printf '  Version: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf '\n'
}

usage() {
    cat <<'EOF'
github520-deploy.sh - GitHub520 manager for Linux (beta)

Usage:
  sudo github520-deploy [command]
  sudo ./github520-deploy.sh [command]
  github520-deploy                 # show status and a short help hint

Commands:
  install, --install             Run the interactive installer and install
                                 /usr/local/bin/github520-deploy.
  reinstall                      Re-run the installer using the installed
                                 script (same as install).
  update, refresh, --update      Immediately download and refresh /etc/hosts.
  status                         Show version, hosts count, timer state,
                                 last log line and backup count.
  logs [-f]                      Show the update log; -f follows it.
  restore [latest|original|FILE] Restore /etc/hosts from a backup.
  --uninstall                    Remove the CLI and systemd units, but keep
                                 /etc/hosts, logs and backups.
  --uninstall-completely         Restore the original /etc/hosts, then remove
                                 the CLI, units, logs, backups and temp files.
  version, --version             Show version.
  help, --help                   Show this help.

Internal:
  --update --systemd             Used by github520-deploy-update.service. Redirects
                                 all output to /var/log/github520-deploy/update.log.

Options:
  -f, --follow                   Follow the log (with logs).
      --force                    Skip the confirmation for --uninstall-completely.

Install flow:
  1. Welcome
  2. Root/sudo check
  3. Linux / container / VM check
  4. Optional Btrfs/snapper snapshot
  5. Network backend detection
  6. GitHub520 download and /etc/hosts update
  7. Optional static IPv4/DNS configuration
  8. Install and enable github520-deploy-update.timer (hourly)
  9. Final summary

Timer:
  systemctl status github520-deploy-update.timer
  systemctl list-timers github520-deploy-update.timer
  journalctl -u github520-deploy-update.service
  tail -f /var/log/github520-deploy/update.log
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

    if [ "${GITHUB520_DEPLOY_ELEVATED:-0}" = "1" ]; then
        deny_access "root privileges are still unavailable after sudo."
    fi

    if sudo -n true 2>/dev/null; then
        log "Re-executing with cached sudo credentials."
        export GITHUB520_DEPLOY_ELEVATED=1
        exec sudo -n -- bash "$SELF" "$@"
    fi

    log "Root privileges are required; sudo may ask for your password."
    if ! sudo -v; then
        deny_access "sudo authentication failed, or this account cannot use sudo."
    fi

    export GITHUB520_DEPLOY_ELEVATED=1
    exec sudo -- bash "$SELF" "$@"
}

# -----------------------------------------------------------------------------
# Linux / container / virtual machine check
# -----------------------------------------------------------------------------
detect_system() {
    local virt="" dmi="" pretty="Linux"

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
        # shellcheck disable=SC1091
        . /etc/os-release
        pretty=${PRETTY_NAME:-Linux}

        if [ "${ID:-}" = "arch" ]; then
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
            --description "github520-deploy $(date '+%Y-%m-%d %H:%M:%S')" \
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
        --description "github520-deploy $(date '+%Y-%m-%d %H:%M:%S')" \
        --cleanup-algorithm number; then
        die "Failed to create a snapshot for the root subvolume."
    fi

    SNAPSHOT_DONE="root subvolume (@) via snapper config '$root_cfg'"
}

read_snapshot_choice() {
    local deadline choice="" rc remaining

    require_tty

    printf '\nSnapshot options (Btrfs with snapper detected):\n'
    printf '  1) Snapshot all snapper configs\n'
    printf '  2) Snapshot only the @ subvolume (root config)\n'
    printf '  3) Do not snapshot (abort deployment)\n'

    deadline=$((SECONDS + SNAPSHOT_TIMEOUT))
    while true; do
        remaining=$((deadline - SECONDS))
        if [ "$remaining" -le 0 ]; then
            printf '\r%*s\r' 60 ''
            die "Snapshot selection timed out after ${SNAPSHOT_TIMEOUT} seconds."
        fi
        printf '\r[%2ds] Select 1, 2 or 3: ' "$remaining"

        rc=0
        if IFS= read -r -t 1 choice; then
            printf '\r%*s\r' 60 ''
            choice=${choice//[[:space:]]/}
            case "$choice" in
                1|2|3)
                    printf 'Selection: %s\n' "$choice"
                    SNAPSHOT_CHOICE=$choice
                    return 0
                    ;;
                '')
                    ;;
                *)
                    warn "Invalid selection '$choice'; enter 1, 2 or 3."
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
        log "Root filesystem is '$root_fs', not Btrfs; snapshot skipped."
        SNAPSHOT_DONE="not applicable ($root_fs)"
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
        3) die "No snapshot was requested; aborting deployment." ;;
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
        log "Network backends detected: ${managers[*]}"
    else
        warn "No known network management backend was detected."
    fi
    log "ifupdown is preferred for static IP/DNS changes; NetworkManager is the next fallback."
}

detect_default_route() {
    local route i
    local -a fields=()

    if ! route=$(ip -4 route show default 2>/dev/null | head -n 1); then
        die "Failed to read the IPv4 routing table."
    fi
    if [ -z "$route" ]; then
        die "No IPv4 default route is present."
    fi

    IFS=' ' read -r -a fields <<< "$route"
    for ((i = 0; i < ${#fields[@]}; i++)); do
        case "${fields[i]}" in
            via) GATEWAY=${fields[i + 1]:-} ;;
            dev) IFACE=${fields[i + 1]:-} ;;
        esac
    done

    if [ -z "$IFACE" ]; then
        die "Could not determine the default network interface."
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
    local ip=$1
    [[ $ip == *:* ]] || return 1
    [[ $ip =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    return 0
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
    local dns1="" dns2="" def1="" def2=""
    local -a cur_dns=()

    mapfile -t cur_dns < <(current_dns_servers)
    def1=${cur_dns[0]:-}
    def2=${cur_dns[1]:-}

    if [ -n "$def1" ]; then
        printf 'Current DNS servers: %s\n' "${cur_dns[*]}"
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
    if [ "$NM_OLD_METHOD" = "manual" ]; then
        nmcli connection modify "$uuid" ipv4.method manual || return 1
        nmcli connection modify "$uuid" \
            ipv4.addresses "$NM_OLD_ADDR" \
            ipv4.gateway "$NM_OLD_GATEWAY" \
            ipv4.dns "$NM_OLD_DNS" || return 1
    else
        nmcli connection modify "$uuid" ipv4.method "$NM_OLD_METHOD" || return 1
        nmcli connection modify "$uuid" ipv4.addresses "" ipv4.gateway "" || return 1
        nmcli connection modify "$uuid" ipv4.dns "$NM_OLD_DNS" || return 1
    fi
    nmcli connection modify "$uuid" ipv4.ignore-auto-dns "${NM_OLD_IGNORE_DNS:-no}" || return 1
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
            if ($0 ~ /^[[:space:]]*iface[[:space:]]+/ && $2 == iface) {
                skip = 1
                next
            }
            if ($0 ~ /^[[:space:]]*(auto|allow-hotplug|allow-auto)[[:space:]]+/ && $2 == iface) {
                next
            }
            print
        }
    ' "$src" > "$base" || die "Failed to parse $src."

    {
        cat "$base"
        printf '\n'
        printf 'auto %s\n' "$IFACE"
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
    cp -L -p -- "$RESOLV_FILE" "$backup" 2>/dev/null || {
        warn "Could not back up $RESOLV_FILE."
        backup=""
    }
    RESOLV_BACKUP=$backup

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
        resolvectl dns "$IFACE" "${DNS_SERVERS[@]}" || warn "resolvectl could not set DNS."
        resolvectl flush-caches >/dev/null 2>&1 || true
        return 0
    fi

    if command -v resolvconf >/dev/null 2>&1; then
        {
            for d in "${DNS_SERVERS[@]}"; do
                printf 'nameserver %s\n' "$d"
            done
        } | resolvconf -a "github520-$IFACE" || warn "resolvconf could not apply DNS."
        return 0
    fi

    write_resolv_conf
}

rollback_network_config() {
    local rc=0

    if [ -n "$IFACE" ] && command -v resolvectl >/dev/null 2>&1; then
        resolvectl revert "$IFACE" >/dev/null 2>&1 || true
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

configure_static_network() {
    local ip_input="" pfx=24

    require_tty
    select_config_backend
    create_network_backup_dir

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
        printf '  DNS       : %s\n' "${DNS_SERVERS[*]}"
    fi
    if ! confirm_action "Apply this static network configuration?"; then
        log "Network configuration cancelled."
        return 0
    fi

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
check_github520() {
    local url code reachable=0

    command -v curl >/dev/null 2>&1 || die "curl is required."

    log "Checking GitHub520 availability..."
    log "Upstream: $GITHUB520_REPO_URL"

    for url in "${HOSTS_SOURCES[@]}"; do
        log "Probing source: $url"
        code=""
        if code=$(curl -fsSL --connect-timeout 6 --max-time 15 \
            --retry 1 --retry-delay 1 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null); then
            if [ "$code" = "200" ]; then
                ok "Source reachable: $url"
                reachable=1
                break
            fi
            warn "HTTP $code from $url"
        else
            warn "Request failed: $url"
        fi
    done

    if [ "$reachable" -ne 1 ]; then
        die "GitHub520 is unavailable from all configured sources."
    fi
}

validate_hosts_block() {
    local file=$1 start end entries

    [ -s "$file" ] || { warn "Downloaded content is empty."; return 1; }

    start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$file" || true)
    end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$file" || true)

    if [ "$start" -ne 1 ] || [ "$end" -ne 1 ]; then
        warn "Invalid GitHub520 block markers (start=$start end=$end)."
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

        if ! code=$(curl -fsSL --connect-timeout 8 --max-time 25 \
            --retry 1 --retry-delay 1 -o "$try" -w '%{http_code}' "$url"); then
            warn "Download failed; next source."
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
    ' "$file"
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

    existing_start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" || true)
    existing_end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" || true)
    if [ "$existing_start" -ne "$existing_end" ]; then
        die "$HOSTS_FILE contains an unbalanced GitHub520 block."
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
        systemctl restart dnsmasq >/dev/null 2>&1 || true
    fi
}

apply_hosts_update() {
    check_github520
    fetch_hosts_block
    build_new_hosts
    install_new_hosts
}

# -----------------------------------------------------------------------------
# systemd timer/service
# -----------------------------------------------------------------------------
install_script_copy() {
    local src

    src=$(readlink -f -- "$0" 2>/dev/null || true)
    [ -n "$src" ] || src="$PWD/$0"

    if [ "$src" = "$INSTALL_PATH" ]; then
        log "CLI is already installed at $INSTALL_PATH."
    else
        ensure_dir "$(dirname -- "$INSTALL_PATH")" 0755
        install -m 0755 -- "$src" "$INSTALL_PATH" || die "Failed to install $INSTALL_PATH."
        ok "Installed CLI: $INSTALL_PATH"
    fi

    ln -sfn "$INSTALL_PATH" "$LEGACY_INSTALL_PATH" || \
        warn "Could not create compatibility symlink: $LEGACY_INSTALL_PATH"
}

install_timer() {
    local service_file="/etc/systemd/system/$SERVICE_NAME"
    local timer_file="/etc/systemd/system/$TIMER_NAME"

    install_script_copy

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
OnBootSec=5min
OnUnitActiveSec=1h
AccuracySec=1min
RandomizedDelaySec=30s
Persistent=true
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF

    chmod 0644 "$service_file" "$timer_file"
    systemctl daemon-reload || die "systemctl daemon-reload failed."
    systemctl enable "$TIMER_NAME" >/dev/null || die "Failed to enable $TIMER_NAME."
    systemctl restart "$TIMER_NAME" || die "Failed to start $TIMER_NAME."

    systemctl is-enabled --quiet "$TIMER_NAME" || die "$TIMER_NAME is not enabled."
    systemctl is-active --quiet "$TIMER_NAME" || die "$TIMER_NAME is not active."

    ensure_dir "$LOG_DIR" 0755
    printf '[%s] [INFO] Timer installed and enabled (hourly updates).\n' \
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
    local tmp

    [ -f "$HOSTS_FILE" ] || return 1
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
    local service_file="/etc/systemd/system/$SERVICE_NAME"
    local timer_file="/etc/systemd/system/$TIMER_NAME"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "$TIMER_NAME" >/dev/null 2>&1 || true
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
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
    rm -f -- "$INSTALL_PATH" "$LEGACY_INSTALL_PATH"
    log "Removed installed CLI: $INSTALL_PATH"
}

purge_installation_data() {
    rm -rf -- "$LOG_DIR" "$BACKUP_DIR"
    rm -f -- /etc/hosts.github520-backup.* 2>/dev/null || true
    rm -rf -- /tmp/github520-deploy.* /tmp/github520-deploy-update.* \
        /tmp/github520-strip.* /tmp/github520-restore.* 2>/dev/null || true
    log "Removed logs, backups and temporary files."
}

do_uninstall() {
    local mode=$1

    if [ "$mode" = "complete" ]; then
        if [ "$FORCE" -ne 1 ]; then
            warn "This will restore the original /etc/hosts and remove all GitHub520 data."
            if ! confirm_action "Completely uninstall GitHub520-Deploy?"; then
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
        restore_hosts_for_complete_uninstall || \
            die "Could not restore $HOSTS_FILE; logs and backups were kept."
        remove_installed_cli
        purge_installation_data
        printf '\nGitHub520-Deploy has been completely removed.\n'
        printf '/etc/hosts was restored and GitHub520 entries were removed.\n'
    else
        remove_installed_cli
        printf '\nGitHub520-Deploy CLI and systemd units have been removed.\n'
        printf 'Kept on purpose:\n'
        printf '  hosts file : %s\n' "$HOSTS_FILE"
        printf '  logs       : %s\n' "$LOG_DIR"
        printf '  backups    : %s\n' "$BACKUP_DIR"
        printf 'Use --uninstall-completely to restore hosts and purge all data.\n'
    fi
}

restore_hosts_command() {
    local target=$RESTORE_TARGET
    local tmp=""

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

    printf '%sGitHub520-Deploy%s %s (%s)\n' "$C_INFO" "$C_RESET" "$VERSION" "$RELEASE_CHANNEL"
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
    printf '\n[%s] ===== GitHub520 hourly update start (v%s-%s) =====\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$VERSION" "$RELEASE_CHANNEL"
}

run_install() {
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-deploy.XXXXXX") || \
        die "Failed to create a temporary directory."
    log "Temporary workspace: $TMP_DIR"

    ensure_original_hosts_backup

    detect_filesystem_and_snapshot
    detect_network_backends
    detect_default_route

    check_github520
    fetch_hosts_block
    build_new_hosts
    install_new_hosts
    flush_dns_caches

    ask_network_change
    install_timer

    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR" 2>/dev/null || true
        TMP_DIR=""
    fi

    print_final_summary
}

run_manual_update() {
    MANUAL_UPDATE=1
    ensure_dir "$LOG_DIR" 0755
    append_update_log "[INFO] Manual update started."

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-deploy-update.XXXXXX") || \
        die "Failed to create a temporary directory."

    log "Manual GitHub520 update started."
    apply_hosts_update
    flush_dns_caches

    append_update_log "[ OK ] Manual update succeeded (source=${SELECTED_HOSTS_URL}, entries=${HOSTS_ENTRY_COUNT})."
    ok "Manual update completed. Hosts entries: $HOSTS_ENTRY_COUNT"
}

run_update_mode() {
    UPDATE_MODE=1
    init_update_log

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-deploy-update.XXXXXX") || \
        die "Failed to create a temporary directory."

    log "Linux update started."
    apply_hosts_update
    flush_dns_caches

    printf '[%s] [ OK ] GitHub520 hourly update succeeded.\n' "$(date '+%Y-%m-%d %H:%M:%S')"
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
    printf '%s GitHub520-Deploy 安装完成！ / Installation complete!%s\n' "$C_OK" "$C_RESET"
    printf '%s========================================================%s\n' "$C_OK" "$C_RESET"
    printf '  猫娘已经把 GitHub520 乖乖安置在 Linux 里啦，喵～\n'
    printf '  Your catgirl has tucked GitHub520 safely into Linux.\n'
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
            printf '  DNS servers    : %s\n' "${DNS_SERVERS[*]}"
        fi
        printf '  Network backup : %s\n' "$NET_BACKUP_DIR"
    else
        printf '  Network changes: none\n'
    fi
    printf '\n'
    printf '  常用命令 / Useful commands:\n'
    printf '    sudo github520-deploy status\n'
    printf '    sudo github520-deploy update\n'
    printf '    sudo github520-deploy logs -f\n'
    printf '    sudo github520-deploy restore\n'
    printf '    sudo github520-deploy --uninstall\n'
    printf '    sudo github520-deploy --uninstall-completely\n'
    printf '    systemctl status %s\n' "$TIMER_NAME"
    printf '    journalctl -u %s\n' "$SERVICE_NAME"
    printf '\n'
    printf '  项目仓库 / Repositories:\n'
    printf '    GitHub : %s\n' "${REPO_URLS[0]}"
    printf '    Gitee  : %s\n' "${REPO_URLS[1]}"
    printf '    GitCode: %s\n' "${REPO_URLS[2]}"
    printf '\n'
    printf '  作者 / Author: 白丝小猫娘 (WS-CatGirl)\n'
    printf '  临时文件已清理，备份和日志已保留。\n'
    printf '  Temporary files cleaned; backups and logs retained.\n'
    printf '  感谢安装和使用，喵～ Ciallo～(∠・ω< )⌒★\n'
    printf '  Thank you for installing GitHub520-Deploy!\n'
    printf '\n'
    printf '  提示：这是 beta 版本，请先备份重要配置；遇到问题欢迎反馈。\n'
    printf '  Note: this is a beta release. Keep backups and report any issues.\n'
    printf '\n'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local welcome_shown=0

    parse_args "$@"

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

            detect_system
            run_install
            ;;
        update)
            require_root "$@"
            detect_system
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
