#!/usr/bin/env bash
# Run from a macOS host with Swift toolchain installed. Walks the Swift
# wire fixtures and copies them into Clawix.Tests/Fixtures/ so the C#
# round-trip tests have something to compare against.
#
# Usage:
#   bash clawix/windows/scripts/dump-fixtures.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="$(cd "$ROOT/../packages" && pwd)"
FIXTURES_OUT="$ROOT/Clawix.Tests/Fixtures"

mkdir -p "$FIXTURES_OUT"

if ! command -v swift >/dev/null 2>&1; then
    echo "swift CLI not found; install Xcode CLT first." >&2
    exit 2
fi

# Build and run the fixture synthesizer (lives in ClawixEngine).
pushd "$PACKAGES_DIR/ClawixEngine" >/dev/null
swift build --product FixtureFileSynthesizer 2>/dev/null || true
swift run FixtureFileSynthesizer "$FIXTURES_OUT" || {
    echo "FixtureFileSynthesizer not yet wired in Swift; manual export pending." >&2
    exit 0
}
popd >/dev/null

echo "Fixtures landed in $FIXTURES_OUT"
ls "$FIXTURES_OUT" | head -20
