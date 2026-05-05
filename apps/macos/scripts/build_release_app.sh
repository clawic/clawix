#!/usr/bin/env bash
# Builds a notarization-ready Clawix.app:
# - swift build -c release
# - bundles Sparkle.framework with per-component hardened-runtime signing
# - signs the whole .app with the release identity read from env
#
# This is the artifact the workspace-private release orchestrator
# (scripts-dev/release.sh) feeds into notarytool + create-dmg.
#
# Required env (typically via .signing.env at the workspace root):
#   DEVELOPER_ID_IDENTITY  → release codesign identity
#   BUNDLE_ID              → reverse-DNS bundle identifier
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Clawix"
BUNDLE_DIR="$PROJECT_DIR/build/Release/${APP_NAME}.app"
ICON_FILE="$PROJECT_DIR/Sources/Clawix/Resources/Clawix.icns"

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
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"

if [[ -z "$DEVELOPER_ID_IDENTITY" ]]; then
    echo "ERROR: DEVELOPER_ID_IDENTITY not set." >&2
    echo "Set it in .signing.env (workspace root) to a 'Developer ID Application' identity." >&2
    echo "List candidates with: security find-identity -v -p codesigning" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/_emit_version.sh"

echo "==> Compiling xcstrings"
python3 "$SCRIPT_DIR/compile_xcstrings.py"

echo "==> Building Swift package (release)"
cd "$PROJECT_DIR"
# Strip absolute build paths (Swift's `#file` and DWARF debug records embed
# them otherwise). With `-file-prefix-map`, each occurrence of the build
# directory in the binary is rewritten to a stable, anonymous prefix so
# the shipped artifact does not leak the maintainer's $HOME / username.
# Functionally a no-op; only rewrites string literals in the binary.
swift build -c release \
    -Xswiftc -file-prefix-map -Xswiftc "${PROJECT_DIR}/.build=clawix/.build" \
    -Xswiftc -file-prefix-map -Xswiftc "${PROJECT_DIR}=clawix/apps/macos" \
    2>&1

BINARY="$PROJECT_DIR/.build/release/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not produced at $BINARY" >&2
    exit 1
fi

echo "==> Assembling $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Frameworks"

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
    echo "ERROR: resource bundle not found for release build" >&2
    exit 1
fi

SU_FEED_URL_DEFAULT="https://github.com/clawic/clawix/releases/latest/download/appcast.xml"
SU_FEED_URL="${SU_FEED_URL:-$SU_FEED_URL_DEFAULT}"
SU_PUBLIC_ED_KEY="${SPARKLE_ED_PUB_KEY:-}"
SU_ED_KEY_BLOCK=""
if [[ -n "$SU_PUBLIC_ED_KEY" ]]; then
    SU_ED_KEY_BLOCK=$'\n    <key>SUPublicEDKey</key>            <string>'"$SU_PUBLIC_ED_KEY"$'</string>'
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
    <key>SUFeedURL</key>                 <string>${SU_FEED_URL}</string>${SU_ED_KEY_BLOCK}
    <key>SUEnableAutomaticChecks</key>   <true/>
    <key>SUScheduledCheckInterval</key>  <integer>86400</integer>
    <key>SUEnableInstallerLauncherService</key><true/>
</dict>
</plist>
PLIST
printf "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

# Sparkle.framework: copy from .build XCFramework into the app bundle.
SPARKLE_FW="$(find "$PROJECT_DIR/.build" -path "*/Sparkle.xcframework/macos-*/Sparkle.framework" -type d -prune 2>/dev/null | head -n 1 || true)"
if [[ -z "$SPARKLE_FW" ]]; then
    echo "ERROR: Sparkle.framework not found in .build (XCFramework missing)" >&2
    exit 1
fi
cp -R "$SPARKLE_FW" "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"

# Strip absolute build paths from the binary. Swift's -file-prefix-map
# only rewrites DWARF; #file literals embedded by precondition / GRDB
# code live in __TEXT,__cstring and need a post-build patch. Done before
# codesign so the signature seals the patched bytes.
echo "==> Stripping absolute build paths from binary"
# Pass the personal prefixes at runtime so the .py file holds none of
# them as source literals (the workspace forbids listing personal paths
# in any file under clawix/, even inside a "detection" routine).
python3 "$SCRIPT_DIR/strip_user_paths.py" \
    "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}" \
    --replace "${PROJECT_DIR}/.build/=clawix/.build/" \
    --replace "${PROJECT_DIR}/=clawix/apps/macos/" \
    --replace "$(dirname "${PROJECT_DIR}")/=clawix/apps/" \
    --replace "${HOME}/="

# Per-component signing with hardened runtime, in the order the
# notarization service requires: innermost executables first, then the
# framework wrapper, then the app binary, then the .app itself.
echo "==> Signing Sparkle internals"
SPARKLE_BUNDLE="$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
sign() {
    local target="$1"
    [[ -e "$target" ]] || return 0
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID_IDENTITY" \
             "$target"
}

# Sparkle ships its versioned content under Versions/B (the symlinked
# current version). Sign every nested executable Sparkle exposes.
SPARKLE_CURRENT="$SPARKLE_BUNDLE/Versions/Current"
while IFS= read -r xpc; do
    sign "$xpc"
done < <(find "$SPARKLE_CURRENT/XPCServices" -maxdepth 1 -name "*.xpc" 2>/dev/null || true)

if [[ -e "$SPARKLE_CURRENT/Autoupdate" ]]; then
    sign "$SPARKLE_CURRENT/Autoupdate"
fi
if [[ -e "$SPARKLE_CURRENT/Updater.app" ]]; then
    sign "$SPARKLE_CURRENT/Updater.app/Contents/MacOS/Updater" || true
    sign "$SPARKLE_CURRENT/Updater.app"
fi
sign "$SPARKLE_BUNDLE"

echo "==> Signing app binary + bundle (identity: $DEVELOPER_ID_IDENTITY)"
codesign --force --options runtime --timestamp \
         --sign "$DEVELOPER_ID_IDENTITY" \
         "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"

codesign --force --options runtime --timestamp \
         --sign "$DEVELOPER_ID_IDENTITY" \
         --identifier "$BUNDLE_ID" \
         "$BUNDLE_DIR"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"

echo ""
echo "Done: $BUNDLE_DIR"
echo "Marketing version: $MARKETING_VERSION"
echo "Build number: $BUILD_NUMBER"
echo "Bundle ID: $BUNDLE_ID"
