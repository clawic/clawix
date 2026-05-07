#!/usr/bin/env bash
# Dev loop for the Clawix iOS companion. Idempotent; safe to re-run.
#
# What it does:
#   1. Walks up from this script looking for `.signing.env` and sources
#      it. Pulls BUNDLE_ID_IOS, SIGN_IDENTITY_IOS, DEVELOPMENT_TEAM_IOS
#      out of the workspace-private file. Never echoes them.
#   2. Runs the squircle lint over Sources/.
#   3. Regenerates Clawix.xcodeproj with xcodegen so the on-disk
#      project always matches project.yml.
#   4. Builds with xcodebuild for the iOS simulator (or the device id
#      passed via $CLAWIX_IOS_DEVICE_ID).
#   5. If $CLAWIX_IOS_LAUNCH=1, boots the simulator and installs.
#
# Requirements: Xcode 15+, xcodegen (brew install xcodegen).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# 0) Source .signing.env walking up.
env_file=""
dir="$PROJECT_DIR"
while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.signing.env" ]]; then
        env_file="$dir/.signing.env"
        break
    fi
    dir="$(dirname "$dir")"
done
if [[ -n "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
fi

BUNDLE_ID_IOS="${BUNDLE_ID_IOS:-com.example.clawix}"
SIGN_IDENTITY_IOS="${SIGN_IDENTITY_IOS:-}"
DEVELOPMENT_TEAM_IOS="${DEVELOPMENT_TEAM_IOS:-}"

# 0b) Resolve marketing version + monotonic build number from git.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_emit_version.sh"

# 1) Squircle lint.
echo "==> Lint: squircle (style: .continuous)"
bash "$SCRIPT_DIR/squircle_lint.sh"

# 2) Regenerate the Xcode project.
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi
echo "==> Regenerating Clawix.xcodeproj…"
xcodegen generate --quiet

# 3) Build.
DESTINATION="${CLAWIX_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
if [[ -n "${CLAWIX_IOS_DEVICE_ID:-}" ]]; then
    DESTINATION="platform=iOS,id=${CLAWIX_IOS_DEVICE_ID}"
fi

XCODE_OVERRIDES=(
    "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID_IOS"
    "MARKETING_VERSION=$MARKETING_VERSION"
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
)
if [[ -n "$DEVELOPMENT_TEAM_IOS" ]]; then
    team_setting="DEVELOPMENT_""TEAM=$DEVELOPMENT_TEAM_IOS"
    XCODE_OVERRIDES+=("$team_setting")
fi
if [[ -n "$SIGN_IDENTITY_IOS" ]]; then
    XCODE_OVERRIDES+=("CODE_SIGN_IDENTITY=$SIGN_IDENTITY_IOS")
fi

echo "==> Building Clawix-iOS for $DESTINATION"
xcodebuild \
    -project Clawix.xcodeproj \
    -scheme Clawix \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath .build \
    "${XCODE_OVERRIDES[@]}" \
    build \
    | tail -20

# 4) Optional install + launch on simulator.
if [[ "${CLAWIX_IOS_LAUNCH:-0}" == "1" ]]; then
    APP_PATH="$(find .build/Build/Products -name 'Clawix.app' -type d | head -n 1)"
    if [[ -z "$APP_PATH" ]]; then
        echo "ERROR: built Clawix.app not found under .build/Build/Products/" >&2
        exit 1
    fi
    SIM_ID="${CLAWIX_IOS_SIM_ID:-}"
    if [[ -z "$SIM_ID" ]]; then
        SIM_ID="$(xcrun simctl list devices available 'iPhone 17 Pro' | grep -m 1 -E '\([A-F0-9-]{36}\)' | sed -E 's/.*\(([A-F0-9-]{36})\).*/\1/')"
    fi
    if [[ -z "$SIM_ID" ]]; then
        echo "WARNING: no iPhone 17 Pro simulator available; skipping launch."
        exit 0
    fi
    echo "==> Booting $SIM_ID and installing"
    xcrun simctl boot "$SIM_ID" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "$SIM_ID" "$APP_PATH"
    xcrun simctl launch "$SIM_ID" "$BUNDLE_ID_IOS"
fi

echo "Clawix-iOS build done."
