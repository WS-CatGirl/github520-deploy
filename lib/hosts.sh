#!/usr/bin/env bash
# =============================================================================
# hosts.sh
#
# GitHub520 source download, validation, /etc/hosts generation, backup,
# atomic install, DNS cache flushing and update locking.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

# -----------------------------------------------------------------------------
# GitHub520 sources, hosts update
# -----------------------------------------------------------------------------
acquire_update_lock() {
    local lock=$LOCK_FILE

    [ -d /run ] || lock="${TMPDIR:-/tmp}/github520-hosts.lock"
    command -v flock >/dev/null 2>&1 || return 0

    if ! exec 9>"$lock"; then
        warn "Could not open lock file $lock; continuing without locking."
        return 0
    fi
    if ! flock -w 120 9; then
        die "Another GitHub520 hosts update is still running."
    fi
}

release_update_lock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 9 >/dev/null 2>&1 || true
    fi
    exec 9>&- 2>/dev/null || true
}

prepare_github520_download() {
    command -v curl >/dev/null 2>&1 || die "curl is required."

    # fetch_hosts_block performs the real per-source probe and validation.
    # A separate probe here would download every source twice.
    log "Preparing GitHub520 download..."
    log "Upstream: $GITHUB520_REPO_URL"
}

validate_hosts_block() {
    local file=$1 start end entries start_line end_line

    [ -s "$file" ] || { warn "Downloaded content is empty."; return 1; }

    start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$file" || true)
    end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$file" || true)

    if [ "$start" -ne 1 ] || [ "$end" -ne 1 ]; then
        warn "Invalid GitHub520 block markers (start=$start end=$end)."
        return 1
    fi

    start_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$file" |
        head -n 1 | cut -d: -f1 || true)
    end_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$file" |
        head -n 1 | cut -d: -f1 || true)
    if [ -n "$start_line" ] && [ -n "$end_line" ] && [ "$start_line" -ge "$end_line" ]; then
        warn "Invalid GitHub520 block: end marker appears before start marker."
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

        if ! code=$(curl -fsSL --proto '=https' --proto-redir '=https' \
            --connect-timeout 8 --max-time 25 \
            --retry 1 --retry-delay 1 -o "$try" -w '%{http_code}' "$url"); then
            warn "Download failed${code:+ (HTTP $code)}; next source."
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
    ' "$file" 2>/dev/null || printf '0\n'
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
    local existing_start_line existing_end_line

    existing_start=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" || true)
    existing_end=$(grep -ciE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" || true)
    if [ "$existing_start" -ne "$existing_end" ]; then
        die "$HOSTS_FILE contains an unbalanced GitHub520 block."
    fi

    existing_start_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+start' "$HOSTS_FILE" |
        head -n 1 | cut -d: -f1 || true)
    existing_end_line=$(grep -niE '^[[:space:]]*#[[:space:]]*github520[[:space:]]+host[[:space:]]+end' "$HOSTS_FILE" |
        head -n 1 | cut -d: -f1 || true)
    if [ -n "$existing_start_line" ] && [ -n "$existing_end_line" ] &&
       [ "$existing_start_line" -ge "$existing_end_line" ]; then
        die "$HOSTS_FILE has its GitHub520 end marker before the start marker."
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
        # SIGHUP reloads /etc/hosts without dropping DNS service briefly.
        systemctl reload dnsmasq >/dev/null 2>&1 ||
            systemctl restart dnsmasq >/dev/null 2>&1 || true
    fi
}

apply_hosts_update() {
    acquire_update_lock
    prepare_github520_download
    fetch_hosts_block
    build_new_hosts
    install_new_hosts
    release_update_lock
}

