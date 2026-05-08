#!/usr/bin/env bash
# Resolves the marketing version (from apps/macos/VERSION) and a monotonic
# build number (from git history) and exports them so the calling script
# can interpolate them into the generated Info.plist.
#
# Usage: source this file from dev.sh / build_app.sh / build_release_app.sh.
# It does not run anything destructive; it only sets variables.
#
# Exposes:
#   MARKETING_VERSION  → CFBundleShortVersionString (e.g. "0.1.0")
#   BUILD_NUMBER       → CFBundleVersion (e.g. "47")
#   CLAWJS_VERSION     → ClawJSVersion (the @clawjs/cli release this Clawix
#                        build is pinned to, read from apps/macos/CLAWJS_VERSION).
set -euo pipefail

EMIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT_PROJECT_DIR="$(dirname "$EMIT_DIR")"
EMIT_VERSION_FILE="$EMIT_PROJECT_DIR/VERSION"
EMIT_CLAWJS_VERSION_FILE="$EMIT_PROJECT_DIR/CLAWJS_VERSION"

if [[ ! -f "$EMIT_VERSION_FILE" ]]; then
    echo "ERROR: $EMIT_VERSION_FILE missing" >&2
    return 1 2>/dev/null || exit 1
fi

MARKETING_VERSION="$(tr -d '[:space:]' < "$EMIT_VERSION_FILE")"
if [[ -z "$MARKETING_VERSION" ]]; then
    echo "ERROR: $EMIT_VERSION_FILE is empty" >&2
    return 1 2>/dev/null || exit 1
fi

# Build number = monotonic commit count. Stable across rebuilds at the
# same HEAD, increments on every new commit. Falls back to 0 when run
# outside a git checkout (e.g. tarball install).
if BUILD_NUMBER="$(git -C "$EMIT_PROJECT_DIR" rev-list --count HEAD 2>/dev/null)"; then
    :
else
    BUILD_NUMBER="0"
fi

# ClawJS pinning. Each Clawix build declares the exact @clawjs/cli release
# it was integrated against. The value is interpolated into Info.plist as
# `ClawJSVersion` and read at runtime by ClawJSRuntime.expectedVersion.
# Phase 1 of the integration uses this same value to install the bundled
# tree under Contents/Helpers/clawjs/ and refuses to ship a release whose
# bundled package.json version doesn't match.
if [[ ! -f "$EMIT_CLAWJS_VERSION_FILE" ]]; then
    echo "ERROR: $EMIT_CLAWJS_VERSION_FILE missing" >&2
    return 1 2>/dev/null || exit 1
fi

CLAWJS_VERSION="$(tr -d '[:space:]' < "$EMIT_CLAWJS_VERSION_FILE")"
if [[ -z "$CLAWJS_VERSION" ]]; then
    echo "ERROR: $EMIT_CLAWJS_VERSION_FILE is empty" >&2
    return 1 2>/dev/null || exit 1
fi

export MARKETING_VERSION BUILD_NUMBER CLAWJS_VERSION
