#!/usr/bin/env bash
# =============================================================================
# cli.sh
#
# CLI argument parsing, installation guard and command dispatch.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
${USAGE_TITLE} - GitHub520 manager for ${PLATFORM_DESC} (rc)

Usage:
  sudo ${PROGRAM_NAME} [command]
  sudo ./${REPO_SCRIPT_NAME} [command]
  ${PROGRAM_NAME}                 # show status and a short help hint

Installation:
  Source checkout : run ./install.sh from the cloned repository.
  Package         : run sudo ${PROGRAM_NAME} install.
  Direct installation through a repository copy of this script is rejected.

Commands:
  install, --install             Apply hosts, optional network settings and
                                 enable the timer. Refuses if another CLI,
                                 a hosts block or an active timer/service exists.
  reinstall                      Re-run the installer using the installed
                                 script; bypasses the existing-install check.
  update, refresh, --update      Immediately download and refresh /etc/hosts.
  status                         Show version, hosts count, timer state,
                                 last log line and backup count.
  logs [-f]                      Show the update log; -f follows it.
  restore [latest|original|FILE] Restore /etc/hosts from a backup.
  --uninstall                    Disable the timer and remove the CLI/units
                                 for a source install; package files remain.
  --uninstall-completely         Restore the original /etc/hosts, then remove
                                 logs, backups and temp files. Package files
                                 remain and must be removed with the system
                                 package manager.
  version, --version             Show version.
  help, --help                   Show this help.

Internal:
  --check-installed              Used by install.sh to detect an existing
                                 installation before asking for confirmation.
  --update --systemd             Used by ${SERVICE_NAME}. Redirects
                                 all output to ${LOG_DIR}/update.log.

Options:
  -f, --follow                   Follow the log (with logs).
      --force                    Skip the confirmation for --uninstall-completely.

Install flow (started by install.sh or the installed CLI):
  1. Welcome
  2. Root/sudo check
  3. ${PLATFORM_CHECK_DESC}
  4. Existing installation check (skipped by reinstall)
  5. Optional Btrfs/snapper snapshot
  6. Network backend detection
  7. GitHub520 download and /etc/hosts update
  8. Optional static IPv4/DNS configuration
  9. DNS validation and recovery
 10. Install and enable ${TIMER_NAME} (hourly)
 11. Final summary

Timer:
  systemctl status ${TIMER_NAME}
  systemctl list-timers ${TIMER_NAME}
  journalctl -u ${SERVICE_NAME}
  tail -f ${LOG_DIR}/update.log
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                usage
                exit 0
                ;;
            -V|--version|version)
                printf '%s %s (%s)\n' "$SCRIPT_NAME" "$VERSION" "$RELEASE_CHANNEL"
                exit 0
                ;;
            install|--install)
                COMMAND="install"
                ;;
            reinstall)
                COMMAND="install"
                REINSTALL=1
                ;;
            update|refresh|--update|--refresh)
                COMMAND="update"
                ;;
            status|--status)
                COMMAND="status"
                ;;
            logs|--logs)
                COMMAND="logs"
                ;;
            uninstall|--uninstall)
                COMMAND="uninstall"
                ;;
            uninstall-completely|--uninstall-completely)
                COMMAND="uninstall-complete"
                ;;
            restore|--restore)
                COMMAND="restore"
                if [ "$#" -gt 1 ]; then
                    case "$2" in
                        -*) ;;
                        *)
                            RESTORE_TARGET=$2
                            shift
                            ;;
                    esac
                fi
                ;;
            --check-installed)
                COMMAND="check-installed"
                ;;
            --systemd)
                SYSTEMD_MODE=1
                ;;
            -f|--follow)
                FOLLOW_LOG=1
                ;;
            --force)
                FORCE=1
                ;;
            --)
                shift
                if [ "$#" -gt 0 ]; then
                    err "Unexpected argument: $*"
                    exit 2
                fi
                break
                ;;
            *)
                err "Unknown command or option: $1"
                err "Run '$SCRIPT_NAME --help' for usage."
                exit 2
                ;;
        esac
        shift
    done

    [ -n "$COMMAND" ] || COMMAND="status"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
is_installed_cli() {
    [ -n "${SELF:-}" ] && [ "$SELF" = "$INSTALL_PATH" ] && return 0
    [ "$(command -v "$0" 2>/dev/null || true)" = "$INSTALL_PATH" ] && return 0
    return 1
}

main() {
    local welcome_shown=0

    if [ "${GITHUB520_CHECK_ONLY:-0}" != "1" ]; then
        show_prerelease_notice
    fi

    SELF=$(readlink -f -- "$0" 2>/dev/null || true)
    [ -n "$SELF" ] || SELF=${0:-}

    parse_args "$@"

    if [ "$COMMAND" = "install" ] &&
       [ "${GITHUB520_FROM_INSTALLER:-0}" != "1" ] &&
       ! is_installed_cli; then
        err "Direct installation is not supported."
        err "Please run: bash ./install.sh"
        exit 2
    fi

    case "$COMMAND" in
        check-installed)
            assert_no_existing_installation
            exit 0
            ;;
        status)
            show_status
            exit 0
            ;;
        logs)
            show_logs
            exit 0
            ;;
        install)
            if [ "$(id -u)" -eq 0 ]; then
                show_welcome
                welcome_shown=1
            fi

            require_root "$@"

            if [ "$welcome_shown" -eq 0 ]; then
                show_welcome
            fi

            detect_platform

            if [ "$REINSTALL" -eq 1 ]; then
                log "Reinstall requested; skipping the existing-installation check."
            else
                assert_no_existing_installation
            fi

            run_install
            ;;
        update)
            require_root "$@"
            detect_platform
            if [ "$SYSTEMD_MODE" -eq 1 ]; then
                run_update_mode
            else
                run_manual_update
            fi
            ;;
        uninstall)
            require_root "$@"
            do_uninstall "retain"
            ;;
        uninstall-complete)
            require_root "$@"
            do_uninstall "complete"
            ;;
        restore)
            require_root "$@"
            restore_hosts_command
            ;;
        *)
            err "Unknown command: $COMMAND"
            usage
            exit 2
            ;;
    esac
}
