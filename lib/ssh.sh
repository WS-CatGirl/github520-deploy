#!/usr/bin/env bash
# =============================================================================
# ssh.sh
#
# SSH session and SSH-ancestor detection, plus the red safety warning.
#
# Sourced by github520-common.sh. Do not execute this file directly.
# =============================================================================

ssh_ancestor_detected() {
    local pid=$$ ppid="" comm="" depth=0

    while [ "$pid" -gt 1 ] && [ "$depth" -lt 12 ]; do
        comm=$(cat "/proc/$pid/comm" 2>/dev/null || true)
        case "$comm" in
            sshd|sshd-session|dropbear|mosh-server)
                return 0
                ;;
        esac

        ppid=$(awk '/^PPid:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)
        [ -n "$ppid" ] || return 1
        [ "$ppid" -gt 1 ] || return 1
        pid=$ppid
        depth=$((depth + 1))
    done

    return 1
}

is_ssh_session() {
    [ "${GITHUB520_SSH_SESSION:-0}" = "1" ] && return 0
    [ -n "${SSH_CONNECTION:-}" ] && return 0
    [ -n "${SSH_CLIENT:-}" ] && return 0
    [ -n "${SSH_TTY:-}" ] && return 0

    local env_file="/proc/${PPID:-0}/environ"
    if [ -r "$env_file" ] &&
       tr '\0' '\n' < "$env_file" 2>/dev/null |
           grep -E '^(SSH_(CONNECTION|CLIENT|TTY)=|GITHUB520_SSH_SESSION=1)' >/dev/null 2>&1; then
        return 0
    fi

    ssh_ancestor_detected
}

show_ssh_warning() {
    printf '\n%s' "$C_SSH_ALERT"
    printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
    printf '!!  SSH SESSION DETECTED / 检测到 SSH 连接                         !!\n'
    printf '!!  Changing IP/DNS may disconnect this session immediately.     !!\n'
    printf '!!  修改 IP 或 DNS 可能立即中断当前 SSH 连接。                    !!\n'
    printf '!!  Keep a local console/IPMI/out-of-band access ready.          !!\n'
    printf '!!  请准备好本地控制台、IPMI 或其他带外访问方式。                 !!\n'
    printf '!!  Type YES exactly (uppercase) to continue.                    !!\n'
    printf '!!  必须输入全大写 YES 才能继续；其他输入将跳过 IP/DNS 修改。    !!\n'
    printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
    printf '%s\n' "$C_RESET"
}
