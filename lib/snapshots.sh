#!/usr/bin/env bash
# =============================================================================
# snapshots.sh
#
# Btrfs / snapper snapshot detection and creation.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

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

