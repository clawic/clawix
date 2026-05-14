#!/usr/bin/env bash
# Dev launcher for Clawix.
#
# Builds, kills the previous Clawix process if any, and relaunches.
# The window position is preserved by NSWindow.setFrameAutosaveName("ClawixMainWindow"),
# so each rebuild reopens the window EXACTLY where the user left it.
#
# This script assembles the app in a staging location outside Desktop. A
# private workspace wrapper may set CLAWIX_DEV_INSTALL_BUNDLE to install that
# staged app into the canonical local slot before launch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Clawix"
# Bundle ID is overridable via env (typically through .signing.env). The
# default below is a clearly-placeholder value: anyone who wants to ship
# their own build should provide their own reverse-DNS bundle ID via
# BUNDLE_ID. The maintainer's real bundle ID is NOT stored in this repo.
BUNDLE_ID_DEFAULT="com.example.clawix.desktop"
# The staging bundle and runtime state live OUTSIDE ~/Desktop. If the .app
# sits inside ~/Desktop, macOS prompts for Desktop folder access every launch.
DEV_DIR="$HOME/Library/Caches/Clawix-Dev"
STAGING_BUNDLE="${CLAWIX_DEV_STAGING_BUNDLE:-$DEV_DIR/${APP_NAME}.app}"
INSTALL_BUNDLE="${CLAWIX_DEV_INSTALL_BUNDLE:-}"
BUNDLE="$STAGING_BUNDLE"
RELEASE_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"
BIN="$BUNDLE/Contents/MacOS/${APP_NAME}"
ICON_FILE="$PROJECT_DIR/Sources/Clawix/Resources/Clawix.icns"
LOG_FILE="$DEV_DIR/dev.log"
PID_FILE="$DEV_DIR/dev.pid"
LOCK_FILE="$DEV_DIR/dev.lock"

# Optional maintainer config. If a `.signing.env` file lives alongside the
# repo root or in a parent directory, source it here. It can set:
#
#   SIGN_IDENTITY  → stable codesign identity (so macOS TCC grants persist
#                    across rebuilds; "-" or empty means ad-hoc signing).
#   BUNDLE_ID      → reverse-DNS bundle id used to package the .app and
#                    sign it. Defaults to a placeholder if unset.
#
# Both ALSO accept being passed in the environment (env wins over file).
# This script never hard-codes the maintainer's bundle id or identity:
# they live in `.signing.env`, which lives OUTSIDE the public repo and is
# git-ignored if it ever gets copied inside.
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
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="${BUNDLE_ID:-$BUNDLE_ID_DEFAULT}"
REQUIRE_STABLE_SIGNING="${CLAWIX_DEV_REQUIRE_STABLE_SIGNING:-0}"
if [[ "$REQUIRE_STABLE_SIGNING" == "1" && ( -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ) ]]; then
    echo "ERROR: SIGN_IDENTITY is required for this dev install; refusing ad-hoc signing." >&2
    exit 1
fi

# Resolve marketing + build version. Sourced so MARKETING_VERSION and
# BUILD_NUMBER end up in this shell's environment for the plist heredoc.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_emit_version.sh"

mkdir -p "$DEV_DIR"

# Serialize: only one dev.sh runs at a time. Two parallel agents would
# otherwise race on the build/kill/launch sequence and leave duplicate
# windows. Wait politely instead of failing.
while ! ( set -C; echo $$ > "$LOCK_FILE" ) 2>/dev/null; do
    HOLDER=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if [[ -n "$HOLDER" ]] && ! kill -0 "$HOLDER" 2>/dev/null; then
        # Stale lock from a crashed run.
        rm -f "$LOCK_FILE"
        continue
    fi
    sleep 0.4
done
trap 'rm -f "$LOCK_FILE"' EXIT

# 0) Lint: squircle enforcement. Every corner radius in the app must be
#    rendered with style: .continuous (Apple's superellipse). Circular
#    corners are forbidden by the project's design canon. This check is
#    cheap and runs before swift build so a regression fails fast.
cd "$PROJECT_DIR"
echo "==> Lint: squircle (style: .continuous)"
SQ_BAD=""

# A) Single-line RoundedRectangle without .continuous.
A=$(grep -rn "RoundedRectangle(cornerRadius:" --include="*.swift" Sources/ \
    | grep -v "\.continuous" || true)
[[ -n "$A" ]] && SQ_BAD+=$'\n[A] RoundedRectangle without style: .continuous:\n'"$A"

# B) The .cornerRadius(N) modifier always clips with circular corners.
B=$(grep -rn "\.cornerRadius(" --include="*.swift" Sources/ || true)
[[ -n "$B" ]] && SQ_BAD+=$'\n[B] forbidden .cornerRadius() modifier (use clipShape with style: .continuous):\n'"$B"

# C) Explicit circular style.
C=$(grep -rn "style: \.circular\|RoundedCornerStyle\.circular" --include="*.swift" Sources/ || true)
[[ -n "$C" ]] && SQ_BAD+=$'\n[C] explicit style: .circular forbidden:\n'"$C"

