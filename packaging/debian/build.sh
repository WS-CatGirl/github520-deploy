#!/usr/bin/env bash
#
# Build the Debian package for the generic Linux entry.
# Run this on Debian/Ubuntu, not on Arch; it only assembles the package and
# does not install or run anything.
#
#   ./packaging/debian/build.sh [output-directory]
#
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
PKG=github520-deploy
VERSION=$(sed -n 's/^Version: //p' "$SCRIPT_DIR/control" | head -n 1)
OUT_DIR=${1:-"$REPO_ROOT/dist"}

[ -n "$VERSION" ] || {
    printf 'Unable to read Version from %s/control\n' "$SCRIPT_DIR" >&2
    exit 1
}

mkdir -p "$OUT_DIR"
STAGE=$(mktemp -d /tmp/github520-deb.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

install -d "$STAGE/DEBIAN" \
    "$STAGE/usr/bin" \
    "$STAGE/usr/lib/$PKG" \
    "$STAGE/lib/systemd/system" \
    "$STAGE/usr/share/doc/$PKG"

install -Dm755 "$REPO_ROOT/github520-deploy.sh" "$STAGE/usr/bin/$PKG"
install -Dm644 "$REPO_ROOT/lib/github520-common.sh" \
    "$STAGE/usr/lib/$PKG/github520-common.sh"
install -Dm644 "$REPO_ROOT/lib/core.sh" \
    "$STAGE/usr/lib/$PKG/core.sh"
install -Dm644 "$REPO_ROOT/lib/snapshots.sh" \
    "$STAGE/usr/lib/$PKG/snapshots.sh"
install -Dm644 "$REPO_ROOT/lib/network.sh" \
    "$STAGE/usr/lib/$PKG/network.sh"
install -Dm644 "$REPO_ROOT/lib/ssh.sh" \
    "$STAGE/usr/lib/$PKG/ssh.sh"
install -Dm644 "$REPO_ROOT/lib/hosts.sh" \
    "$STAGE/usr/lib/$PKG/hosts.sh"
install -Dm644 "$REPO_ROOT/lib/systemd.sh" \
    "$STAGE/usr/lib/$PKG/systemd.sh"
install -Dm644 "$REPO_ROOT/lib/uninstall.sh" \
    "$STAGE/usr/lib/$PKG/uninstall.sh"
install -Dm644 "$REPO_ROOT/lib/installer.sh" \
    "$STAGE/usr/lib/$PKG/installer.sh"
install -Dm644 "$REPO_ROOT/lib/cli.sh" \
    "$STAGE/usr/lib/$PKG/cli.sh"
install -Dm644 "$REPO_ROOT/lib/platform-generic.sh" \
    "$STAGE/usr/lib/$PKG/platform-generic.sh"
install -Dm644 /dev/null "$STAGE/usr/lib/$PKG/.packaged"

install -Dm644 "$SCRIPT_DIR/github520-deploy-update.service" \
    "$STAGE/lib/systemd/system/github520-deploy-update.service"
install -Dm644 "$SCRIPT_DIR/github520-deploy-update.timer" \
    "$STAGE/lib/systemd/system/github520-deploy-update.timer"

install -Dm644 "$REPO_ROOT/LICENSE" "$STAGE/usr/share/doc/$PKG/copyright"
install -Dm644 "$REPO_ROOT/README.md" "$STAGE/usr/share/doc/$PKG/README.md"
install -Dm644 "$SCRIPT_DIR/changelog" "$STAGE/usr/share/doc/$PKG/changelog"
gzip -9n "$STAGE/usr/share/doc/$PKG/changelog"

install -Dm644 "$SCRIPT_DIR/control" "$STAGE/DEBIAN/control"
install -Dm755 "$SCRIPT_DIR/postinst" "$STAGE/DEBIAN/postinst"
install -Dm755 "$SCRIPT_DIR/prerm" "$STAGE/DEBIAN/prerm"
install -Dm755 "$SCRIPT_DIR/postrm" "$STAGE/DEBIAN/postrm"

(
    cd "$STAGE"
    find usr lib -type f -print0 |
        LC_ALL=C sort -z |
        xargs -0 md5sum > DEBIAN/md5sums
)

chmod 0755 "$STAGE"

dpkg-deb --root-owner-group --build "$STAGE" \
    "$OUT_DIR/${PKG}_${VERSION}_all.deb"

printf 'Built: %s\n' "$OUT_DIR/${PKG}_${VERSION}_all.deb"
