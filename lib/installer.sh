#!/usr/bin/env bash
# =============================================================================
# installer.sh
#
# Installation workflow, update mode and final summary.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

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
    printf '  提示：这是 v1.2-milestone.1 预发布版本，请先备份重要配置；遇到问题欢迎反馈。\n'
    printf '  Note: this is the v1.2-milestone.1 pre-release. Keep backups and report any issues.\n'
    printf '\n'
}

