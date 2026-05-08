#!/usr/bin/env bash
# Dev launcher for Clawix.
#
# Builds, kills the previous Clawix process if any, and relaunches.
# The window position is preserved by NSWindow.setFrameAutosaveName("ClawixMainWindow"),
# so each rebuild reopens the window EXACTLY where the user left it.
#
# This is the ONE command an agent should run after edits, idempotent and safe.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Clawix"
# Bundle ID is overridable via env (typically through .signing.env). The
# default below is a clearly-placeholder value: anyone who wants to ship
# their own build should provide their own reverse-DNS bundle ID via
# BUNDLE_ID. The maintainer's real bundle ID is NOT stored in this repo.
BUNDLE_ID_DEFAULT="com.example.clawix.desktop"
# The dev bundle and runtime state live OUTSIDE ~/Desktop. If the .app
# sits inside ~/Desktop, macOS prompts for Desktop folder access every
# launch. Putting it under ~/Library/Caches avoids that trigger.
DEV_DIR="$HOME/Library/Caches/Clawix-Dev"
BUNDLE="$DEV_DIR/${APP_NAME}.app"
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

if [[ ! -f "$PROJECT_DIR/.build/debug/${APP_NAME}" ]]; then
    echo "ERROR: binary not produced at .build/debug/${APP_NAME}"
    exit 1
fi

# 1.5) Build the bridge daemon (clawix-bridged). Lives in a sibling SPM
#      package under Helpers/Bridged/. The daemon shares ClawixEngine
#      with the GUI but is its own executable target so it can be
#      registered as a LaunchAgent later (SMAppService.agent), keeping
#      the iPhone bridge alive across Cmd+Q / GUI crashes.
#
#      The dev build embeds the daemon binary at
#      Contents/Helpers/clawix-bridged so the eventual SMAppService
#      registration finds it at the conventional path. The daemon is
#      NOT auto-registered or auto-started here — that requires a
#      Settings UI toggle which lands in a later phase.
BRIDGED_PKG="$PROJECT_DIR/Helpers/Bridged"
BRIDGED_BIN_BUILT=""
if [[ -f "$BRIDGED_PKG/Package.swift" ]]; then
    echo "==> Building clawix-bridged daemon…"
    (cd "$BRIDGED_PKG" && swift build 2>&1)
    BRIDGED_BIN_BUILT="$BRIDGED_PKG/.build/debug/clawix-bridged"
    if [[ ! -f "$BRIDGED_BIN_BUILT" ]]; then
        echo "WARN: clawix-bridged binary not produced; bundle will ship without daemon" >&2
        BRIDGED_BIN_BUILT=""
    fi
fi

# 1.6) Build the secrets-vault proxy helper (clawix-secrets-proxy). Lives
#      under Helpers/SecretsProxy/, shares SecretsProxyCore with the GUI,
#      and is what Codex / Claude Code / scripts call to use vault
#      secrets without ever seeing the literal value. The helper connects
#      to the running app over a unix-domain socket inside
#      ~/Library/Application Support/Clawix/secrets/proxy.sock.
SECRETS_PROXY_PKG="$PROJECT_DIR/Helpers/SecretsProxy"
SECRETS_PROXY_BIN_BUILT=""
if [[ -f "$SECRETS_PROXY_PKG/Package.swift" ]]; then
    echo "==> Building clawix-secrets-proxy helper…"
    (cd "$SECRETS_PROXY_PKG" && swift build 2>&1)
    SECRETS_PROXY_BIN_BUILT="$SECRETS_PROXY_PKG/.build/debug/clawix-secrets-proxy"
    if [[ ! -f "$SECRETS_PROXY_BIN_BUILT" ]]; then
        echo "WARN: clawix-secrets-proxy binary not produced; bundle will ship without it" >&2
        SECRETS_PROXY_BIN_BUILT=""
    fi
fi

