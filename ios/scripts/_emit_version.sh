#!/usr/bin/env bash
# Resolves the marketing version (from ios/VERSION) and the build
# number (from ios/BUILD_NUMBER) and exports them so the calling
# script can interpolate them into the generated Info.plist.
#
# Usage: source this file from dev.sh / build_release_app.sh. It does
# not run anything destructive; it only sets variables.
#
# Exposes:
#   MARKETING_VERSION  → CFBundleShortVersionString (e.g. "0.1.0")
#   BUILD_NUMBER       → CFBundleVersion (e.g. "1", "2", "3", ...)
#
# BUILD_NUMBER is a manually-managed monotonic counter, NOT git's
# `rev-list --count HEAD` like macOS uses. The release orchestrator
# (scripts-dev/ios-release.sh, lives outside the public repo) bumps
# BUILD_NUMBER by +1 on every upload and commits the new value. iOS
# starts at 1 and grows independently of the macOS build series so the
# numbers stay tidy in App Store Connect.
set -euo pipefail

EMIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT_PROJECT_DIR="$(dirname "$EMIT_DIR")"
EMIT_VERSION_FILE="$EMIT_PROJECT_DIR/VERSION"
EMIT_BUILD_NUMBER_FILE="$EMIT_PROJECT_DIR/BUILD_NUMBER"

if [[ ! -f "$EMIT_VERSION_FILE" ]]; then
    echo "ERROR: $EMIT_VERSION_FILE missing" >&2
    return 1 2>/dev/null || exit 1
fi

MARKETING_VERSION="$(tr -d '[:space:]' < "$EMIT_VERSION_FILE")"
if [[ -z "$MARKETING_VERSION" ]]; then
    echo "ERROR: $EMIT_VERSION_FILE is empty" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -f "$EMIT_BUILD_NUMBER_FILE" ]]; then
    echo "ERROR: $EMIT_BUILD_NUMBER_FILE missing" >&2
    return 1 2>/dev/null || exit 1
fi

BUILD_NUMBER="$(tr -d '[:space:]' < "$EMIT_BUILD_NUMBER_FILE")"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $EMIT_BUILD_NUMBER_FILE is not a non-negative integer: '$BUILD_NUMBER'" >&2
    return 1 2>/dev/null || exit 1
fi

export MARKETING_VERSION BUILD_NUMBER
