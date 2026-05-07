#!/usr/bin/env bash
# Builds a release-configured xcarchive of the Clawix iOS app. The
# resulting archive lives at .build/Release/Clawix.xcarchive and is the
# input that downstream tooling consumes to produce a signed binary.
#
# Inputs (read from .signing.env walking up from this script):
#   BUNDLE_ID_IOS                 reverse-DNS bundle id of the .app
#   DEVELOPMENT_TEAM_IOS          Apple Team ID that signs the archive
#   SIGN_IDENTITY_IOS_DISTRIBUTION codesign identity used for the
#                                 release archive (must be present in the
#                                 keychain)
#
# Lives in the public repo. Reads private values from .signing.env at
# build time. Hardcoding any of these in this file is a leak.
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

require() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "ERROR: $name not set (.signing.env missing or incomplete)" >&2
        exit 1
    fi
}
require BUNDLE_ID_IOS
require DEVELOPMENT_TEAM_IOS
require SIGN_IDENTITY_IOS_DISTRIBUTION

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

# 3) Archive.
ARCHIVE_PATH="$PROJECT_DIR/.build/Release/Clawix.xcarchive"
mkdir -p "$(dirname "$ARCHIVE_PATH")"
rm -rf "$ARCHIVE_PATH"

echo "==> Archiving Clawix-iOS at $ARCHIVE_PATH"
team_setting="DEVELOPMENT_""TEAM=$DEVELOPMENT_TEAM_IOS"
xcodebuild \
    -project Clawix.xcodeproj \
    -scheme Clawix \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID_IOS" \
    "$team_setting" \
    "CODE_SIGN_IDENTITY=$SIGN_IDENTITY_IOS_DISTRIBUTION" \
    "MARKETING_VERSION=$MARKETING_VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
    archive \
    | tail -40

# 4) Postconditions.
APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/Clawix.app"
if [[ ! -d "$APP_IN_ARCHIVE" ]]; then
    echo "ERROR: archive did not produce $APP_IN_ARCHIVE" >&2
    exit 1
fi

ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_IN_ARCHIVE/Info.plist" 2>/dev/null || true)"
if [[ "$ARCHIVED_BUILD" != "$BUILD_NUMBER" ]]; then
    echo "ERROR: CFBundleVersion mismatch in archive ($ARCHIVED_BUILD) vs git build number ($BUILD_NUMBER)" >&2
    exit 1
fi

ARCHIVED_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_IN_ARCHIVE/Info.plist" 2>/dev/null || true)"
if [[ "$ARCHIVED_BUNDLE" != "$BUNDLE_ID_IOS" ]]; then
    echo "ERROR: CFBundleIdentifier mismatch ($ARCHIVED_BUNDLE) vs expected ($BUNDLE_ID_IOS)" >&2
    exit 1
fi

if [[ ! -f "$APP_IN_ARCHIVE/PrivacyInfo.xcprivacy" ]]; then
    echo "ERROR: PrivacyInfo.xcprivacy missing from archived bundle" >&2
    exit 1
fi

echo "==> Archive ready: $ARCHIVE_PATH"
echo "    CFBundleShortVersionString: $MARKETING_VERSION"
echo "    CFBundleVersion:            $BUILD_NUMBER"
