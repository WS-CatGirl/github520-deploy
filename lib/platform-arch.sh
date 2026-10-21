# =============================================================================
# platform-arch.sh
#
# Arch Linux-specific overrides for github520-common.sh.
#
# Sourced after github520-common.sh by Github520-Arch.sh.
# =============================================================================

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

    # Parse in a subshell: sourcing os-release in this shell would overwrite
    # this script's VERSION and other global variables.
    os_id=$(
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        printf '%s' "${ID:-}"
    )
    pretty=$(
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        printf '%s' "${PRETTY_NAME:-Arch Linux}"
    )

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

detect_platform() {
    detect_arch
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
        log "Network backends detected: $(join_words "${managers[@]}")"
    else
        warn "No known network management backend was detected."
    fi
    log "NetworkManager is preferred for static IP/DNS changes on Arch."
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
