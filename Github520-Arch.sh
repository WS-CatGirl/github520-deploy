#!/usr/bin/env bash
# =============================================================================
# Github520-Arch.sh
#
# GitHub520 hosts installer for Arch Linux.
#
# Version : v0.1-beta
# Author  : 白丝小猫娘 (WS-CatGirl)
#
# Repositories:
#   https://github.com/WS-CatGirl/github520-deploy
#   https://gitee.com/wscatgirl/github520-deploy
#   https://gitcode.com/WS_CatGirl/github520-deploy
#
# What this script does:
#   0. Welcome screen.
#   1. Root/sudo privilege handling.
#   2. Arch Linux check (os-release ID=arch).
#   3. Optional Btrfs/snapper snapshot.
#   4. Network backend detection (NetworkManager first).
#   5. GitHub520 source check and hosts download.
#   6. Backup and update /etc/hosts.
#   7. Optional static IPv4/DNS configuration.
#   8. Install a systemd service + hourly timer for automatic updates.
#   9. Cleanup and final summary.
#
# The timer runs:
#   /usr/local/bin/github520-arch.sh --update
# and writes to /var/log/github520/update.log.
#
# Requirements: Arch Linux, systemd, bash 4+, curl, iproute2, coreutils.
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
BACKUP_DIR="/var/backups/github520"
LOG_DIR="/var/log/github520"
UPDATE_LOG="$LOG_DIR/update.log"
INSTALL_PATH="/usr/local/bin/github520-arch.sh"
SERVICE_NAME="github520-update.service"
TIMER_NAME="github520-update.timer"
SNAPSHOT_TIMEOUT=30
MAX_HOSTS_BACKUPS=24

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
    if [ "$UPDATE_MODE" -eq 1 ]; then
        printf '[%s] [FAIL] GitHub520 hourly update failed.\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    fi
    exit 1
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
    printf '  %s欢迎使用 / Welcome to GitHub520-Arch%s\n' "$C_INFO" "$C_RESET"
    printf '  猫娘已经把 Arch Linux 的 hosts 工具准备好啦，喵～\n'
    printf '  This catgirl is ready to make GitHub purr on Arch Linux.\n'
    printf '  Version: %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf '\n'
}

usage() {
    cat <<'EOF'
GitHub520-Arch.sh - GitHub520 hosts installer for Arch Linux (beta)

Usage:
  sudo ./Github520-Arch.sh
  sudo ./Github520-Arch.sh --update
  ./Github520-Arch.sh --help
  ./Github520-Arch.sh --version

Options:
  -h, --help       Show this help and exit.
  -V, --version    Show the script version and exit.
      --update     Internal mode used by the systemd timer. Updates
                   /etc/hosts non-interactively, writes the result to
                   /var/log/github520/update.log and exits.

Normal install flow:
  1. Welcome
  2. Root/sudo check
  3. Arch Linux check
  4. Optional Btrfs/snapper snapshot
  5. Network backend detection
  6. GitHub520 download and /etc/hosts update
  7. Optional static IPv4/DNS configuration
  8. Install and enable github520-update.timer (hourly)
  9. Final summary

Timer:
  systemctl status github520-update.timer
  systemctl list-timers github520-update.timer
  journalctl -u github520-update.service
  tail -f /var/log/github520/update.log
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -V|--version)
                printf '%s %s (%s)\n' "$SCRIPT_NAME" "$VERSION" "$RELEASE_CHANNEL"
                exit 0
                ;;
            --update)
                UPDATE_MODE=1
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
                err "Unknown option: $1"
                err "Run '$SCRIPT_NAME --help' for usage."
                exit 2
                ;;
        esac
        shift
    done
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

    if [ "${GITHUB520_ARCH_ELEVATED:-0}" = "1" ]; then
        deny_access "root privileges are still unavailable after sudo."
    fi

    if sudo -n true 2>/dev/null; then
        log "Re-executing with cached sudo credentials."
        export GITHUB520_ARCH_ELEVATED=1
        exec sudo -n -- bash "$SELF" "$@"
    fi

    log "Root privileges are required; sudo may ask for your password."
    if ! sudo -v; then
        deny_access "sudo authentication failed, or this account cannot use sudo."
    fi

    export GITHUB520_ARCH_ELEVATED=1
    exec sudo -- bash "$SELF" "$@"
}

