#!/bin/sh
# =============================================================================
# askpass.sh
#
# Gitee HTTPS askpass helper for github520-deploy.
#
# Git calls this script with a prompt as the first argument. The script reads
# the token from GITEE_TOKEN_FILE and the account name from GITEE_USERNAME.
# It never reads credentials from its command line and never logs them.
#
# This file is a standalone helper for users who clone manually. bootstrap.sh
# generates an equivalent temporary helper because the repository is not
# available before the initial clone.
# =============================================================================

set -eu

prompt=${1:-}

case "$prompt" in
    *[Uu]sername*)
        [ -n "${GITEE_USERNAME:-}" ] || exit 1
        printf '%s\n' "$GITEE_USERNAME"
        ;;
    *[Pp]assword*|*[Tt]oken*)
        [ -n "${GITEE_TOKEN_FILE:-}" ] || exit 1
        [ -r "$GITEE_TOKEN_FILE" ] || exit 1
        token=$(tr -d '\r\n' < "$GITEE_TOKEN_FILE")
        [ -n "$token" ] || exit 1
        printf '%s\n' "$token"
        ;;
    *)
        exit 1
        ;;
esac