# D) Multi-line UnevenRoundedRectangle / Path(roundedRect:...) without
#    .continuous within 6 lines of the opening.
#    NSBezierPath(roundedRect:xRadius:yRadius:) is AppKit and has no
#    `.continuous` variant. Project instructions allow it for capsule
#    /pill thumbs (radius >= ~40% of the shorter side), so we exclude it
#    here to avoid false positives on the scrollbar thumb.
D=$(awk '
  FNR==1 { needs=0; start=0; buf="" }
  needs {
    buf = buf "\n" $0
    if ($0 ~ /\.continuous/) { needs=0; buf="" }
    else if (FNR - start >= 6) {
      printf "%s:%d:\n%s\n---\n", FILENAME, start, buf
      needs=0; buf=""
    }
  }
  (/UnevenRoundedRectangle\(/ || /Path\(roundedRect:/) && !/NSBezierPath\(roundedRect:/ {
    start=FNR; needs=1; buf=$0
    if ($0 ~ /\.continuous/) { needs=0; buf="" }
  }
' $(find Sources -name "*.swift") || true)
[[ -n "$D" ]] && SQ_BAD+=$'\n[D] UnevenRoundedRectangle / Path(roundedRect:) without style: .continuous nearby:\n'"$D"

if [[ -n "$SQ_BAD" ]]; then
    echo "ERROR: squircle rule violated. Every corner radius must use style: .continuous." >&2
    echo "$SQ_BAD" >&2
    echo >&2
    echo "Fix: RoundedRectangle(cornerRadius: X, style: .continuous)" >&2
    exit 1
fi

# 0.5) Compile Localizable.xcstrings into per-locale .lproj/Localizable.strings.
#      SwiftPM (as of 6.x) does not process .xcstrings, so without this step
#      `bundle.localizations` is just ["es"] and the language selector cannot
#      switch the UI at runtime. The script is idempotent and ~20 ms.
echo "==> Compiling xcstrings…"
python3 "$SCRIPT_DIR/compile_xcstrings.py"

# 1) Build.
echo "==> Building Swift package…"
swift build 2>&1
echo "==> Building Secrets XPC service…"
swift build --target ClawixSecretsXPC 2>&1

if [[ ! -f "$PROJECT_DIR/.build/debug/${APP_NAME}" ]]; then
    echo "ERROR: binary not produced at .build/debug/${APP_NAME}"
    exit 1
fi
SECRETS_XPC_BIN_BUILT="$PROJECT_DIR/.build/debug/ClawixSecretsXPC"
if [[ ! -f "$SECRETS_XPC_BIN_BUILT" ]]; then
    echo "ERROR: Secrets XPC service binary not produced at $SECRETS_XPC_BIN_BUILT"
    exit 1
fi

# 1.4) Build the web SPA (clawix/web/) and stage it inside the daemon's
#      SwiftPM resource directory so `clawix-bridge` ships with the web
#      client embedded. The daemon serves it on its HTTP listener
#      (port 24081 by default). When pnpm or node is missing we skip with
#      a warning so the macOS dev loop stays unblocked; the daemon then
#      serves a 404 for the SPA but iOS keeps working untouched.
WEB_PKG="$PROJECT_DIR/../web"
WEB_DIST_SRC="$WEB_PKG/dist"
WEB_DIST_DEST="$PROJECT_DIR/Helpers/Bridged/Sources/clawix-bridge/Resources/web-dist"
if [[ -f "$WEB_PKG/package.json" ]] && command -v pnpm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
    echo "==> Building clawix/web/ SPA…"
    (cd "$WEB_PKG" && pnpm install --silent && pnpm --silent build) || {
        echo "WARN: web SPA build failed; daemon will keep previous bundle (or 404)" >&2
    }
    if [[ -d "$WEB_DIST_SRC" ]]; then
        mkdir -p "$WEB_DIST_DEST"
        # Mirror dist/ into the SwiftPM resource dir without leaving stale
        # files behind from a previous build.
        rsync -a --delete "$WEB_DIST_SRC/" "$WEB_DIST_DEST/"
        # Keep .gitkeep so the directory is committed even when empty.
        : > "$WEB_DIST_DEST/.gitkeep"
    fi
else
    echo "==> Skipping web SPA build (pnpm/node missing or web/ absent)"
fi

# 1.45) Wire the clawjs/iot dev pointer so ClawJSServiceManager can spawn
#       the IoT daemon (Phase 1 IoT integration). The daemon lives in the
#       sibling clawjs repo, not inside this tree, so a pointer file at
#       ~/Library/Application Support/Clawix/clawjs/dev-pointers/iot.dir
#       tells the supervisor where to find it. Production builds will
#       substitute a bundled copy under Contents/Resources/clawjs-iot/.
CLAWJS_IOT_DIR="${CLAWJS_IOT_DIR:-}"
if [[ -z "$CLAWJS_IOT_DIR" ]]; then
    for iot_candidate in \
        "${CLAWJS_DEV_OVERLAY:-}/iot" \
        "$PROJECT_DIR/../../../../clawjs/iot" \
        "$PROJECT_DIR/../../../clawjs/iot" \
        "$HOME/Desktop/clawjs/iot"
    do
        [[ -n "$iot_candidate" && -d "$iot_candidate" ]] || continue
        if [[ -f "$iot_candidate/package.json" ]]; then
            CLAWJS_IOT_DIR="$(cd "$iot_candidate" && pwd)"
            break
        fi
    done
fi

if [[ -n "$CLAWJS_IOT_DIR" ]] && command -v npm >/dev/null 2>&1; then
    echo "==> Building clawjs/iot for dev pointer ($CLAWJS_IOT_DIR)…"
    if [[ ! -d "$CLAWJS_IOT_DIR/node_modules" ]]; then
        (cd "$CLAWJS_IOT_DIR" && npm install --silent) || \
            echo "WARN: npm install failed in $CLAWJS_IOT_DIR" >&2
    fi
    (cd "$CLAWJS_IOT_DIR" && npm run --silent build:server) || \
        echo "WARN: iot build:server failed; .iot service will be blocked" >&2

    POINTER_DIR="$HOME/Library/Application Support/Clawix/clawjs/dev-pointers"
    mkdir -p "$POINTER_DIR"
    printf "%s\n" "$CLAWJS_IOT_DIR" > "$POINTER_DIR/iot.dir"
    echo "==> Wired iot dev pointer at $POINTER_DIR/iot.dir"
else
    echo "==> Skipping iot dev pointer (clawjs/iot not found or npm missing)"
fi

# 1.5) Build the bridge daemon (clawix-bridge). Lives in a sibling SPM
#      package under Helpers/Bridged/. The daemon shares ClawixEngine
#      with the GUI but is its own executable target so it can be
#      registered as a LaunchAgent later (SMAppService.agent), keeping
#      the iPhone bridge alive across Cmd+Q / GUI crashes.
#
#      The dev build embeds the daemon binary at
#      Contents/Helpers/clawix-bridge so the eventual SMAppService
#      registration finds it at the conventional path. The daemon is
#      NOT auto-registered or auto-started here — that requires a
#      Settings UI toggle which lands in a later phase.
BRIDGED_PKG="$PROJECT_DIR/Helpers/Bridged"
BRIDGED_BIN_BUILT=""
if [[ -f "$BRIDGED_PKG/Package.swift" ]]; then
    echo "==> Building clawix-bridge daemon…"
    (cd "$BRIDGED_PKG" && swift build 2>&1)
    BRIDGED_BIN_BUILT="$BRIDGED_PKG/.build/debug/clawix-bridge"
    if [[ ! -f "$BRIDGED_BIN_BUILT" ]]; then
        echo "WARN: clawix-bridge binary not produced; bundle will ship without daemon" >&2
        BRIDGED_BIN_BUILT=""
    fi
fi

# 2) Kill any previous instance, however launched.
#    The frame is persisted on every move/resize, so killing is safe.
PIDS=$({
    pgrep -f "${DEV_DIR}/.*/${APP_NAME}" 2>/dev/null || true
    pgrep -f "${PROJECT_DIR}/build/.*/${APP_NAME}" 2>/dev/null || true
    pgrep -f "/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
} | sort -u)
if [[ -n "$PIDS" ]]; then
    echo "==> Stopping previous ${APP_NAME} (PIDs: $PIDS)"
    kill $PIDS 2>/dev/null || true
    # Give the app up to 3s to exit cleanly so applicationWillTerminate runs.
    for _ in 1 2 3 4 5 6; do
        sleep 0.5
        REMAIN=$({
            pgrep -f "${DEV_DIR}/.*/${APP_NAME}" 2>/dev/null || true
            pgrep -f "${PROJECT_DIR}/build/.*/${APP_NAME}" 2>/dev/null || true
            pgrep -f "/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
        } | sort -u)
        [[ -z "$REMAIN" ]] && break
    done
    REMAIN=$({
        pgrep -f "${DEV_DIR}/.*/${APP_NAME}" 2>/dev/null || true
        pgrep -f "${PROJECT_DIR}/build/.*/${APP_NAME}" 2>/dev/null || true
        pgrep -f "/Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    } | sort -u)
    if [[ -n "$REMAIN" ]]; then
        kill -9 $REMAIN 2>/dev/null || true
        sleep 0.3
    fi
fi

# 3) Assemble the .app bundle.
echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$DEV_DIR"
cp "$PROJECT_DIR/.build/debug/${APP_NAME}" "$BIN"
chmod +x "$BIN"
cp "$ICON_FILE" "$BUNDLE/Contents/Resources/Clawix.icns"

# 3.0) Compile SwiftPM package asset catalogs in place. `swift build`
#      does NOT run `actool` on `.xcassets` folders for executable
#      targets, it just copies them as raw resources. SwiftUI's
#      `Image(name:bundle:)` cannot read a raw .xcassets folder, so any
#      package that ships icons via an asset catalog (currently
#      `lcandy2/LucideIcon`) renders as an empty view until we compile
#      the catalog ourselves.
#
#      We compile in `.build/.../debug/<Pkg>_<Target>.bundle/` directly,
#      because that is the path the synthesized `Bundle.module` accessor
#      already falls back to when the .app's bundleURL lookup misses
#      (which it does for macOS .app structure: SwiftPM looks for
#      `<App>.app/<bundle>`, not `<App>.app/Contents/Resources/<bundle>`).
#      Compiling in place therefore makes Lucide icons render at runtime
#      without putting non-conventional files inside the .app, which
#      would break codesign sealing of the bundle root.
SWIFTPM_BUILD="$PROJECT_DIR/.build/arm64-apple-macosx/debug"
if [[ ! -d "$SWIFTPM_BUILD" ]]; then
    SWIFTPM_BUILD="$PROJECT_DIR/.build/debug"
fi
shopt -s nullglob
for spm_bundle in "$SWIFTPM_BUILD"/*.bundle; do
    while IFS= read -r -d '' xcassets; do
        out_dir=$(dirname "$xcassets")
        # Skip if Assets.car is already present and newer than the
        # source xcassets (idempotent re-runs).
        if [[ -f "$out_dir/Assets.car" && "$out_dir/Assets.car" -nt "$xcassets" ]]; then
            continue
        fi
        xcrun actool --compile "$out_dir" "$xcassets" \
            --platform macosx \
            --minimum-deployment-target 14.0 \
            --output-format human-readable-text >/dev/null
    done < <(find "$spm_bundle" -type d -name "*.xcassets" -print0)
    # Synthesize a minimal Info.plist if the package didn't ship one.
    # Foundation `Bundle(path:)` returns a degraded bundle when there is
    # no Info.plist — `bundle.url(forResource:withExtension:)` works but
    # `Image(name:bundle:)`'s asset-catalog lookup silently fails. The
    # SPM resource bundle template only writes Info.plist when there are
    # localizations, so packages that ship just an .xcassets (like
    # `lcandy2/LucideIcon`) need this stub.
    if [[ ! -f "$spm_bundle/Info.plist" ]]; then
        cat > "$spm_bundle/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
</dict>
</plist>
PLIST
    fi
done
shopt -u nullglob

# 3.1) Embed the bridge daemon under Contents/Helpers/clawix-bridge.
#      SMAppService.agent expects the helper to live next to the .app
#      it ships with so the LaunchAgent plist's `ProgramArguments` can
#      use a path relative to the bundle. Even though SMAppService is
#      not yet wired up to register/unregister this from Settings, the
#      bundle layout is the production layout so future passes only
#      add the wiring, not move the binary.
#
# 3.2) Generate Contents/Library/LaunchAgents/clawix.bridge.plist
#      from a template here. The Label is the literal `clawix.bridge`,
#      public and shared with the standalone npm CLI so both surfaces
#      register the same agent slot. The defaults suite is also the
#      literal `clawix.bridge` so the pairing bearer is shared between
#      the GUI's PairingService and the daemon.
if [[ -n "$BRIDGED_BIN_BUILT" ]]; then
    mkdir -p "$BUNDLE/Contents/Helpers" "$BUNDLE/Contents/Library/LaunchAgents"
    cp "$BRIDGED_BIN_BUILT" "$BUNDLE/Contents/Helpers/clawix-bridge"
    chmod +x "$BUNDLE/Contents/Helpers/clawix-bridge"

    AGENT_LABEL="clawix.bridge"
    AGENT_PLIST="$BUNDLE/Contents/Library/LaunchAgents/${AGENT_LABEL}.plist"
    cat > "$AGENT_PLIST" << AGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>                       <string>${AGENT_LABEL}</string>
    <key>BundleProgram</key>               <string>Contents/Helpers/clawix-bridge</string>
    <key>RunAtLoad</key>                   <true/>
    <key>KeepAlive</key>                   <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAWIX_BRIDGE_PORT</key>     <string>24080</string>
        <key>CLAWIX_BRIDGE_DEFAULTS_SUITE</key> <string>clawix.bridge</string>
    </dict>
    <key>StandardOutPath</key>             <string>/tmp/clawix-bridge.out</string>
    <key>StandardErrorPath</key>           <string>/tmp/clawix-bridge.err</string>
</dict>
</plist>
AGENTPLIST
fi

# 3.25) Embed the Secrets-only XPC authorization service. The service issues
#      short HMAC assertions for sensitive Secrets HTTP requests after macOS
#      XPC connects a caller whose code signature identifier matches this app.
SECRETS_XPC_SERVICE_NAME="${BUNDLE_ID}.secrets-xpc"
SECRETS_XPC_BUNDLE="$BUNDLE/Contents/XPCServices/ClawixSecretsXPC.xpc"
mkdir -p "$SECRETS_XPC_BUNDLE/Contents/MacOS"
cp "$SECRETS_XPC_BIN_BUILT" "$SECRETS_XPC_BUNDLE/Contents/MacOS/ClawixSecretsXPC"
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

# 3.3) Generate the LaunchAgent plist for the local LLM runtime. Unlike
#      the bridge daemon, this binary does NOT ship inside the bundle —
#      it's downloaded lazily into Application Support. So we cannot use
#      `BundleProgram` with a relative path; instead a /bin/sh -c
#      wrapper resolves $HOME at launch time. The wrapper exits 0 if the
#      binary isn't present (so KeepAlive doesn't infinite-loop on a
#      runtime that hasn't been installed yet).
mkdir -p "$BUNDLE/Contents/Library/LaunchAgents"
LM_AGENT_LABEL="${BUNDLE_ID}.local-models"
LM_AGENT_PLIST="$BUNDLE/Contents/Library/LaunchAgents/${LM_AGENT_LABEL}.plist"
cat > "$LM_AGENT_PLIST" << LMAGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>                       <string>${LM_AGENT_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>RUNTIME="\$HOME/Library/Application Support/Clawix/local-models/runtime"; [ -x "\$RUNTIME/ollama" ] || exit 0; mkdir -p "\$HOME/Library/Logs/Clawix" "\$HOME/Library/Application Support/Clawix/local-models/models" "\$HOME/Library/Application Support/Clawix/local-models/home"; exec env DYLD_LIBRARY_PATH="\$RUNTIME" OLLAMA_HOST=127.0.0.1:11435 OLLAMA_MODELS="\$HOME/Library/Application Support/Clawix/local-models/models" OLLAMA_KEEP_ALIVE=5m HOME="\$HOME/Library/Application Support/Clawix/local-models/home" "\$RUNTIME/ollama" serve</string>
    </array>
    <key>RunAtLoad</key>                   <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>          <false/>
    </dict>
    <key>StandardOutPath</key>             <string>/tmp/clawix-local-models.out</string>
    <key>StandardErrorPath</key>           <string>/tmp/clawix-local-models.err</string>
</dict>
</plist>
LMAGENTPLIST

#      Exclude `.build/index-build/...` — that tree is produced by
#      SourceKit's background indexer and lags behind real builds, so
#      newly-added resources (fonts, images) can be missing for an
#      entire dev cycle if we copy from there.
RESOURCE_BUNDLE="$(find "$PROJECT_DIR/.build" -path "*/index-build/*" -prune -o -path "*/debug/${APP_NAME}_${APP_NAME}.bundle" -type d -print 2>/dev/null | head -n 1 || true)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$BUNDLE/Contents/Resources/"
    while IFS= read -r lproj; do
        cp -R "$lproj" "$BUNDLE/Contents/Resources/"
    done < <(find "$RESOURCE_BUNDLE" -maxdepth 1 -name "*.lproj" -type d | sort)
else
    echo "ERROR: resource bundle not found for debug build"
    exit 1
fi
# Sparkle: SUFeedURL is the only required key for update checks. The
# public EdDSA key (SUPublicEDKey) gates whether downloaded updates are
# accepted. It comes from `.signing.env`; if empty, Sparkle will check
# but refuse to install (development scenario, expected).
SU_FEED_URL_DEFAULT="https://github.com/clawic/clawix/releases/latest/download/appcast.xml"
SU_FEED_URL="${SU_FEED_URL:-$SU_FEED_URL_DEFAULT}"
SU_PUBLIC_ED_KEY="${SPARKLE_ED_PUB_KEY:-}"
SU_ED_KEY_BLOCK=""
if [[ -n "$SU_PUBLIC_ED_KEY" ]]; then
    SU_ED_KEY_BLOCK=$'\n    <key>SUPublicEDKey</key>            <string>'"$SU_PUBLIC_ED_KEY"$'</string>'
fi

cat > "$BUNDLE/Contents/Info.plist" << PLIST
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
            <key>CFBundleURLName</key>    <string>${BUNDLE_ID}.clawix</string>
            <key>CFBundleURLSchemes</key> <array><string>clawix</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
printf "APPL????" > "$BUNDLE/Contents/PkgInfo"

# Sparkle.framework lives next to the binary so Sparkle's XPC services
# and Autoupdate launcher are reachable. SPM ships it as a binary target
# (XCFramework); pick the macos slice and copy the framework as-is.
SPARKLE_FW="$(find "$PROJECT_DIR/.build" -path "*/Sparkle.xcframework/macos-*/Sparkle.framework" -type d -prune 2>/dev/null | head -n 1 || true)"
if [[ -n "$SPARKLE_FW" ]]; then
    mkdir -p "$BUNDLE/Contents/Frameworks"
    rm -rf "$BUNDLE/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_FW" "$BUNDLE/Contents/Frameworks/Sparkle.framework"
else
    echo "WARN: Sparkle.framework not found in .build; auto-update will be inert" >&2
fi

# 3.4) Bundle the pinned @clawjs/cli release plus a Node runtime under
#      Contents/Resources/clawjs/. ClawJSRuntime.swift expects this layout
#      at runtime. The script is idempotent (skips when CLAWJS_VERSION
#      already matches the installed tree) and signs every nested .node
#      with SIGN_IDENTITY so native modules can load.
if [[ "${CLAWIX_DEV_BUNDLE_CLAWJS:-1}" == "1" ]]; then
    echo "==> Bundling ClawJS runtime"
    if [[ -z "${CLAWJS_DEV_OVERLAY:-}" ]]; then
        for overlay_candidate in \
            "$PROJECT_DIR/../../../clawjs" \
            "$PROJECT_DIR/../../clawjs"
        do
            if [[ -d "$overlay_candidate/packages/clawjs/bin" ]]; then
                CLAWJS_DEV_OVERLAY="$overlay_candidate"
                export CLAWJS_DEV_OVERLAY
                break
            fi
        done
    fi
    CLAWJS_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CLAWJS_SIGN_OPTS="--timestamp=none" \
        bash "$SCRIPT_DIR/bundle_clawjs.sh" "$BUNDLE"
else
    echo "==> Skipping ClawJS bundling (set CLAWIX_DEV_BUNDLE_CLAWJS=1 to enable)"
    rm -rf "$BUNDLE/Contents/Resources/clawjs"
fi

# 4) Sign the bundle with the stable identity. TCC ties permissions to
#    Team ID + bundle ID + designated requirement, so as long as the
#    signature stays consistent between rebuilds, grants like Desktop
#    folder access are remembered. If the cert is unavailable, fall back
#    to ad-hoc rather than blocking the dev loop, but warn.
echo "==> Signing $BUNDLE"
# Sign nested signed components first (without --identifier so each
# keeps its own bundle id from its Info.plist), then sign the app
# itself with --identifier "$BUNDLE_ID". Using --deep with --identifier
# corrupts nested code signatures: it overwrites the identifier of
# Sparkle.framework with the app's bundle id, which breaks dyld
# library validation at launch.
sign_one() {
    local target="$1"
    local err
    if ! err="$(codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$target" 2>&1)"; then
        if [[ "$REQUIRE_STABLE_SIGNING" == "1" ]]; then
            echo "ERROR: codesign with SIGN_IDENTITY failed for $target:" >&2
            echo "$err" >&2
            exit 1
        fi
        echo "WARN: codesign with $SIGN_IDENTITY failed for $target, falling back to ad-hoc: $err" >&2
        codesign --force --sign - --timestamp=none "$target"
    fi
}

# Sign the bridge daemon helper. SMAppService refuses to register a
# LaunchAgent helper whose codesign team id doesn't match the
# enclosing .app, so we sign with the same identity used for the GUI.
# The helper carries the public identifier `clawix.bridge` (matching
# the LaunchAgent Label) so launchd / SMAppService can address it
# independently of the GUI's bundle id.
HELPER_BIN="$BUNDLE/Contents/Helpers/clawix-bridge"
if [[ -f "$HELPER_BIN" ]]; then
    if ! codesign --force --sign "$SIGN_IDENTITY" \
                  --identifier "clawix.bridge" \
                  --timestamp=none \
                  "$HELPER_BIN" 2>/tmp/clawix-bridge-sign.err; then
        if [[ "$REQUIRE_STABLE_SIGNING" == "1" ]]; then
            echo "ERROR: codesign for clawix-bridge failed:" >&2
            cat /tmp/clawix-bridge-sign.err >&2
            exit 1
        fi
        echo "WARN: codesign for clawix-bridge with $SIGN_IDENTITY failed, falling back to ad-hoc:" >&2
        cat /tmp/clawix-bridge-sign.err >&2
        codesign --force --sign - --identifier "clawix.bridge" "$HELPER_BIN"
    fi
fi

if [[ -d "$BUNDLE/Contents/XPCServices" ]]; then
    while IFS= read -r xpc; do
        sign_one "$xpc"
    done < <(find "$BUNDLE/Contents/XPCServices" -maxdepth 1 -name "*.xpc" 2>/dev/null || true)
fi

SPARKLE_BUNDLE="$BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_BUNDLE" ]]; then
    SPARKLE_CURRENT="$SPARKLE_BUNDLE/Versions/Current"
    while IFS= read -r xpc; do
        sign_one "$xpc"
    done < <(find "$SPARKLE_CURRENT/XPCServices" -maxdepth 1 -name "*.xpc" 2>/dev/null || true)
    [[ -e "$SPARKLE_CURRENT/Autoupdate" ]] && sign_one "$SPARKLE_CURRENT/Autoupdate"
    if [[ -e "$SPARKLE_CURRENT/Updater.app" ]]; then
        sign_one "$SPARKLE_CURRENT/Updater.app"
    fi
    sign_one "$SPARKLE_BUNDLE"
fi

if ! codesign --force --sign "$SIGN_IDENTITY" \
              --identifier "$BUNDLE_ID" \
              --timestamp=none \
              "$BUNDLE" 2>/tmp/clawix-codesign.err; then
    if [[ "$REQUIRE_STABLE_SIGNING" == "1" ]]; then
        echo "ERROR: codesign for $BUNDLE failed:" >&2
        cat /tmp/clawix-codesign.err >&2
        exit 1
    fi
    echo "WARN: codesign with $SIGN_IDENTITY failed, falling back to ad-hoc:" >&2
    cat /tmp/clawix-codesign.err >&2
    codesign --force --sign - --identifier "$BUNDLE_ID" "$BUNDLE"
fi

LAUNCH_BUNDLE="$BUNDLE"
if [[ -n "$INSTALL_BUNDLE" ]]; then
    echo "==> Verifying staged signature before install"
    if ! codesign --verify --strict "$BUNDLE" >/dev/null 2>&1; then
        echo "ERROR: staged bundle signature verification failed: $BUNDLE" >&2
        exit 1
    fi
    if codesign -dv "$BUNDLE" 2>&1 | grep -q 'Signature=adhoc'; then
        echo "ERROR: staged bundle is ad-hoc signed; refusing install." >&2
        exit 1
    fi

    echo "==> Installing $INSTALL_BUNDLE"
    INSTALL_PARENT="$(dirname "$INSTALL_BUNDLE")"
    INSTALL_TMP="$INSTALL_PARENT/.${APP_NAME}.app.installing.$$"
    rm -rf "$INSTALL_TMP"
    if ! /usr/bin/ditto "$BUNDLE" "$INSTALL_TMP"; then
        echo "ERROR: failed to stage install at $INSTALL_TMP" >&2
        rm -rf "$INSTALL_TMP"
        exit 1
    fi
    rm -rf "$INSTALL_BUNDLE"
    if ! mv "$INSTALL_TMP" "$INSTALL_BUNDLE"; then
        echo "ERROR: failed to install $INSTALL_BUNDLE. Check write permissions for $INSTALL_PARENT." >&2
        rm -rf "$INSTALL_TMP"
        exit 1
    fi
    LAUNCH_BUNDLE="$INSTALL_BUNDLE"
    echo "==> Installed canonical app: $LAUNCH_BUNDLE"
fi

# 4.5) Optional: assemble and install one .app bundle per sidebar tool.
#      Each mini-app reuses the SAME compiled binary as Clawix.app but
#      ships in its own .app with a distinct bundle id and name. The
#      binary detects the role at launch via the CLXAppRole Info.plist
#      key (read by ClawixToolRole.fromBundle) and renders only that
#      tool's view. The full set can be skipped via
#      CLAWIX_DEV_SKIP_TOOLS=1 (legacy CLAWIX_DEV_SKIP_TASKS also
#      accepted); a comma-separated subset can be selected via
#      CLAWIX_DEV_TOOLS_ONLY="tasks,notes". Bundle ids default to
#      ${BUNDLE_ID}.tools.<slug>; a per-tool override
#      BUNDLE_ID_<UPPER_SLUG> takes precedence so the existing Tasks.app
#      codesign / TCC state stays stable across the migration.

assemble_tool_app() {
    local slug="$1"      # "tasks", "goals", ...
    local display="$2"   # "Tasks", "Goals", ...
    local bid="$3"       # bundle id (override or derived)
    local role="$4"      # CLXAppRole literal ("tasks" or "tool:<slug>")
    local upper staging staging_var staging_default bin icon_src sparkle_src
    upper="$(echo "$slug" | tr '[:lower:]' '[:upper:]')"
    staging_default="$DEV_DIR/${display}.app"
    staging_var="CLAWIX_DEV_${upper}_STAGING_BUNDLE"
    staging="${!staging_var:-$staging_default}"
    bin="$staging/Contents/MacOS/${display}"
    icon_src="$PROJECT_DIR/Resources/AppIcons/${display}.icns"

    echo "==> Assembling $staging"
    rm -rf "$staging"
    mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
    cp "$PROJECT_DIR/.build/debug/${APP_NAME}" "$bin"
    chmod +x "$bin"
    if [[ -f "$icon_src" ]]; then
        cp "$icon_src" "$staging/Contents/Resources/${display}.icns"
    fi

    # Sparkle.framework is dynamically linked by the shared binary
    # (rpath @executable_path/../Frameworks, set in Package.swift); the
    # mini-app inherits that link, so without the framework dyld halts
    # the process at launch with "Library not loaded". Copy the
    # already-signed framework from the Clawix.app staging dir and let
    # the outer codesign below seal it without --deep.
    sparkle_src="$BUNDLE/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$sparkle_src" ]]; then
        mkdir -p "$staging/Contents/Frameworks"
        cp -R "$sparkle_src" "$staging/Contents/Frameworks/Sparkle.framework"
    else
        echo "WARN: Sparkle.framework not found at $sparkle_src; ${display}.app will fail at launch" >&2
    fi

    cat > "$staging/Contents/Info.plist" << TOOLPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>${display}</string>
    <key>CFBundleIdentifier</key>        <string>${bid}</string>
    <key>CFBundleName</key>              <string>${display}</string>
    <key>CFBundleDisplayName</key>       <string>${display}</string>
    <key>CFBundleIconFile</key>          <string>${display}</string>
    <key>CFBundleVersion</key>           <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>CLXAppRole</key>                <string>${role}</string>
</dict>
</plist>
TOOLPLIST
    printf "APPL????" > "$staging/Contents/PkgInfo"

    echo "==> Signing $staging"
    if ! codesign --force --sign "$SIGN_IDENTITY" \
                  --identifier "$bid" \
                  --timestamp=none \
                  "$staging" 2>"/tmp/clawix-${slug}-codesign.err"; then
        if [[ "$REQUIRE_STABLE_SIGNING" == "1" ]]; then
            echo "ERROR: codesign for $staging failed:" >&2
            cat "/tmp/clawix-${slug}-codesign.err" >&2
            exit 1
        fi
        echo "WARN: codesign with $SIGN_IDENTITY failed for ${display}.app, falling back to ad-hoc:" >&2
        cat "/tmp/clawix-${slug}-codesign.err" >&2
        codesign --force --sign - --identifier "$bid" "$staging"
    fi

    if [[ -n "${INSTALL_BUNDLE:-}" ]]; then
        local install_target install_tmp
        install_target="$(dirname "$INSTALL_BUNDLE")/${display}.app"
        echo "==> Installing $install_target"
        install_tmp="$(dirname "$install_target")/.${display}.app.installing.$$"
        rm -rf "$install_tmp"
        if ! /usr/bin/ditto "$staging" "$install_tmp"; then
            echo "ERROR: failed to stage ${display} install at $install_tmp" >&2
            rm -rf "$install_tmp"
            exit 1
        fi
        rm -rf "$install_target"
        if ! mv "$install_tmp" "$install_target"; then
            echo "ERROR: failed to install $install_target. Check write permissions for $(dirname "$install_target")." >&2
            rm -rf "$install_tmp"
            exit 1
        fi
        echo "==> Installed ${display} mini-app: $install_target"
    else
        echo "==> ${display} staging only at $staging (no INSTALL_BUNDLE set)"
    fi
}

# Mirrors SidebarToolsCatalog.entries in macos/Sources/Clawix/SidebarView.swift.
# Format: "slug:Display".
TOOLS_CATALOG=(
    "tasks:Tasks"
    "goals:Goals"
    "notes:Notes"
    "projects:Projects"
    "secrets:Secrets"
    "memory:Memory"
    "database:Database"
    "photos:Photos"
    "documents:Documents"
    "recent:Recent"
    "drive:Drive"
)

if [[ "${CLAWIX_DEV_SKIP_TOOLS:-${CLAWIX_DEV_SKIP_TASKS:-0}}" != "1" ]]; then
    declare -a TOOLS_ONLY=()
    if [[ -n "${CLAWIX_DEV_TOOLS_ONLY:-}" ]]; then
        IFS=',' read -ra TOOLS_ONLY <<< "${CLAWIX_DEV_TOOLS_ONLY}"
    fi

    for entry in "${TOOLS_CATALOG[@]}"; do
        slug="${entry%%:*}"
        display="${entry##*:}"

        if [[ ${#TOOLS_ONLY[@]} -gt 0 ]]; then
            found=0
            for s in "${TOOLS_ONLY[@]}"; do
                [[ "$s" == "$slug" ]] && { found=1; break; }
            done
            [[ $found -eq 1 ]] || continue
        fi

        upper="$(echo "$slug" | tr '[:lower:]' '[:upper:]')"
        override_var="BUNDLE_ID_${upper}"
        bid="${!override_var:-${BUNDLE_ID}.tools.${slug}}"
        [[ -n "$bid" ]] || continue

        # Tasks keeps the unprefixed legacy role literal so a freshly
        # rebuilt Tasks.app stays drop-in compatible with installs from
        # before the tool registry refactor. All other slugs use the
        # tool:<slug> form, which ClawixToolRole.fromBundle parses too.
        if [[ "$slug" == "tasks" ]]; then
            role_value="tasks"
        else
            role_value="tool:$slug"
        fi

        assemble_tool_app "$slug" "$display" "$bid" "$role_value"
    done
fi

# 5) Launch the app bundle. Window position is restored from the autosave
#    name, so the user sees the same window in the same place.
#
#    `CLAWIX_DEV_NOLAUNCH=1` skips the launch and exits after a successful
#    build. Used by `perf-capture.sh` so xctrace can be the one launching
#    the binary (and seeing its launch timeline). Bundle path is printed
#    so the caller can find it.
if [[ "${CLAWIX_DEV_NOLAUNCH:-0}" == "1" ]]; then
    echo "==> Build complete, launch skipped (CLAWIX_DEV_NOLAUNCH=1)"
    echo "Bundle: $LAUNCH_BUNDLE"
    exit 0
fi
echo "==> Launching ${APP_NAME}"
/usr/bin/open -n "$LAUNCH_BUNDLE"

APP_PID=""
EXPECTED_EXE="${CLAWIX_DEV_EXPECT_EXECUTABLE:-$LAUNCH_BUNDLE/Contents/MacOS/$APP_NAME}"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    APP_PID="$(
        while IFS= read -r pid; do
            [[ -n "$pid" ]] || continue
            command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
            if [[ "$command" == "$EXPECTED_EXE" || "$command" == "$EXPECTED_EXE "* ]]; then
                echo "$pid"
                break
            fi
        done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
    )"
    [[ -n "$APP_PID" ]] && break
done

if [[ -z "$APP_PID" ]] || ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "ERROR: ${APP_NAME} exited immediately. Last 30 log lines:"
    tail -30 "$LOG_FILE"
    exit 1
fi

echo "$APP_PID" > "$PID_FILE"

echo ""
echo "${APP_NAME} running (PID $APP_PID). Logs: $LOG_FILE"
echo "Edit any .swift file under Sources/Clawix and re-run this script to apply."
