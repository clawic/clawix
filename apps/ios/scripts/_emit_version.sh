#!/usr/bin/env bash
# Resolves the marketing version (from apps/ios/VERSION) and a monotonic
# build number (from git history) and exports them so the calling script
# can interpolate them into the generated Info.plist.
#
# Usage: source this file from dev.sh / build_release_app.sh. It does not
# run anything destructive; it only sets variables.
#
# Exposes:
#   MARKETING_VERSION  → CFBundleShortVersionString (e.g. "0.1.0")
#   BUILD_NUMBER       → CFBundleVersion (e.g. "47")
#
# Build number comes from `git rev-list --count HEAD` over the whole
# monorepo, which means iOS and macOS share the same monotonic series.
# Any commit increments both, so a build number is always strictly
# greater than every build number that came before it on the same
# branch, regardless of which target last released.
set -euo pipefail

EMIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT_PROJECT_DIR="$(dirname "$EMIT_DIR")"
EMIT_VERSION_FILE="$EMIT_PROJECT_DIR/VERSION"

if [[ ! -f "$EMIT_VERSION_FILE" ]]; then
    echo "ERROR: $EMIT_VERSION_FILE missing" >&2
    return 1 2>/dev/null || exit 1
fi

MARKETING_VERSION="$(tr -d '[:space:]' < "$EMIT_VERSION_FILE")"
if [[ -z "$MARKETING_VERSION" ]]; then
    echo "ERROR: $EMIT_VERSION_FILE is empty" >&2
    return 1 2>/dev/null || exit 1
fi

if BUILD_NUMBER="$(git -C "$EMIT_PROJECT_DIR" rev-list --count HEAD 2>/dev/null)"; then
    :
else
    BUILD_NUMBER="0"
fi

export MARKETING_VERSION BUILD_NUMBER
