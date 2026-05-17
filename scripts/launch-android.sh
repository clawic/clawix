#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
GRADLE_VERSION="${CLAWIX_ANDROID_GRADLE_VERSION:-8.10.2}"

cd "$ANDROID_DIR"

GRADLE_CMD=()

if [ -x ./gradlew ]; then
  GRADLE_CMD=(./gradlew)
elif command -v gradle >/dev/null 2>&1; then
  GRADLE_CMD=(gradle)
else
  CACHED_GRADLE_ZIP="$(find "$HOME/.gradle/wrapper/dists" -path "*/gradle-${GRADLE_VERSION}-*.zip" -print -quit 2>/dev/null || true)"
  if [ -z "$CACHED_GRADLE_ZIP" ]; then
    CACHED_GRADLE_ZIP="$(find "$HOME/.gradle/wrapper/dists" -path "*/gradle-*-*.zip" -print | sort -r | head -n 1 || true)"
  fi
  if [ -z "$CACHED_GRADLE_ZIP" ]; then
    echo "Gradle wrapper is missing. Install Gradle or open android/ in Android Studio once, then rerun this script." >&2
    exit 69
  fi
  CACHED_GRADLE_VERSION="$(basename "$CACHED_GRADLE_ZIP" | sed -E 's/^gradle-([0-9.]+)-.*$/\1/')"
  CACHE_DIR="${TMPDIR:-/tmp}/clawix-gradle-${CACHED_GRADLE_VERSION}"
  GRADLE_BIN="$CACHE_DIR/gradle-${CACHED_GRADLE_VERSION}/bin/gradle"
  if [ ! -x "$GRADLE_BIN" ]; then
    rm -rf "$CACHE_DIR"
    mkdir -p "$CACHE_DIR"
    unzip -q "$CACHED_GRADLE_ZIP" -d "$CACHE_DIR"
  fi
  if [ ! -x "$GRADLE_BIN" ]; then
    echo "Cached Gradle distribution is unusable: $CACHED_GRADLE_ZIP" >&2
    exit 69
  fi
  GRADLE_CMD=("$GRADLE_BIN")
fi

case "${1:-assemble}" in
  assemble)
    exec "${GRADLE_CMD[@]}" :app:assembleDebug
    ;;
  install)
    exec "${GRADLE_CMD[@]}" :app:installDebug
    ;;
  test)
    exec "${GRADLE_CMD[@]}" :app:testDebugUnitTest
    ;;
  *)
    echo "usage: scripts/launch-android.sh [assemble|install|test]" >&2
    exit 64
    ;;
esac
