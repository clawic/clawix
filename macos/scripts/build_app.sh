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

python3 "$SCRIPT_DIR/compile_xcstrings.py"

echo "==> Building Swift package (release)…"
cd "$PROJECT_DIR"
swift build -c release 2>&1
echo "==> Building Secrets XPC service (release)…"
swift build -c release --target ClawixSecretsXPC 2>&1

BINARY="$PROJECT_DIR/.build/release/${APP_NAME}"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not found at $BINARY"
    exit 1
fi
SECRETS_XPC_BINARY="$PROJECT_DIR/.build/release/ClawixSecretsXPC"
if [[ ! -f "$SECRETS_XPC_BINARY" ]]; then
    echo "ERROR: Secrets XPC service binary not found at $SECRETS_XPC_BINARY"
    exit 1
fi

echo "==> Assembling app bundle at $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BINARY" "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
cp "$ICON_FILE" "$BUNDLE_DIR/Contents/Resources/Clawix.icns"
SECRETS_XPC_SERVICE_NAME="${BUNDLE_ID}.secrets-xpc"
SECRETS_XPC_BUNDLE="$BUNDLE_DIR/Contents/XPCServices/ClawixSecretsXPC.xpc"
mkdir -p "$SECRETS_XPC_BUNDLE/Contents/MacOS"
cp "$SECRETS_XPC_BINARY" "$SECRETS_XPC_BUNDLE/Contents/MacOS/ClawixSecretsXPC"
chmod +x "$SECRETS_XPC_BUNDLE/Contents/MacOS/ClawixSecretsXPC"
cat > "$SECRETS_XPC_BUNDLE/Contents/Info.plist" << XPCPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>ClawixSecretsXPC</string>
    <key>CFBundleIdentifier</key>        <string>${SECRETS_XPC_SERVICE_NAME}</string>
    <key>CFBundleName</key>              <string>ClawixSecretsXPC</string>
    <key>CFBundlePackageType</key>       <string>XPC!</string>
    <key>CLXAllowedCallerIdentifier</key><string>${BUNDLE_ID}</string>
    <key>XPCService</key>
    <dict>
        <key>ServiceType</key>           <string>Application</string>
    </dict>
</dict>
</plist>
XPCPLIST
RESOURCE_BUNDLE="$(find "$PROJECT_DIR/.build" -path "*/release/${APP_NAME}_${APP_NAME}.bundle" -type d | head -n 1 || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$BUNDLE_DIR/Contents/Resources/"
    while IFS= read -r lproj; do
        cp -R "$lproj" "$BUNDLE_DIR/Contents/Resources/"
    done < <(find "$RESOURCE_BUNDLE" -maxdepth 1 -name "*.lproj" -type d | sort)
    # Copy every other SwiftPM package bundle and compile any .xcassets
    # they contain. `swift build` does not run actool on package
    # resources for executables, so without this loop bundles like
    # `LucideIcon_LucideIcon.bundle` ship a raw .xcassets folder that
    # SwiftUI's `Image(name:bundle:)` cannot load at runtime.
    SWIFTPM_BUILD_DIR="$(dirname "$RESOURCE_BUNDLE")"
    shopt -s nullglob
    for spm_bundle in "$SWIFTPM_BUILD_DIR"/*.bundle; do
        bundle_name=$(basename "$spm_bundle")
        if [[ "$bundle_name" == "${APP_NAME}_${APP_NAME}.bundle" ]]; then
            continue
        fi
        dest="$BUNDLE_DIR/Contents/Resources/$bundle_name"
        cp -R "$spm_bundle" "$dest"
        while IFS= read -r -d '' xcassets; do
            out_dir=$(dirname "$xcassets")
            xcrun actool --compile "$out_dir" "$xcassets" \
                --platform macosx \
                --minimum-deployment-target 14.0 \
                --output-format human-readable-text >/dev/null
            rm -rf "$xcassets"
        done < <(find "$dest" -type d -name "*.xcassets" -print0)
    done
    shopt -u nullglob
else
    echo "ERROR: resource bundle not found for release build"
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
    <key>ClawJSVersion</key>             <string>${CLAWJS_VERSION}</string>
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
    <key>NSCameraUsageDescription</key>
    <string>Clawix uses the camera so you can attach a photo straight from the QuickAsk panel.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Clawix shows your calendar events inside its Calendar workspace.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Clawix reads and edits your calendar events inside its Calendar workspace.</string>
    <key>NSContactsUsageDescription</key>
    <string>Clawix shows your contacts inside its Contacts workspace.</string>
    <key>SUFeedURL</key>                 <string>${SU_FEED_URL}</string>${SU_ED_KEY_BLOCK}
    <key>SUEnableAutomaticChecks</key>   <true/>
    <key>SUScheduledCheckInterval</key>  <integer>86400</integer>
    <key>SUEnableInstallerLauncherService</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>    <string>${BUNDLE_ID}.oauth-callback</string>
            <key>CFBundleURLSchemes</key> <array><string>clawix</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Sparkle.framework: copy from .build XCFramework into the app bundle.
SPARKLE_FW="$(find "$PROJECT_DIR/.build" -path "*/Sparkle.xcframework/macos-*/Sparkle.framework" -type d -prune 2>/dev/null | head -n 1 || true)"
if [[ -n "$SPARKLE_FW" ]]; then
    mkdir -p "$BUNDLE_DIR/Contents/Frameworks"
    rm -rf "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FW" "$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
else
    echo "WARN: Sparkle.framework not found in .build; auto-update will be inert" >&2
fi

# Per-component signing. --deep with --identifier corrupts nested
# bundle ids (Sparkle.framework would inherit the app's bundle id and
# fail dyld library validation). Sign nested components first without
# --identifier, then the .app top-level with --identifier.
echo "==> Signing $BUNDLE_DIR (identity: ${SIGN_IDENTITY})"
sign_one() {
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$1"
}
SPARKLE_BUNDLE="$BUNDLE_DIR/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_BUNDLE" ]]; then
    SPARKLE_CURRENT="$SPARKLE_BUNDLE/Versions/Current"
    while IFS= read -r xpc; do
        sign_one "$xpc"
    done < <(find "$SPARKLE_CURRENT/XPCServices" -maxdepth 1 -name "*.xpc" 2>/dev/null || true)
    [[ -e "$SPARKLE_CURRENT/Autoupdate" ]] && sign_one "$SPARKLE_CURRENT/Autoupdate"
    [[ -e "$SPARKLE_CURRENT/Updater.app" ]] && sign_one "$SPARKLE_CURRENT/Updater.app"
    sign_one "$SPARKLE_BUNDLE"
fi
if [[ -d "$BUNDLE_DIR/Contents/XPCServices" ]]; then
    while IFS= read -r xpc; do
        sign_one "$xpc"
    done < <(find "$BUNDLE_DIR/Contents/XPCServices" -maxdepth 1 -name "*.xpc" 2>/dev/null || true)
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$BUNDLE_DIR"

# Minimal PkgInfo
printf "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

echo ""
echo "Done: $BUNDLE_DIR"
echo "Bundle ID: $BUNDLE_ID"
echo "Launch: open '$BUNDLE_DIR'"
