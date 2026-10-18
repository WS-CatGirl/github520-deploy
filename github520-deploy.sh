#!/usr/bin/env bash
# =============================================================================
# github520-deploy.sh
#
# Deploy GitHub520 hosts entries on a native Linux machine.
#
# Upstream project:
#   GitHub520 by 521xueweihan
#   https://github.com/521xueweihan/GitHub520
#
# Official hosts source:
#   https://raw.hellogithub.com/hosts
#
# Additional mirrors are tried automatically when a source fails:
#   jsDelivr (several CDN endpoints) and raw.githubusercontent.com.
#
# What this script does:
#   0. Ensures it runs with root privileges (re-executes itself through sudo).
#   1. Refuses non-Linux systems, WSL, containers and virtual machines.
#   2. On Btrfs with snapper, asks for a snapshot (30 second countdown),
#      creates it, and aborts on timeout, error or "no snapshot".
#   3. Detects the network management backend, verifies that GitHub520 is
#      reachable, downloads its hosts block from the first working source,
#      backs up /etc/hosts and installs it.
#   4. Optionally configures a static IPv4 address and DNS servers.
#
# Requirements: bash 4+, coreutils, util-linux (findmnt), iproute2, curl.
# =============================================================================

# Re-execute with bash when the file is started through sh/dash.
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    printf '[FAIL] bash 4 or newer is required (found %s).\n' "${BASH_VERSION:-unknown}" >&2
    exit 1
fi

set -Eeuo pipefail
IFS=$'\n\t'
umask 022
export LC_ALL=C

SCRIPT_NAME=${0##*/}
GITHUB520_REPO_URL="https://github.com/521xueweihan/GitHub520"
HOSTS_SOURCES=(
    "https://raw.hellogithub.com/hosts"
    "https://fastly.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://gcore.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://testingcf.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://quantil.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://cdn.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
    "https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"
)
HOSTS_FILE="/etc/hosts"
RESOLV_FILE="/etc/resolv.conf"
SNAPSHOT_TIMEOUT=30

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

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_INFO=$'\033[1;34m'
    C_OK=$'\033[1;32m'
    C_WARN=$'\033[1;33m'
    C_ERR=$'\033[1;31m'
else
    C_RESET=""
    C_INFO=""
    C_OK=""
    C_WARN=""
    C_ERR=""
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
log() {
    printf '%s[INFO]%s %s\n' "$C_INFO" "$C_RESET" "$*"
}

ok() {
    printf '%s[ OK ]%s %s\n' "$C_OK" "$C_RESET" "$*"
}

warn() {
    printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2
}

err() {
    printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
}

die() {
    err "$*"
    exit 1
}

# -----------------------------------------------------------------------------
# Cleanup / rollback
# -----------------------------------------------------------------------------
cleanup() {
    local rc=$?
    trap - ERR
    if [ "$HOSTS_WRITTEN" -eq 1 ] && [ "$HOSTS_COMMITTED" -ne 1 ] &&
       [ -n "$HOSTS_BACKUP" ] && [ -f "$HOSTS_BACKUP" ]; then
        warn "Deployment did not complete; restoring $HOSTS_FILE from backup."
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
    local rc=$?
    err "Unexpected command failure at line $1 (status $rc)."
    exit "$rc"
}

trap cleanup EXIT
trap 'on_error "$LINENO"' ERR
trap 'exit 130' INT TERM

# -----------------------------------------------------------------------------
# Step 0: privileges
# -----------------------------------------------------------------------------
deny_access() {
    err "ACCESS DENIED: $*"
    err "Advice: run this script as root (for example: su -), or ask an"
    err "administrator to grant your account sudo privileges, then retry."
    exit 1
}

require_root() {
    local self

    if [ "$(id -u)" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            log "Privilege check passed: running as root via sudo (invoked by $SUDO_USER)."
        else
            log "Privilege check passed: running as root."
        fi
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        deny_access "this account is not root and the sudo command is not available."
    fi

    self=$(readlink -f -- "$0" 2>/dev/null || true)
    if [ -z "$self" ]; then
        self="$PWD/$0"
    fi

    if [ "${GITHUB520_ELEVATED:-0}" = "1" ]; then
        deny_access "root privileges are still unavailable after the sudo re-exec."
    fi

    if sudo -n true 2>/dev/null; then
        log "Privilege check: sudo credentials are already available; re-executing with sudo."
        export GITHUB520_ELEVATED=1
        exec sudo -n -- bash "$self" "$@"
    fi

    log "Root privileges are required; sudo may ask for your password."
    if ! sudo -v; then
        deny_access "sudo authentication failed, or this account is not allowed to use sudo."
    fi

    log "sudo authentication succeeded; re-executing the script with sudo."
    export GITHUB520_ELEVATED=1
    exec sudo -- bash "$self" "$@"
}

# -----------------------------------------------------------------------------
# Step 1: operating system
# -----------------------------------------------------------------------------
detect_os() {
    local kernel virt dmi pretty

    kernel=$(uname -s 2>/dev/null || printf 'unknown')
    if [ "$kernel" != "Linux" ]; then
        err "Unsupported operating system: $kernel."
        err "This script only supports native Linux. Windows, macOS and other"
        err "non-Linux systems are not supported."
        exit 1
    fi

    if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ] ||
       grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        err "Windows Subsystem for Linux (WSL) detected. WSL is not supported."
        err "Run this script on a native Linux installation instead."
        exit 1
    fi

    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] ||
       grep -qaE '(docker|kubepods|containerd|lxc)' /proc/1/cgroup 2>/dev/null; then
        err "Container environment detected. Containers are not supported."
        exit 1
    fi

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt=$(systemd-detect-virt 2>/dev/null || true)
        if [ -n "$virt" ] && [ "$virt" != "none" ]; then
            err "Virtual machine or container environment detected: $virt."
            err "This script only runs on native Linux installations."
            exit 1
        fi
    fi

    dmi=$(
        {
            cat /sys/class/dmi/id/product_name 2>/dev/null || true
            cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true
        } | tr '\n' ' '
    )
    case "${dmi,,}" in
        *virtualbox*|*vmware*|*kvm*|*qemu*|*hyper-v*|*xen*|*parallels*|*bochs*)
            err "Virtual machine detected through DMI data: $dmi"
            err "This script only runs on native Linux installations."
            exit 1
            ;;
    esac

    pretty=""
    if [ -r /etc/os-release ]; then
        pretty=$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null |
            cut -d= -f2- | tr -d '"' || true)
    fi
    [ -n "$pretty" ] || pretty="Linux"

    ok "Operating system check passed: $pretty (native Linux)."
}

