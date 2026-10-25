#!/usr/bin/env bash
# =============================================================================
# installer.sh
#
# Installation workflow, update mode and final summary.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

# -----------------------------------------------------------------------------
# Existing installation detection
# -----------------------------------------------------------------------------
detect_existing_installation() {
    local cli="" real="" seen=" " self_real="" self_cmd_real="" starts=0 ends=0
    local unit="" timer_enabled="" timer_active="" service_enabled="" service_active=""
    local -a candidates=()

    EXISTING_INSTALL_REASONS=()
    EXISTING_INSTALL_CLI=0
    EXISTING_INSTALL_TIMER=0
    EXISTING_INSTALL_HOSTS=0

    self_real=$(readlink -f -- "${SELF:-$0}" 2>/dev/null || true)
    [ -n "$self_real" ] || self_real=${SELF:-$0}
    self_cmd_real=$(command -v -- "$0" 2>/dev/null || true)
    if [ -n "$self_cmd_real" ]; then
        self_cmd_real=$(readlink -f -- "$self_cmd_real" 2>/dev/null || printf '%s' "$self_cmd_real")
    fi

    candidates=(
        "$INSTALL_PATH"
        "/usr/local/bin/$PROGRAM_NAME"
        "/usr/bin/$PROGRAM_NAME"
        "/usr/local/bin/${PROGRAM_NAME}.sh"
    )
    if [ -n "$LEGACY_INSTALL_PATH" ]; then
        candidates+=("$LEGACY_INSTALL_PATH")
    fi

    for cli in "${candidates[@]}"; do
        [ -n "$cli" ] || continue
        case "$seen" in
            *" $cli "*) continue ;;
        esac
        seen+="$cli "

        [ -e "$cli" ] || continue

        # The CLI currently executing this install is not a conflict.
        real=$(readlink -f -- "$cli" 2>/dev/null || printf '%s' "$cli")
        if [ "$real" = "$self_real" ] ||
           { [ -n "$self_cmd_real" ] && [ "$real" = "$self_cmd_real" ]; }; then
            continue
        fi

        EXISTING_INSTALL_CLI=1
        EXISTING_INSTALL_REASONS+=("CLI found: $cli")
    done

    if [ -f "$HOSTS_FILE" ]; then
        starts=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" 2>/dev/null || true)
        ends=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" 2>/dev/null || true)
        if [ "${starts:-0}" -gt 0 ] || [ "${ends:-0}" -gt 0 ]; then
            EXISTING_INSTALL_HOSTS=1
            EXISTING_INSTALL_REASONS+=("Hosts block found in $HOSTS_FILE (start=$starts end=$ends)")
        fi
    fi

    # Source installs write their units into /etc/systemd/system. Package
    # units live under /usr/lib or /lib, so mere package installation is not
    # treated as configured.
    for unit in "/etc/systemd/system/$SERVICE_NAME" "/etc/systemd/system/$TIMER_NAME"; do
        if [ -e "$unit" ]; then
            EXISTING_INSTALL_TIMER=1
            EXISTING_INSTALL_REASONS+=("Systemd unit found: $unit")
        fi
    done

    if command -v systemctl >/dev/null 2>&1; then
        timer_enabled=$(systemctl is-enabled "$TIMER_NAME" 2>/dev/null || true)
        case "$timer_enabled" in
            enabled|enabled-runtime)
                EXISTING_INSTALL_TIMER=1
                EXISTING_INSTALL_REASONS+=("Timer is enabled: $TIMER_NAME")
                ;;
        esac

        timer_active=$(systemctl is-active "$TIMER_NAME" 2>/dev/null || true)
        if [ "$timer_active" = "active" ]; then
            EXISTING_INSTALL_TIMER=1
            EXISTING_INSTALL_REASONS+=("Timer is active: $TIMER_NAME")
        fi

        service_enabled=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)
        case "$service_enabled" in
            enabled|enabled-runtime)
                EXISTING_INSTALL_TIMER=1
                EXISTING_INSTALL_REASONS+=("Service is enabled: $SERVICE_NAME")
                ;;
        esac

        service_active=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)
        if [ "$service_active" = "active" ]; then
            EXISTING_INSTALL_TIMER=1
            EXISTING_INSTALL_REASONS+=("Service is active: $SERVICE_NAME")
        fi
    fi

    [ "${#EXISTING_INSTALL_REASONS[@]}" -gt 0 ]
}

assert_no_existing_installation() {
    local reason=""

    log "Checking for an existing GitHub520 installation."

    if ! detect_existing_installation; then
        log "No existing GitHub520 installation detected."
        return 0
    fi

    err "An existing GitHub520 installation was detected; refusing to install again."
    for reason in "${EXISTING_INSTALL_REASONS[@]}"; do
        err "  - $reason"
    done

    if [ "$EXISTING_INSTALL_CLI" -eq 1 ]; then
        err "To redeploy the installed CLI: sudo $PROGRAM_NAME reinstall"
        err "To remove it first: sudo $PROGRAM_NAME --uninstall-completely"
    elif [ "$EXISTING_INSTALL_TIMER" -eq 1 ]; then
        err "Disable and remove the existing timer/service first:"
        err "  sudo systemctl disable --now $TIMER_NAME"
        err "  sudo rm -f /etc/systemd/system/$SERVICE_NAME /etc/systemd/system/$TIMER_NAME"
        err "  sudo systemctl daemon-reload"
        if [ "$EXISTING_INSTALL_HOSTS" -eq 1 ]; then
            err "Also restore $HOSTS_FILE from a backup or remove the GitHub520 block."
        fi
    else
        err "Restore $HOSTS_FILE from a backup or remove the GitHub520 block manually,"
        err "then retry the installation."
    fi

    exit 1
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
    printf '    GitHub  : %s\n' "${REPO_URLS[0]}"
    printf '    Gitee   : %s\n' "${REPO_URLS[1]}"
    printf '    GitCode : %s\n' "${REPO_URLS[2]}"
    printf '    Codeberg: %s\n' "${REPO_URLS[3]}"
    printf '    Gitea   : %s\n' "${REPO_URLS[4]}"
    printf '\n'
    printf '  作者 / Author: 白丝小猫娘 (WS-CatGirl)\n'
    printf '  临时文件已清理，备份和日志已保留。\n'
    printf '  Temporary files cleaned; backups and logs retained.\n'
    printf '  感谢安装和使用，喵～ Ciallo～(∠・ω< )⌒★\n'
    printf '  Thank you for installing %s!\n' "$PROGRAM_LABEL"
    printf '\n'
    printf '  提示：这是 v1.0.1-rc 预发布版本，请先备份重要配置；遇到问题欢迎反馈。\n'
    printf '  Note: this is the v1.0.1-rc pre-release. Keep backups and report any issues.\n'
    printf '\n'
}