# -----------------------------------------------------------------------------
# Arch Linux check
# -----------------------------------------------------------------------------
detect_arch() {
    local os_id="" pretty="Arch Linux"

    if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
        die "This script only supports Arch Linux."
    fi

    if [ ! -r /etc/os-release ]; then
        die "/etc/os-release is missing; cannot verify Arch Linux."
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    os_id=${ID:-}
    pretty=${PRETTY_NAME:-Arch Linux}

    if [ "$os_id" != "arch" ]; then
        err "Unsupported distribution: $pretty (ID=${os_id:-unknown})."
        err "GitHub520-Arch.sh only supports Arch Linux (ID=arch)."
        err "Arch-based distributions such as Manjaro are not supported."
        exit 1
    fi

    if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
        die "systemd is required to install the hourly update timer."
    fi

    ok "Arch Linux detected: $pretty"
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
            --description "github520-arch $(date '+%Y-%m-%d %H:%M:%S')" \
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
        --description "github520-arch $(date '+%Y-%m-%d %H:%M:%S')" \
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
    if [ -f /etc/network/interfaces ]; then
        managers+=("ifupdown")
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
    log "NetworkManager is preferred for static IP/DNS changes on Arch."
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

    if command -v nmcli >/dev/null 2>&1 &&
       systemctl is-active --quiet NetworkManager 2>/dev/null; then
        uuid=$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null |
            awk -F: -v dev="$IFACE" '$2 == dev {print $1; exit}' || true)
        if [ -n "$uuid" ]; then
            BACKEND="networkmanager"
            BACKEND_ID=$uuid
            NET_BACKEND_DESC="NetworkManager"
            log "Selected backend: NetworkManager (preferred)."
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

    if src=$(find_ifupdown_file); then
        BACKEND="ifupdown"
        BACKEND_ID=$IFACE
        BACKEND_FILE=$src
        NET_BACKEND_DESC="ifupdown ($src)"
        log "Selected backend: ifupdown."
        return 0
    fi

    die "No supported backend for static configuration (NetworkManager, systemd-networkd, ifupdown)."
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

    mapfile -t files < <(ls -1t "$BACKUP_DIR"/hosts.* 2>/dev/null || true)
    if [ "${#files[@]}" -gt "$MAX_HOSTS_BACKUPS" ]; then
        rm -f -- "${files[@]:MAX_HOSTS_BACKUPS}"
    fi
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
        log "Script is already installed at $INSTALL_PATH."
        return 0
    fi

    ensure_dir "$(dirname -- "$INSTALL_PATH")" 0755
    install -m 0755 -- "$src" "$INSTALL_PATH" || die "Failed to install $INSTALL_PATH."
    ok "Installed script copy: $INSTALL_PATH"
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
ExecStart=$INSTALL_PATH --update
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

run_update_mode() {
    init_update_log

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-arch-update.XXXXXX") || \
        die "Failed to create a temporary directory."

    log "Arch Linux update started."
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
    printf '%s GitHub520-Arch 安装完成！ / Installation complete!%s\n' "$C_OK" "$C_RESET"
    printf '%s========================================================%s\n' "$C_OK" "$C_RESET"
    printf '  猫娘已经把 GitHub520 乖乖安置在 Arch Linux 里啦，喵～\n'
    printf '  Your catgirl has tucked GitHub520 safely into Arch Linux.\n'
    printf '\n'
    printf '  Version        : %s (%s)\n' "$VERSION" "$RELEASE_CHANNEL"
    printf '  Hosts file     : %s\n' "$HOSTS_FILE"
    printf '  Hosts source   : %s\n' "$SELECTED_HOSTS_URL"
    printf '  Hosts backup   : %s\n' "${HOSTS_BACKUP:-none}"
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
    printf '    systemctl status %s\n' "$TIMER_NAME"
    printf '    systemctl list-timers %s\n' "$TIMER_NAME"
    printf '    journalctl -u %s\n' "$SERVICE_NAME"
    printf '    tail -f %s\n' "$UPDATE_LOG"
    printf '    sudo systemctl start %s\n' "$SERVICE_NAME"
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
    printf '  Thank you for installing GitHub520-Arch!\n'
    printf '\n'
    printf '  提示：这是 beta 版本，请先备份重要配置；遇到问题欢迎反馈。\n'
    printf '  Note: this is a beta release. Keep backups and report any issues.\n'
    printf '\n'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    if [ "$UPDATE_MODE" -eq 1 ]; then
        require_root "$@"
        detect_arch
        run_update_mode
    fi

    show_welcome
    require_root "$@"
    detect_arch

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-arch.XXXXXX") || \
        die "Failed to create a temporary directory."
    log "Temporary workspace: $TMP_DIR"

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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