# -----------------------------------------------------------------------------
# Step 2: filesystem and optional Btrfs/snapper snapshot
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
        warn "The root subvolume is named '${root_name:-unknown}', not '@'; snapshotting root config '$root_cfg' anyway."
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
    local deadline choice="" rc

    require_tty

    printf '\nSnapshot options (Btrfs with snapper detected):\n'
    printf '  1) Snapshot all snapper configs (all subvolumes)\n'
    printf '  2) Snapshot only the @ subvolume (root config)\n'
    printf '  3) Do not snapshot (abort deployment)\n'

    deadline=$((SECONDS + SNAPSHOT_TIMEOUT))
    while true; do
        local remaining=$((deadline - SECONDS))
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
                die "Failed to read the snapshot selection (end of input)."
            fi
        fi
    done
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
        log "Root filesystem is '$root_fs', not Btrfs; snapshot step skipped."
        SNAPSHOT_DONE="not applicable (root filesystem: $root_fs)"
        return 0
    fi

    log "Root filesystem is Btrfs."

    if ! command -v snapper >/dev/null 2>&1; then
        log "snapper is not installed; snapshot step skipped."
        SNAPSHOT_DONE="skipped (snapper not installed)"
        return 0
    fi

    if ! command -v btrfs >/dev/null 2>&1; then
        die "btrfs-progs is required to list Btrfs subvolumes, but the btrfs command is missing."
    fi

    if ! btrfs subvolume list / > "$TMP_DIR/btrfs-subvolumes.txt" 2> "$TMP_DIR/btrfs-subvolumes.err"; then
        die "Failed to list Btrfs subvolumes: $(tr '\n' ' ' < "$TMP_DIR/btrfs-subvolumes.err")"
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
        log "Btrfs is in use but snapper has no configurations; snapshot step skipped."
        SNAPSHOT_DONE="skipped (no snapper configs)"
        return 0
    fi

    log "Snapper configurations detected:"
    while IFS=, read -r cfg sub; do
        cfg=${cfg%$'\r'}
        sub=${sub%$'\r'}
        cfg=${cfg//\"/}
        sub=${sub//\"/}
        [ -n "$cfg" ] || continue
        printf '  config: %-12s subvolume: %s\n' "$cfg" "${sub:-unknown}"
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
        3) die "No snapshot was requested; aborting deployment as required." ;;
        *) die "Invalid snapshot selection." ;;
    esac

    SNAPSHOT_CHOICE=""
    ok "Snapshot created: $SNAPSHOT_DONE."
}

