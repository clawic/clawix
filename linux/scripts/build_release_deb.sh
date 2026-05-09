#!/usr/bin/env bash
# Builds a signed .deb of Clawix for Debian/Ubuntu. The same shell binary
# and daemon as the AppImage; difference is the install layout
# (/opt/clawix/) and the apt repository registration in postinst.
#
# Output:
#   release-output/clawix_<version>_<arch>.deb
#
# Requires the same toolchain as the AppImage script + dpkg-deb + dpkg-sig.

set -euo pipefail

ARCH=${CLAWIX_LINUX_ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_ROOT="$ROOT/linux"
APP_DIR="$LINUX_ROOT/app"
DAEMON_DIR="$ROOT/macos/Helpers/Bridged"
OUT_DIR="$LINUX_ROOT/release-output"
VERSION="$(cat "$LINUX_ROOT/VERSION" | tr -d '\n[:space:]')"

mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
PKG_ROOT="$WORK/clawix_${VERSION}_${ARCH}"
mkdir -p \
  "$PKG_ROOT/DEBIAN" \
  "$PKG_ROOT/opt/clawix" \
  "$PKG_ROOT/usr/bin" \
  "$PKG_ROOT/usr/share/applications" \
  "$PKG_ROOT/usr/share/icons/hicolor/256x256/apps" \
  "$PKG_ROOT/usr/share/keyrings"

echo "[deb] building daemon (release)…"
( cd "$DAEMON_DIR" && swift build --configuration release )
cp "$DAEMON_DIR/.build/release/clawix-bridged" "$PKG_ROOT/opt/clawix/clawix-bridged"
chmod +x "$PKG_ROOT/opt/clawix/clawix-bridged"

echo "[deb] building frontend + shell…"
( cd "$APP_DIR" && npm install --silent && npm run build && npx tauri build --bundles "" )
cp "$APP_DIR/src-tauri/target/release/clawix-linux" "$PKG_ROOT/opt/clawix/clawix"
chmod +x "$PKG_ROOT/opt/clawix/clawix"

ln -s /opt/clawix/clawix "$PKG_ROOT/usr/bin/clawix"

cp "$LINUX_ROOT/packaging/appimage/clawix.desktop" "$PKG_ROOT/usr/share/applications/clawix.desktop"
cp "$LINUX_ROOT/packaging/appimage/clawix.png" "$PKG_ROOT/usr/share/icons/hicolor/256x256/apps/clawix.png"

cp "$LINUX_ROOT/packaging/debian/control.in" "$PKG_ROOT/DEBIAN/control"
sed -i "s/__VERSION__/$VERSION/g; s/__ARCH__/$ARCH/g" "$PKG_ROOT/DEBIAN/control"
cp "$LINUX_ROOT/packaging/debian/postinst" "$PKG_ROOT/DEBIAN/postinst"
cp "$LINUX_ROOT/packaging/debian/prerm" "$PKG_ROOT/DEBIAN/prerm"
cp "$LINUX_ROOT/packaging/debian/postrm" "$PKG_ROOT/DEBIAN/postrm"
chmod +x "$PKG_ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/prerm" "$PKG_ROOT/DEBIAN/postrm"

# Bundle the apt keyring so postinst can drop it into
# /usr/share/keyrings/clawix-archive-keyring.gpg without a network round-trip.
if [ -f "$LINUX_ROOT/packaging/debian/clawix-archive-keyring.gpg" ]; then
  install -m 0644 "$LINUX_ROOT/packaging/debian/clawix-archive-keyring.gpg" \
    "$PKG_ROOT/usr/share/keyrings/clawix-archive-keyring.gpg"
fi

OUT_PATH="$OUT_DIR/clawix_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$PKG_ROOT" "$OUT_PATH"

if command -v dpkg-sig >/dev/null 2>&1; then
  : "${GPG_KEY_ID:?GPG_KEY_ID must be exported (load via .signing.env)}"
  dpkg-sig --sign builder -k "$GPG_KEY_ID" "$OUT_PATH"
else
  echo "[deb] dpkg-sig not installed; skipping .deb signature" >&2
fi

echo "[deb] done → $OUT_PATH"
