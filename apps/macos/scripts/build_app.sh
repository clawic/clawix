#!/usr/bin/env bash
# Builds the Swift package and wraps the executable into a macOS .app bundle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Clawix"
BUNDLE_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
ICON_FILE="$PROJECT_DIR/Sources/Clawix/Resources/Clawix.icns"

# Optional maintainer config. Same rules as dev.sh: source `.signing.env`
# from the repo root or a parent directory; env vars win over file. The
# maintainer's real bundle id and codesign identity are NEVER hard-coded
# in this repo, they live in `.signing.env` outside the public tree.
BUNDLE_ID_DEFAULT="com.example.clawix.desktop"
for candidate in \
    "${SIGN_IDENTITY_FILE:-}" \
    "$PROJECT_DIR/.signing.env" \
    "$PROJECT_DIR/../.signing.env" \
    "$PROJECT_DIR/../../.signing.env" \
    "$PROJECT_DIR/../../../.signing.env"
do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    # shellcheck disable=SC1090
    set -a; source "$candidate"; set +a
    break
done
BUNDLE_ID="${BUNDLE_ID:-$BUNDLE_ID_DEFAULT}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Resolve marketing + build version for the generated Info.plist.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_emit_version.sh"

echo "==> Building Swift package (release)…"
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$PROJECT_DIR/.build/release/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not found at $BINARY"
    exit 1
fi

echo "==> Assembling app bundle at $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BINARY" "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
cp "$ICON_FILE" "$BUNDLE_DIR/Contents/Resources/Clawix.icns"
RESOURCE_BUNDLE="$(find "$PROJECT_DIR/.build" -path "*/release/${APP_NAME}_${APP_NAME}.bundle" -type d | head -n 1 || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$BUNDLE_DIR/Contents/Resources/"
    while IFS= read -r lproj; do
        cp -R "$lproj" "$BUNDLE_DIR/Contents/Resources/"
    done < <(find "$RESOURCE_BUNDLE" -maxdepth 1 -name "*.lproj" -type d | sort)
else
    echo "ERROR: resource bundle not found for release build"
    exit 1
fi

cat > "$BUNDLE_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>Clawix</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>              <string>Clawix</string>
    <key>CFBundleDisplayName</key>       <string>Clawix</string>
    <key>CFBundleIconFile</key>          <string>Clawix</string>
    <key>CFBundleVersion</key>           <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><false/></dict>
    <key>NSHumanReadableCopyright</key>  <string>Clawix</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Clawix uses the microphone to record voice notes that are transcribed into the composer.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Clawix transcribes recorded voice notes to insert them as text in the composer.</string>
</dict>
</plist>
PLIST

# Sign the release bundle. If SIGN_IDENTITY is "-" or empty, codesign uses
# ad-hoc; the resulting .app will not survive Gatekeeper for distribution
# but works fine locally. Maintainers ship by setting SIGN_IDENTITY in
# .signing.env (outside this repo).
echo "==> Signing $BUNDLE_DIR (identity: ${SIGN_IDENTITY})"
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$BUNDLE_DIR"

# Minimal PkgInfo
printf "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

echo ""
echo "Done: $BUNDLE_DIR"
echo "Bundle ID: $BUNDLE_ID"
echo "Launch: open '$BUNDLE_DIR'"