# -----------------------------------------------------------------------------
# Step 3: network backend detection and GitHub520 availability
# -----------------------------------------------------------------------------
detect_network_backends() {
    local -a managers=()

    if command -v ip >/dev/null 2>&1; then
        :
    else
        die "iproute2 (the 'ip' command) is required but was not found."
    fi

    if command -v nmcli >/dev/null 2>&1; then
        managers+=("NetworkManager")
    fi
    if [ -f /etc/network/interfaces ]; then
        managers+=("ifupdown")
    fi
    if [ -d /etc/netplan ] && compgen -G "/etc/netplan/*.yaml" >/dev/null; then
        managers+=("netplan")
    fi
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        managers+=("systemd-networkd")
    fi
    if command -v dhcpcd >/dev/null 2>&1; then
        managers+=("dhcpcd")
    fi
    if command -v connmanctl >/dev/null 2>&1; then
        managers+=("ConnMan")
    fi
    if command -v wicked >/dev/null 2>&1; then
        managers+=("wicked")
    fi
    if command -v netctl >/dev/null 2>&1; then
        managers+=("netctl")
    fi

    if [ "${#managers[@]}" -gt 0 ]; then
        log "Network management backends detected: ${managers[*]}"
    else
        warn "No known network management backend was detected."
    fi
}

