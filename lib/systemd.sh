#!/usr/bin/env bash
# =============================================================================
# systemd.sh
#
# Installed CLI/library copy, service and timer installation.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

# -----------------------------------------------------------------------------
# systemd timer/service
# -----------------------------------------------------------------------------
install_script_copy() {
    local src lib_src lib_file

    if [ "$PACKAGED_MODE" -eq 1 ]; then
        [ -x "$INSTALL_PATH" ] || die "Package-managed CLI is missing: $INSTALL_PATH"
        for lib_file in "${GITHUB520_LIB_FILES[@]}" "platform-${PLATFORM}.sh"; do
            [ -f "$LIB_INSTALL_DIR/$lib_file" ] || \
                die "Package-managed shared library is missing: $LIB_INSTALL_DIR/$lib_file"
        done
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
        for lib_file in "${GITHUB520_LIB_FILES[@]}" "platform-${PLATFORM}.sh"; do
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

