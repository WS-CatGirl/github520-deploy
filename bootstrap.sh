#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh
#
# Version : v0.6-beta
#
# Small bootstrap entry point for github520-deploy.
#
# It does not install packages. It checks the environment, lets the user pick
# one repository source, clones that source into a temporary directory, and
# hands the terminal to install.sh.
#
# Intended public URL:
#   https://get.whitesocks-crs.top/bootstrap.sh
# =============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

WORKDIR=""
REPO_DIR=""
REPO_URL=""

info() {
    printf '[ INFO ] %s\n' "$*"
}

ok() {
    printf '[  OK  ] %s\n' "$*"
}

warn() {
    printf '[ WARN ] %s\n' "$*" >&2
}

err() {
    printf '[ FAIL ] %s\n' "$*" >&2
}

die() {
    err "$*"
    exit 1
}

cleanup() {
    local rc=$?
    trap - EXIT

    if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then
        rm -rf -- "$WORKDIR" 2>/dev/null || true
    fi

    exit "$rc"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

print_package_commands() {
    local package=$1
    local os_id="" os_like="" prefix=""

    if [ "$(id -u)" -eq 0 ]; then
        prefix=""
    else
        prefix="sudo "
    fi

    if [ -r /etc/os-release ]; then
        os_id=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${ID:-}"
        )
        os_like=$(
            # shellcheck disable=SC1091
            . /etc/os-release 2>/dev/null || true
            printf '%s' "${ID_LIKE:-}"
        )
    fi

    case "$os_id $os_like" in
        *arch*)
            printf '  Arch Linux: %spacman -S %s\n' "$prefix" "$package"
            ;;
        *debian*|*ubuntu*)
            printf '  Debian/Ubuntu: %sapt update && %sapt install -y %s\n' \
                "$prefix" "$prefix" "$package"
            ;;
        *fedora*|*rhel*|*centos*)
            printf '  Fedora/RHEL: %sdnf install -y %s\n' "$prefix" "$package"
            ;;
        *suse*|*opensuse*)
            printf '  openSUSE: %szypper install -y %s\n' "$prefix" "$package"
            ;;
        *alpine*)
            printf '  Alpine: %sapk add %s\n' "$prefix" "$package"
            ;;
        *)
            printf '  Install %s with your distribution package manager.\n' "$package"
            ;;
    esac
}

require_linux() {
    if [ "$(uname -s 2>/dev/null || true)" != "Linux" ]; then
        err "This bootstrap only supports Linux."
        exit 1
    fi
    ok "Linux detected."
}

require_bash() {
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        err "Bash 4 or newer is required."
        exit 1
    fi
    ok "Bash ${BASH_VERSION} detected."
}

require_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required to download the repository."
        print_package_commands curl
        exit 1
    fi
    ok "curl detected."
}

require_tty() {
    if ! (exec 3</dev/tty) 2>/dev/null; then
        err "An interactive terminal is required (/dev/tty is not available)."
        exit 1
    fi
    ok "Interactive terminal detected."
}

require_git() {
    if ! command -v git >/dev/null 2>&1; then
        err "git is required. Install it manually, then run this bootstrap again."
        print_package_commands git
        exit 1
    fi
    ok "Git detected: $(git --version 2>/dev/null || printf 'unknown')"
}

select_source() {
    local choice=""

    printf '\nSelect a repository source:\n'
    printf '  [1] GitHub\n'
    printf '  [2] Gitee (Login may be required)\n'
    printf '  [3] GitCode (Recommended for Chinese Users)\n'
    printf '  [4] Codeberg\n'
    printf 'Choice [1-4, default 3]: '

    if ! IFS= read -r choice < /dev/tty; then
        die "Failed to read the repository selection."
    fi

    choice=${choice//[[:space:]]/}
    choice=${choice:-3}

    case "$choice" in
        1)
            REPO_URL="https://github.com/WS-CatGirl/github520-deploy.git"
            ok "Selected GitHub."
            ;;
        2)
            REPO_URL="https://gitee.com/wscatgirl/github520-deploy.git"
            ok "Selected Gitee."
            ;;
        3)
            REPO_URL="https://gitcode.com/WS_CatGirl/github520-deploy.git"
            ok "Selected GitCode."
            ;;
        4)
            REPO_URL="https://codeberg.org/WS_CatGirl/github520-deploy.git"
            ok "Selected Codeberg."
            ;;
        *)
            die "Invalid selection: $choice"
            ;;
    esac
}

clone_repository() {
    local attempt

    for attempt in 1 2 3; do
        info "Cloning $REPO_URL (attempt $attempt/3)..."
        if GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main "$REPO_URL" "$REPO_DIR"; then
            ok "Repository cloned."
            return 0
        fi

        warn "Clone failed (attempt $attempt/3)."
        rm -rf -- "$REPO_DIR" 2>/dev/null || true
        if [ "$attempt" -lt 3 ]; then
            sleep 3
        fi
    done

    return 1
}

check_repository_files() {
    local file

    for file in install.sh Github520-Arch.sh github520-deploy.sh; do
        if [ ! -f "$REPO_DIR/$file" ]; then
            die "Required file is missing from the repository: $file"
        fi
    done
    ok "Repository files verified."
}

prompt_reselect_source() {
    local choice=""

    while true; do
        printf '\nClone failed after 3 attempts.\n'
        printf '  [r] Select another repository source\n'
        printf '  [q] Quit\n'
        printf 'Choice [r/q]: '

        if ! IFS= read -r choice < /dev/tty; then
            die "Failed to read the repository selection."
        fi

        choice=${choice//[[:space:]]/}
        case "${choice,,}" in
            r|reselect) return 0 ;;
            q|quit) return 1 ;;
            *) warn "Enter r or q." ;;
        esac
    done
}

main() {
    require_linux
    require_bash
    require_curl
    require_tty
    require_git

    WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/github520-bootstrap.XXXXXX") || \
        die "Failed to create a temporary directory."
    REPO_DIR="$WORKDIR/repo"

    while true; do
        select_source
        if clone_repository; then
            break
        fi

        warn "Could not clone the repository after 3 attempts."
        if ! prompt_reselect_source; then
            die "Installation cancelled by user."
        fi
    done

    check_repository_files

    info "Launching install.sh from the temporary clone..."
    set +e
    bash "$REPO_DIR/install.sh" < /dev/tty
    local rc=$?
    set -e
    exit "$rc"
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