detect_default_route() {
    local route i
    local -a fields=()

    if ! route=$(ip -4 route show default 2>/dev/null | head -n 1); then
        die "Failed to read the IPv4 routing table."
    fi

    if [ -z "$route" ]; then
        die "No IPv4 default route is present. Connect the machine to a network and retry."
    fi

    read -r -a fields <<< "$route"
    for ((i = 0; i < ${#fields[@]}; i++)); do
        case "${fields[i]}" in
            via) GATEWAY=${fields[i + 1]:-} ;;
            dev) IFACE=${fields[i + 1]:-} ;;
        esac
    done

    if [ -z "$IFACE" ]; then
        die "Could not determine the default network interface from: $route"
    fi

    CURRENT_CIDR=$(ip -o -4 addr show dev "$IFACE" scope global 2>/dev/null |
        awk '{print $4; exit}' || true)

    log "Default route: interface=$IFACE gateway=${GATEWAY:-unknown} address=${CURRENT_CIDR:-unknown}"

    if [ -n "$GATEWAY" ] && ! valid_ipv4 "$GATEWAY"; then
        warn "The detected gateway '$GATEWAY' is not a valid IPv4 address."
        GATEWAY=""
    fi
}

check_github520() {
    local url code reachable=0

    if ! command -v curl >/dev/null 2>&1; then
        die "curl is required to download GitHub520 but was not found."
    fi

    log "Checking whether the GitHub520 project is reachable..."
    log "Upstream repository: $GITHUB520_REPO_URL"
    log "Configured sources: ${#HOSTS_SOURCES[@]}"

    for url in "${HOSTS_SOURCES[@]}"; do
        log "Probing GitHub520 source: $url"
        code=""
        if code=$(curl -fsSL --connect-timeout 6 --max-time 15 \
            --retry 1 --retry-delay 1 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null); then
            if [ "$code" = "200" ]; then
                ok "Source reachable (HTTP 200): $url"
                reachable=1
                break
            fi
            warn "Unexpected HTTP status $code from $url."
        else
            warn "Request failed for $url."
        fi
    done

    if [ "$reachable" -ne 1 ]; then
        die "GitHub520 is unavailable from all configured sources. Check network, DNS, proxy or firewall settings and retry."
    fi

    SELECTED_HOSTS_URL=""
}

validate_hosts_block() {
    local file=$1 start end entries

    if [ ! -s "$file" ]; then
        warn "Downloaded GitHub520 content is empty."
        return 1
    fi

    start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$file" || true)
    end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$file" || true)

    if [ "$start" -ne 1 ] || [ "$end" -ne 1 ]; then
        warn "Downloaded content is not a valid GitHub520 hosts block (start=$start, end=$end)."
        return 1
    fi

    entries=$(grep -cE '^[[:space:]]*([0-9]{1,3}\.){3}[0-9]{1,3}[[:space:]]+[A-Za-z0-9._-]+' "$file" || true)
    if [ "$entries" -lt 5 ]; then
        warn "Downloaded GitHub520 block contains too few host entries ($entries)."
        return 1
    fi

    HOSTS_DOWNLOAD_ENTRIES=$entries
    ok "GitHub520 block is valid ($entries host mappings)."
    return 0
}

fetch_hosts_block() {
    local out="$TMP_DIR/hosts.remote"
    local try="$TMP_DIR/hosts.remote.try"
    local url code index=0 total=${#HOSTS_SOURCES[@]}

    log "Downloading the GitHub520 hosts block with automatic source fallback..."

    for url in "${HOSTS_SOURCES[@]}"; do
        index=$((index + 1))
        log "Source $index/$total: $url"

        rm -f -- "$try"
        code=""

        if ! code=$(curl -fsSL --connect-timeout 8 --max-time 25 \
            --retry 1 --retry-delay 1 -o "$try" -w '%{http_code}' "$url"); then
            warn "Download failed from source $index/$total; trying the next source."
            continue
        fi

        if [ "$code" != "200" ]; then
            warn "Source $index/$total returned HTTP $code; trying the next source."
            continue
        fi

        if [ ! -s "$try" ]; then
            warn "Source $index/$total returned an empty file; trying the next source."
            continue
        fi

        if ! validate_hosts_block "$try"; then
            warn "Source $index/$total returned invalid content; trying the next source."
            continue
        fi

        if ! mv -f -- "$try" "$out"; then
            die "Failed to stage the downloaded GitHub520 hosts block."
        fi

        SELECTED_HOSTS_URL=$url
        ok "Using GitHub520 source $index/$total: $url"
        return 0
    done

    rm -f -- "$try"
    die "All ${#HOSTS_SOURCES[@]} GitHub520 sources failed. No changes were made to $HOSTS_FILE."
}

# -----------------------------------------------------------------------------
# Step 4: install /etc/hosts
# -----------------------------------------------------------------------------
backup_hosts_file() {
    local stamp

    if [ ! -f "$HOSTS_FILE" ]; then
        die "$HOSTS_FILE does not exist."
    fi

    stamp=$(date '+%Y%m%d-%H%M%S')
    HOSTS_BACKUP="${HOSTS_FILE}.github520-backup.${stamp}.$$"

    log "Backing up $HOSTS_FILE to $HOSTS_BACKUP"
    if ! cp -L -p -- "$HOSTS_FILE" "$HOSTS_BACKUP"; then
        die "Failed to back up $HOSTS_FILE."
    fi
    if ! cmp -s -- "$HOSTS_FILE" "$HOSTS_BACKUP"; then
        die "Backup verification failed for $HOSTS_FILE."
    fi

    ok "Backup verified."
}

build_new_hosts() {
    local base="$TMP_DIR/hosts.base"
    local new="$TMP_DIR/hosts.new"
    local existing_start existing_end new_start new_end

    existing_start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" || true)
    existing_end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" || true)

    if [ "$existing_start" -ne "$existing_end" ]; then
        die "$HOSTS_FILE contains an unbalanced GitHub520 block (start=$existing_start, end=$existing_end). Repair it manually and retry."
    fi

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
            if (!skip) {
                print
            }
        }
    ' "$HOSTS_FILE" > "$base"; then
        die "Failed to strip the previous GitHub520 block from $HOSTS_FILE."
    fi

    {
        cat "$base"
        printf '\n'
        cat "$TMP_DIR/hosts.remote"
        printf '\n'
    } > "$new"

    new_start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$new" || true)
    new_end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$new" || true)

    if [ "$new_start" -ne 1 ] || [ "$new_end" -ne 1 ]; then
        die "Generated hosts content is invalid (start=$new_start, end=$new_end)."
    fi
}

install_new_hosts() {
    local attrs

    if [ ! -w "$HOSTS_FILE" ]; then
        die "$HOSTS_FILE is not writable, even with root privileges."
    fi

    if command -v lsattr >/dev/null 2>&1; then
        attrs=$(lsattr -d "$HOSTS_FILE" 2>/dev/null | awk '{print $1}' || true)
        case "$attrs" in
            *i*)
                die "$HOSTS_FILE has the immutable attribute set; remove it with 'chattr -i' and retry."
                ;;
        esac
    fi

    HOSTS_WRITTEN=1

    log "Writing the new GitHub520 block to $HOSTS_FILE..."
    if ! cat -- "$TMP_DIR/hosts.new" > "$HOSTS_FILE"; then
        die "Failed to write $HOSTS_FILE."
    fi

    if ! grep -qiE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE"; then
        die "Verification failed: the GitHub520 block is missing from $HOSTS_FILE."
    fi

    HOSTS_ENTRY_COUNT=$(grep -cE '^[[:space:]]*([0-9]{1,3}\.){3}[0-9]{1,3}[[:space:]]+[A-Za-z0-9._-]+' "$HOSTS_FILE" || true)
    if [ "$HOSTS_ENTRY_COUNT" -lt "$HOSTS_DOWNLOAD_ENTRIES" ]; then
        die "Verification failed: expected at least $HOSTS_DOWNLOAD_ENTRIES entries, found $HOSTS_ENTRY_COUNT."
    fi

    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$HOSTS_FILE" >/dev/null 2>&1 || true
    fi

    HOSTS_COMMITTED=1
    ok "$HOSTS_FILE updated with $HOSTS_ENTRY_COUNT GitHub520 host entries."
}

