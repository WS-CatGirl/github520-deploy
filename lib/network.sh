#!/usr/bin/env bash
# =============================================================================
# network.sh
#
# Network backend detection, static IPv4/DNS configuration, validation and
# rollback.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

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

    if is_ssh_session; then
        show_ssh_warning
        prompt_read answer "SSH safety gate - type YES to continue, anything else skips IP/DNS changes: "
        if [ "$answer" != "YES" ]; then
            warn "SSH safety gate not confirmed; skipping static IP/DNS changes."
            log "Continuing to the next installation step."
            return 0
        fi
        log "SSH safety gate confirmed; continuing to static network configuration."
        configure_static_network
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
