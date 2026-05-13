#!/usr/bin/env bash
# Builds a signed AppImage of Clawix for Linux. Equivalent to
# `clawix/macos/scripts/build_release_app.sh` for the .app bundle.
#
# Output:
#   release-output/Clawix-<version>-<arch>.AppImage
#   release-output/Clawix-<version>-<arch>.AppImage.zsync
#   release-output/Clawix-<version>-<arch>.AppImage.sig
#
# Requires:
#   - swift toolchain (for the bridge daemon)
#   - rust toolchain
#   - npm
#   - appimagetool (https://github.com/AppImage/AppImageKit/releases)
#   - gpg with the signing key referenced by GPG_KEY_ID
#   - zsyncmake
#
# `GPG_KEY_ID` is sourced from the workspace `.signing.env` exactly the
# same way `dev.sh` sources `SIGN_IDENTITY` for codesign.

set -euo pipefail

ARCH=${CLAWIX_LINUX_ARCH:-$(uname -m)}
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_ROOT="$ROOT/linux"
APP_DIR="$LINUX_ROOT/app"
DAEMON_DIR="$ROOT/macos/Helpers/Bridged"
OUT_DIR="$LINUX_ROOT/release-output"
VERSION="$(cat "$LINUX_ROOT/VERSION" | tr -d '\n[:space:]')"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[release] missing tool: $1" >&2
    exit 78
  fi
}
require swift
require cargo
require npm
require appimagetool
require zsyncmake
require gpg
: "${GPG_KEY_ID:?GPG_KEY_ID must be exported (load via .signing.env)}"

mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
APPDIR="$WORK/Clawix.AppDir"
mkdir -p "$APPDIR/usr/lib/clawix" "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

echo "[release] building daemon (release)…"
( cd "$DAEMON_DIR" && swift build --configuration release )
cp "$DAEMON_DIR/.build/release/clawix-bridge" "$APPDIR/usr/lib/clawix/clawix-bridge"

echo "[release] building frontend (release)…"
( cd "$APP_DIR" && npm install --silent && npm run build )

echo "[release] building Tauri shell (release, AppImage bundle off — we assemble manually)…"
( cd "$APP_DIR" && npx tauri build --bundles "" )
SHELL_BIN="$APP_DIR/src-tauri/target/release/clawix-linux"
cp "$SHELL_BIN" "$APPDIR/usr/bin/clawix"

echo "[release] copying packaging assets…"
cp "$LINUX_ROOT/packaging/appimage/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
cp "$LINUX_ROOT/packaging/appimage/clawix.desktop" "$APPDIR/clawix.desktop"
cp "$LINUX_ROOT/packaging/appimage/clawix.desktop" "$APPDIR/usr/share/applications/clawix.desktop"
cp "$LINUX_ROOT/packaging/appimage/clawix.png" "$APPDIR/clawix.png"
cp "$LINUX_ROOT/packaging/appimage/clawix.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/clawix.png"

# Optional: bundle Node for ClawJS runtime if a snapshot is staged.
if [ -d "$LINUX_ROOT/packaging/appimage/clawjs-node" ]; then
  echo "[release] bundling Node runtime for ClawJS…"
  cp -R "$LINUX_ROOT/packaging/appimage/clawjs-node" "$APPDIR/usr/lib/clawix/clawjs"
fi

OUT_NAME="Clawix-$VERSION-$ARCH.AppImage"
OUT_PATH="$OUT_DIR/$OUT_NAME"

echo "[release] assembling AppImage with appimagetool…"
ARCH=$ARCH appimagetool --updateinformation \
  "gh-releases-zsync|clawix|clawix|latest|Clawix-*-$ARCH.AppImage.zsync" \
  "$APPDIR" "$OUT_PATH"

echo "[release] generating zsync delta metadata…"
( cd "$OUT_DIR" && zsyncmake -u "$OUT_NAME" "$OUT_NAME" )

echo "[release] signing both artifacts with $GPG_KEY_ID…"
gpg --default-key "$GPG_KEY_ID" --detach-sign --armor "$OUT_PATH"
gpg --default-key "$GPG_KEY_ID" --detach-sign --armor "$OUT_PATH.zsync"
mv "$OUT_PATH.asc" "$OUT_PATH.sig"
mv "$OUT_PATH.zsync.asc" "$OUT_PATH.zsync.sig"

echo "[release] sha256:"
sha256sum "$OUT_PATH" "$OUT_PATH.zsync"

echo "[release] done → $OUT_PATH"