flush_dns_caches() {
    log "Flushing DNS caches (best effort)..."

    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
    elif command -v systemd-resolve >/dev/null 2>&1; then
        systemd-resolve --flush-caches >/dev/null 2>&1 || true
    fi

    if command -v nscd >/dev/null 2>&1; then
        nscd -i hosts >/dev/null 2>&1 || true
    fi

    if command -v dnsmasq >/dev/null 2>&1 &&
       command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet dnsmasq 2>/dev/null; then
        systemctl restart dnsmasq >/dev/null 2>&1 || true
    fi

    ok "DNS cache flush attempted."
}

# -----------------------------------------------------------------------------
# Validation helpers
# -----------------------------------------------------------------------------
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

require_tty() {
    if [ ! -t 0 ]; then
        die "This step requires an interactive terminal on stdin. Run the script directly from a terminal."
    fi
}

prompt_read() {
    local __var=$1 __text=$2 __value=""

    printf '%s' "$__text"
    if ! IFS= read -r __value; then
        printf '\n'
        die "Failed to read input; an interactive terminal is required."
    fi
    printf -v "$__var" '%s' "$__value"
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

join_dns_yaml() {
    local out="" d
    for d in "${DNS_SERVERS[@]}"; do
        out+="${out:+, }\"$d\""
    done
    printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# Step 5: optional static IPv4 / DNS configuration
# -----------------------------------------------------------------------------
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

select_network_backend() {
    local uuid src

    BACKEND=""
    BACKEND_ID=""
    BACKEND_FILE=""

    if command -v nmcli >/dev/null 2>&1 &&
       command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet NetworkManager 2>/dev/null; then
        uuid=$(nmcli -t -f UUID,DEVICE connection show --active 2>/dev/null |
            awk -F: -v dev="$IFACE" '$2 == dev {print $1; exit}' || true)
        if [ -n "$uuid" ]; then
            BACKEND="networkmanager"
            BACKEND_ID=$uuid
            NET_BACKEND_DESC="NetworkManager (connection UUID $uuid)"
            log "Selected configuration backend: $NET_BACKEND_DESC"
            return 0
        fi
    fi

    if command -v netplan >/dev/null 2>&1 &&
       [ -d /etc/netplan ] &&
       compgen -G "/etc/netplan/*.yaml" >/dev/null; then
        BACKEND="netplan"
        BACKEND_ID=$IFACE
        NET_BACKEND_DESC="netplan"
        log "Selected configuration backend: netplan"
        return 0
    fi

    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        BACKEND="networkd"
        BACKEND_ID=$IFACE
        NET_BACKEND_DESC="systemd-networkd"
        log "Selected configuration backend: systemd-networkd"
        return 0
    fi

    if src=$(find_ifupdown_file); then
        BACKEND="ifupdown"
        BACKEND_ID=$IFACE
        BACKEND_FILE=$src
        NET_BACKEND_DESC="ifupdown ($src)"
        log "Selected configuration backend: $NET_BACKEND_DESC"
        return 0
    fi

    die "No supported network configuration backend was found for interface $IFACE (NetworkManager, netplan, systemd-networkd and ifupdown were checked)."
}

current_dns_servers() {
    if command -v resolvectl >/dev/null 2>&1 &&
       command -v systemctl >/dev/null 2>&1 &&
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

read_dns_value() {
    local __var=$1 __label=$2 __default=$3 __val=""

    while true; do
        if [ -n "$__default" ]; then
            prompt_read __val "$__label [$__default]: "
            if [ -z "$__val" ]; then
                __val=$__default
            fi
        else
            prompt_read __val "$__label (optional, press Enter to skip): "
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

create_network_backup_dir() {
    local stamp
    stamp=$(date '+%Y%m%d-%H%M%S')
    NET_BACKUP_DIR="/var/backups/github520-${stamp}.$$"

    if ! install -d -m 0700 "$NET_BACKUP_DIR" 2>/dev/null; then
        if ! mkdir -p "$NET_BACKUP_DIR" || ! chmod 0700 "$NET_BACKUP_DIR"; then
            die "Failed to create the network backup directory: $NET_BACKUP_DIR"
        fi
    fi

    log "Network configuration backups will be stored in: $NET_BACKUP_DIR"
}

apply_networkmanager() {
    local uuid=$1 dns_csv con_name
    local -a cmd=()

    con_name=$(nmcli -t -f UUID,NAME connection show 2>/dev/null |
        awk -F: -v u="$uuid" '$1 == u {print $2; exit}' || true)

    if ! nmcli -t -f ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns \
        connection show "$uuid" > "$NET_BACKUP_DIR/NetworkManager-${uuid}.txt" 2>&1; then
        warn "Could not save the previous NetworkManager settings."
    fi

    log "Configuring NetworkManager connection '${con_name:-$uuid}'..."

    cmd=(connection modify "$uuid" ipv4.method manual
        ipv4.addresses "$STATIC_CIDR" ipv4.gateway "$GATEWAY")

    if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
        dns_csv=$(join_dns_csv)
        cmd+=(ipv4.dns "$dns_csv" ipv4.ignore-auto-dns yes)
    fi

    if ! nmcli "${cmd[@]}"; then
        die "Failed to modify NetworkManager connection '$uuid'. Previous settings: $NET_BACKUP_DIR/NetworkManager-${uuid}.txt"
    fi

    if ! nmcli connection up "$uuid"; then
        die "Failed to activate NetworkManager connection '$uuid'. Previous settings: $NET_BACKUP_DIR/NetworkManager-${uuid}.txt"
    fi

    NET_BACKEND_DESC="NetworkManager (connection ${con_name:-$uuid})"
}

netplan_supports_routes() {
    local ver
    ver=$(netplan --version 2>/dev/null | head -n 1 |
        grep -oE '[0-9]+\.[0-9]+' | head -n 1 || true)

    if [ -z "$ver" ]; then
        return 0
    fi

    if [ "$(printf '%s\n' "0.99" "$ver" | sort -V | head -n 1)" = "0.99" ]; then
        return 0
    fi
    return 1
}

restore_netplan_file() {
    local file=$1 old=$2

    rm -f -- "$file"
    if [ -n "$old" ] && [ -f "$old" ]; then
        cp -a -- "$old" "$file" || warn "Failed to restore $file from $old."
    fi
    netplan apply >/dev/null 2>&1 || true
}

apply_netplan() {
    local file="/etc/netplan/90-github520-static.yaml"
    local old=""
    local dns_yaml=""

    if [ -e "$file" ]; then
        old="$NET_BACKUP_DIR/90-github520-static.yaml"
        if ! cp -a -- "$file" "$old"; then
            die "Failed to back up the existing $file."
        fi
    fi

    if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
        dns_yaml=$(join_dns_yaml)
    fi

    log "Writing netplan configuration: $file"
    {
        printf 'network:\n'
        printf '  version: 2\n'
        printf '  ethernets:\n'
        printf '    "%s":\n' "$IFACE"
        printf '      dhcp4: false\n'
        printf '      addresses: [%s]\n' "$STATIC_CIDR"
        if netplan_supports_routes; then
            printf '      routes:\n'
            printf '        - to: default\n'
            printf '          via: %s\n' "$GATEWAY"
        else
            printf '      gateway4: %s\n' "$GATEWAY"
        fi
        if [ -n "$dns_yaml" ]; then
            printf '      nameservers:\n'
            printf '        addresses: [%s]\n' "$dns_yaml"
        fi
    } > "$file"

    chmod 600 "$file"

    if ! netplan generate; then
        restore_netplan_file "$file" "$old"
        die "netplan generate failed; the previous configuration was restored."
    fi

    if ! netplan apply; then
        restore_netplan_file "$file" "$old"
        die "netplan apply failed; the previous configuration was restored."
    fi

    NET_BACKEND_DESC="netplan ($file)"
}

restore_networkd_file() {
    local file=$1 old=$2

    if [ -n "$old" ] && [ -f "$old" ]; then
        cp -a -- "$old" "$file" || warn "Failed to restore $file from $old."
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

    if [ ! -d "$dir" ]; then
        die "systemd-networkd is active but $dir does not exist."
    fi

    if [ -e "$file" ]; then
        old="$NET_BACKUP_DIR/99-github520-${IFACE}.network"
        if ! cp -a -- "$file" "$old"; then
            die "Failed to back up the existing $file."
        fi
    fi

    log "Writing systemd-networkd configuration: $file"
    {
        printf '[Match]\n'
        printf 'Name=%s\n\n' "$IFACE"
        printf '[Network]\n'
        printf 'DHCP=no\n'
        printf 'Address=%s\n' "$STATIC_CIDR"
        printf 'Gateway=%s\n' "$GATEWAY"
        for d in "${DNS_SERVERS[@]}"; do
            printf 'DNS=%s\n' "$d"
        done
    } > "$file"

    chmod 644 "$file"

    if command -v networkctl >/dev/null 2>&1; then
        if ! networkctl reload; then
            restore_networkd_file "$file" "$old"
            die "networkctl reload failed; the previous configuration was restored."
        fi
        if ! networkctl reconfigure "$IFACE"; then
            restore_networkd_file "$file" "$old"
            die "networkctl reconfigure failed; the previous configuration was restored."
        fi
    else
        if ! systemctl reload systemd-networkd; then
            restore_networkd_file "$file" "$old"
            die "Failed to reload systemd-networkd; the previous configuration was restored."
        fi
    fi

    NET_BACKEND_DESC="systemd-networkd ($file)"
}

apply_ifupdown() {
    local src=$BACKEND_FILE
    local base="$TMP_DIR/interfaces.base"
    local new="$TMP_DIR/interfaces.new"
    local old="$NET_BACKUP_DIR/$(basename -- "$src")"
    local netmask dns_space=""

    if [ -z "$src" ] || [ ! -f "$src" ]; then
        die "The ifupdown configuration file was not found."
    fi

    if ! cp -a -- "$src" "$old"; then
        die "Failed to back up $src."
    fi

    netmask=$(prefix_to_netmask "$STATIC_PREFIX")
    dns_space=$(join_dns_space)

    log "Rewriting ifupdown stanza for $IFACE in $src"
    if ! awk -v iface="$IFACE" '
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
    ' "$src" > "$base"; then
        die "Failed to parse $src."
    fi

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

    if ! cat -- "$new" > "$src"; then
        cp -a -- "$old" "$src" 2>/dev/null || true
        die "Failed to write $src."
    fi

    if command -v ifquery >/dev/null 2>&1; then
        if ! ifquery "$IFACE" >/dev/null 2>&1; then
            cp -a -- "$old" "$src" 2>/dev/null || true
            die "ifquery rejected the new configuration; the previous file was restored."
        fi
    fi

    log "Restarting interface $IFACE through ifupdown..."
    ifdown "$IFACE" >/dev/null 2>&1 || true
    if ! ifup "$IFACE"; then
        cp -a -- "$old" "$src" 2>/dev/null || true
        ifup "$IFACE" >/dev/null 2>&1 || true
        die "ifup failed for $IFACE; the previous configuration was restored."
    fi

    NET_BACKEND_DESC="ifupdown ($src)"
}

write_resolv_conf() {
    local backup new d

    if [ -L "$RESOLV_FILE" ]; then
        warn "$RESOLV_FILE is a symbolic link; refusing to overwrite it directly."
        return 0
    fi

    backup="${RESOLV_FILE}.github520-backup.$(date '+%Y%m%d-%H%M%S').$$"
    if ! cp -L -p -- "$RESOLV_FILE" "$backup" 2>/dev/null; then
        warn "Could not back up $RESOLV_FILE."
        backup=""
    fi

    new="$TMP_DIR/resolv.new"
    {
        grep -vE '^[[:space:]]*nameserver[[:space:]]' "$RESOLV_FILE" 2>/dev/null || true
        for d in "${DNS_SERVERS[@]}"; do
            printf 'nameserver %s\n' "$d"
        done
    } > "$new"

    if ! cat -- "$new" > "$RESOLV_FILE"; then
        die "Failed to write $RESOLV_FILE."
    fi

    log "Updated $RESOLV_FILE with ${#DNS_SERVERS[@]} DNS server(s)."
    if [ -n "$backup" ]; then
        log "resolv.conf backup: $backup"
    fi
}

apply_dns_settings() {
    local d

    if [ "${#DNS_SERVERS[@]}" -eq 0 ]; then
        return 0
    fi

    if command -v resolvectl >/dev/null 2>&1 &&
       command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if ! resolvectl dns "$IFACE" "${DNS_SERVERS[@]}"; then
            warn "resolvectl could not set the DNS servers for $IFACE."
        fi
        resolvectl flush-caches >/dev/null 2>&1 || true
        return 0
    fi

    if command -v resolvconf >/dev/null 2>&1; then
        {
            for d in "${DNS_SERVERS[@]}"; do
                printf 'nameserver %s\n' "$d"
            done
        } | resolvconf -a "github520-$IFACE" || warn "resolvconf could not apply the DNS servers."
        return 0
    fi

    write_resolv_conf
}

wait_for_static_ip() {
    local tries=${1:-10} i
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

verify_network_config() {
    local dns_ok=0 d

    log "Verifying the new network configuration..."

    if ! wait_for_static_ip 12; then
        die "Static address $STATIC_CIDR is not active on $IFACE. Backups: $NET_BACKUP_DIR"
    fi

    if ! ip -4 route show default 2>/dev/null | grep -Fq "via $GATEWAY"; then
        warn "The default route via $GATEWAY was not confirmed."
    fi

    if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
        if command -v resolvectl >/dev/null 2>&1 &&
           resolvectl dns "$IFACE" 2>/dev/null | grep -Fq "${DNS_SERVERS[0]}"; then
            dns_ok=1
        fi
        if grep -qE "^[[:space:]]*nameserver[[:space:]]+${DNS_SERVERS[0]}([[:space:]]|$)" "$RESOLV_FILE" 2>/dev/null; then
            dns_ok=1
        fi
        if [ "$dns_ok" -eq 0 ]; then
            warn "DNS server ${DNS_SERVERS[0]} was not confirmed in the active resolver configuration."
        fi
    fi

    NETWORK_CONFIGURED=1
    ok "Static IPv4 configuration is active on $IFACE."
}

configure_static_network() {
    local ip_input dns1 dns2 def1 def2 pfx
    local -a cur_dns=()

    require_tty
    select_network_backend
    create_network_backup_dir

    while [ -z "$GATEWAY" ] || ! valid_ipv4 "$GATEWAY"; do
        prompt_read GATEWAY "Default gateway could not be detected. Enter the gateway IPv4 address: "
        if ! valid_ipv4 "$GATEWAY"; then
            warn "Invalid gateway address: $GATEWAY"
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
            if [ -z "$ip_input" ]; then
                ip_input=$CURRENT_CIDR
            fi
        else
            prompt_read ip_input "Static IPv4 address in CIDR form (e.g. 192.168.1.50/24): "
        fi

        if [[ $ip_input != */* ]]; then
            pfx=24
            if [[ $CURRENT_CIDR == */* ]]; then
                pfx=${CURRENT_CIDR#*/}
            fi
            ip_input="${ip_input}/${pfx}"
            log "No prefix length supplied; using /$pfx."
        fi

        if valid_cidr "$ip_input"; then
            break
        fi
        warn "Invalid IPv4 CIDR '$ip_input'. Example: 192.168.1.50/24"
    done

    STATIC_CIDR=$ip_input
    STATIC_ADDR=${ip_input%/*}
    STATIC_PREFIX=${ip_input#*/}

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
        warn "No DNS servers were provided; only the static address will be changed."
    fi

    log "Applying static address $STATIC_CIDR on $IFACE via $NET_BACKEND_DESC..."
    warn "Changing the address may interrupt an active remote session (for example SSH)."

    case "$BACKEND" in
        networkmanager) apply_networkmanager "$BACKEND_ID" ;;
        netplan) apply_netplan ;;
        networkd) apply_networkd ;;
        ifupdown) apply_ifupdown ;;
        *) die "Internal error: unknown network backend '$BACKEND'." ;;
    esac

    apply_dns_settings
    verify_network_config

    ok "Network configuration completed via $NET_BACKEND_DESC."
}

maybe_configure_static_network() {
    local answer

    printf '\n'
    printf '%sGitHub520 hosts entries are deployed.%s\n' "$C_OK" "$C_RESET"

    if [ ! -t 0 ]; then
        warn "No interactive terminal is available; skipping the optional static IP/DNS step."
        return 0
    fi

    prompt_read answer "Change this machine's static IPv4 address and DNS servers now? [y/N]: "
    case "$answer" in
        y|Y|yes|YES|Yes)
            configure_static_network
            ;;
        *)
            log "No network configuration changes requested."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------