# 2) Kill any previous instance, however launched.
#    The frame is persisted on every move/resize, so killing is safe.
PIDS=$({
    pgrep -f "${DEV_DIR}/.*/${APP_NAME}" 2>/dev/null || true
    pgrep -f "${PROJECT_DIR}/build/.*/${APP_NAME}" 2>/dev/null || true
    pgrep -x "$APP_NAME" 2>/dev/null || true
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
        } | sort -u)
        [[ -z "$REMAIN" ]] && break
    done
    REMAIN=$({
        pgrep -f "${DEV_DIR}/.*/${APP_NAME}" 2>/dev/null || true
        pgrep -f "${PROJECT_DIR}/build/.*/${APP_NAME}" 2>/dev/null || true
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

# 3.1) Embed the bridge daemon under Contents/Helpers/clawix-bridged.
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
if [[ -n "$SECRETS_PROXY_BIN_BUILT" ]]; then
    mkdir -p "$BUNDLE/Contents/Helpers"
    cp "$SECRETS_PROXY_BIN_BUILT" "$BUNDLE/Contents/Helpers/clawix-secrets-proxy"
    chmod +x "$BUNDLE/Contents/Helpers/clawix-secrets-proxy"
fi

if [[ -n "$BRIDGED_BIN_BUILT" ]]; then
    mkdir -p "$BUNDLE/Contents/Helpers" "$BUNDLE/Contents/Library/LaunchAgents"
    cp "$BRIDGED_BIN_BUILT" "$BUNDLE/Contents/Helpers/clawix-bridged"
    chmod +x "$BUNDLE/Contents/Helpers/clawix-bridged"

    AGENT_LABEL="clawix.bridge"
    AGENT_PLIST="$BUNDLE/Contents/Library/LaunchAgents/${AGENT_LABEL}.plist"
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
    <key>SUFeedURL</key>                 <string>${SU_FEED_URL}</string>${SU_ED_KEY_BLOCK}
    <key>SUEnableAutomaticChecks</key>   <true/>
    <key>SUScheduledCheckInterval</key>  <integer>86400</integer>
    <key>SUEnableInstallerLauncherService</key><true/>
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
HELPER_BIN="$BUNDLE/Contents/Helpers/clawix-bridged"
if [[ -f "$HELPER_BIN" ]]; then
    if ! codesign --force --sign "$SIGN_IDENTITY" \
                  --identifier "clawix.bridge" \
                  --timestamp=none \
                  "$HELPER_BIN" 2>/tmp/clawix-bridged-sign.err; then
        echo "WARN: codesign for clawix-bridged with $SIGN_IDENTITY failed, falling back to ad-hoc:" >&2
        cat /tmp/clawix-bridged-sign.err >&2
        codesign --force --sign - --identifier "clawix.bridge" "$HELPER_BIN"
    fi
fi

SECRETS_PROXY_HELPER_BIN="$BUNDLE/Contents/Helpers/clawix-secrets-proxy"
if [[ -f "$SECRETS_PROXY_HELPER_BIN" ]]; then
    if ! codesign --force --sign "$SIGN_IDENTITY" \
                  --identifier "clawix.secrets-proxy" \
                  --timestamp=none \
                  "$SECRETS_PROXY_HELPER_BIN" 2>/tmp/clawix-secrets-proxy-sign.err; then
        echo "WARN: codesign for clawix-secrets-proxy with $SIGN_IDENTITY failed, falling back to ad-hoc:" >&2
        cat /tmp/clawix-secrets-proxy-sign.err >&2
        codesign --force --sign - --identifier "clawix.secrets-proxy" "$SECRETS_PROXY_HELPER_BIN"
    fi
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
    echo "WARN: codesign with $SIGN_IDENTITY failed, falling back to ad-hoc:" >&2
    cat /tmp/clawix-codesign.err >&2
    codesign --force --sign - --identifier "$BUNDLE_ID" "$BUNDLE"
fi

# 5) Launch the app bundle. Window position is restored from the autosave
#    name, so the user sees the same window in the same place.
echo "==> Launching ${APP_NAME}"
/usr/bin/open -n "$BUNDLE"

APP_PID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    APP_PID="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
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
