#!/usr/bin/env bash
# =============================================================================
# uninstall.sh
#
# Hosts restore, uninstall, purge, status and log commands.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

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