print_final_summary() {
    printf '\n%s========================================================%s\n' "$C_OK" "$C_RESET"
    printf '%s GitHub520 deployment completed successfully%s\n' "$C_OK" "$C_RESET"
    printf '%s========================================================%s\n' "$C_OK" "$C_RESET"
    printf '  hosts file        : %s\n' "$HOSTS_FILE"
    printf '  hosts source      : %s\n' "$SELECTED_HOSTS_URL"
    printf '  hosts backup      : %s\n' "$HOSTS_BACKUP"
    printf '  GitHub520 entries : %s\n' "$HOSTS_ENTRY_COUNT"
    printf '  snapshot          : %s\n' "$SNAPSHOT_DONE"

    if [ "$NETWORK_CONFIGURED" -eq 1 ]; then
        printf '  network backend   : %s\n' "$NET_BACKEND_DESC"
        printf '  static address    : %s\n' "$STATIC_CIDR"
        printf '  gateway           : %s\n' "$GATEWAY"
        if [ "${#DNS_SERVERS[@]}" -gt 0 ]; then
            printf '  DNS servers       : %s\n' "${DNS_SERVERS[*]}"
        fi
        printf '  network backups   : %s\n' "$NET_BACKUP_DIR"
    else
        printf '  network changes   : none\n'
    fi

    printf '\n  Tip: verify the result with: getent hosts github.com\n'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    require_root "$@"
    detect_os

    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-deploy.XXXXXX")
    if [ -z "$TMP_DIR" ] || [ ! -d "$TMP_DIR" ]; then
        die "Failed to create a temporary directory."
    fi
    log "Temporary workspace: $TMP_DIR"

    detect_filesystem_and_snapshot
    detect_network_backends
    detect_default_route
    check_github520
    fetch_hosts_block

    backup_hosts_file
    build_new_hosts
    install_new_hosts
    flush_dns_caches

    maybe_configure_static_network
    print_final_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
