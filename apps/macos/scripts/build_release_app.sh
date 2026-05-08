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

# Build the bridge daemon for release. Lives in a sibling SPM package
# under Helpers/Bridged/, ships as Contents/Helpers/clawix-bridged so
# SMAppService.agent can register it as a LaunchAgent at runtime.
BRIDGED_PKG="$PROJECT_DIR/Helpers/Bridged"
BRIDGED_BINARY=""
if [[ -f "$BRIDGED_PKG/Package.swift" ]]; then
    echo "==> Building clawix-bridged daemon (release)"
    (cd "$BRIDGED_PKG" && swift build -c release \
        -Xswiftc -file-prefix-map -Xswiftc "${BRIDGED_PKG}/.build=clawix/.build" \
        -Xswiftc -file-prefix-map -Xswiftc "${BRIDGED_PKG}=clawix/apps/macos/Helpers/Bridged" \
        2>&1)
    BRIDGED_BINARY="$BRIDGED_PKG/.build/release/clawix-bridged"
    if [[ ! -f "$BRIDGED_BINARY" ]]; then
        echo "ERROR: clawix-bridged binary not produced at $BRIDGED_BINARY" >&2
        exit 1
    fi
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

# Embed the bridge daemon under Contents/Helpers/clawix-bridged plus
# its LaunchAgent plist under Contents/Library/LaunchAgents/. The
# plist label is the literal `clawix.bridge`, public and shared with
# the standalone npm CLI so both surfaces register the same agent slot
# and a machine that swaps CLI for GUI (or vice versa) hands ownership
# over without two daemons fighting for the loopback port. The same
# rationale picks `clawix.bridge` as the UserDefaults suite so the
# pairing bearer survives the swap.
if [[ -n "$BRIDGED_BINARY" ]]; then
    mkdir -p "$BUNDLE_DIR/Contents/Helpers" "$BUNDLE_DIR/Contents/Library/LaunchAgents"
    cp "$BRIDGED_BINARY" "$BUNDLE_DIR/Contents/Helpers/clawix-bridged"
    chmod +x "$BUNDLE_DIR/Contents/Helpers/clawix-bridged"

    AGENT_LABEL="clawix.bridge"
    AGENT_PLIST="$BUNDLE_DIR/Contents/Library/LaunchAgents/${AGENT_LABEL}.plist"
    cat > "$AGENT_PLIST" << AGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>                       <string>${AGENT_LABEL}</string>
    <key>BundleProgram</key>               <string>Contents/Helpers/clawix-bridged</string>
    <key>RunAtLoad</key>                   <true/>
    <key>KeepAlive</key>                   <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAWIX_BRIDGED_PORT</key>     <string>7778</string>
        <key>CLAWIX_BRIDGED_DEFAULTS_SUITE</key> <string>clawix.bridge</string>
    </dict>
    <key>StandardOutPath</key>             <string>/tmp/clawix-bridged.out</string>
    <key>StandardErrorPath</key>           <string>/tmp/clawix-bridged.err</string>
</dict>
</plist>
AGENTPLIST
fi

# Bundle the pinned @clawjs/cli release plus a Node runtime under
# Contents/Helpers/clawjs/. The script signs every nested .node with the
# Developer ID identity and hardened-runtime flags so the final
# `codesign --verify --deep --strict` and notarization both pass.
#
# DISABLED by default in release until the deep-codesign issue is
# resolved: `codesign --verify --deep --strict` chokes on bundled npm
# packages whose internal layout (package.json + nested locale .cjs
# files like `node_modules/zod/v4/locales/es.cjs`) is interpreted as
# a sub-bundle. The dev path has the same gate
# (CLAWIX_DEV_BUNDLE_CLAWJS) and `ClawJSRuntime.isAvailable` already
# returns false when the tree is missing, so the app starts clean.
# Re-enable here once `bundle_clawjs.sh` produces a layout that the
# outer deep-strict pass accepts (sealed sub-bundle under
# Contents/Helpers/, or a move to Contents/Resources/, both options
# are tracked in the plan's "Requests al equipo de ClawJS" list).
if [[ "${CLAWIX_RELEASE_BUNDLE_CLAWJS:-0}" == "1" ]]; then
    echo "==> Bundling ClawJS runtime"
    CLAWJS_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" \
    CLAWJS_SIGN_OPTS="--options runtime --timestamp" \
        bash "$SCRIPT_DIR/bundle_clawjs.sh" "$BUNDLE_DIR"
else
    echo "==> Skipping ClawJS bundling (set CLAWIX_RELEASE_BUNDLE_CLAWJS=1 once the deep-codesign layout is fixed)"
    rm -rf "$BUNDLE_DIR/Contents/Helpers/clawjs"
fi

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

HELPER_BIN="$BUNDLE_DIR/Contents/Helpers/clawix-bridged"
if [[ -f "$HELPER_BIN" ]]; then
    echo "==> Stripping absolute build paths from clawix-bridged"
    python3 "$SCRIPT_DIR/strip_user_paths.py" \
        "$HELPER_BIN" \
        --replace "${BRIDGED_PKG}/.build/=clawix/Helpers/Bridged/.build/" \
        --replace "${BRIDGED_PKG}/=clawix/apps/macos/Helpers/Bridged/" \
        --replace "$(dirname "${PROJECT_DIR}")/=clawix/apps/" \
        --replace "${HOME}/="
    echo "==> Signing clawix-bridged helper"
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID_IDENTITY" \
             --identifier "clawix.bridge" \
             "$HELPER_BIN"
fi

echo "==> Signing app binary + bundle (identity: $DEVELOPER_ID_IDENTITY)"
ENTITLEMENTS_FILE="${SCRIPT_DIR:-$(dirname "$0")}/Clawix.entitlements"
codesign --force --options runtime --timestamp \
         --entitlements "$ENTITLEMENTS_FILE" \
         --sign "$DEVELOPER_ID_IDENTITY" \
         "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"

codesign --force --options runtime --timestamp \
         --entitlements "$ENTITLEMENTS_FILE" \
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
