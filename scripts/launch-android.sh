#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
GRADLE_VERSION="${CLAWIX_ANDROID_GRADLE_VERSION:-8.10.2}"

cd "$ANDROID_DIR"

if [ ! -x ./gradlew ]; then
  if ! command -v gradle >/dev/null 2>&1; then
    echo "Gradle wrapper is missing. Install Gradle or open android/ in Android Studio once, then rerun this script." >&2
    exit 69
  fi
  gradle wrapper --gradle-version "$GRADLE_VERSION"
fi

case "${1:-assemble}" in
  assemble)
    exec ./gradlew :app:assembleDebug
    ;;
  install)
    exec ./gradlew :app:installDebug
    ;;
  test)
    exec ./gradlew :app:testDebugUnitTest
    ;;
  *)
    echo "usage: scripts/launch-android.sh [assemble|install|test]" >&2
    exit 64
    ;;
esac
