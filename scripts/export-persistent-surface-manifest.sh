#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/docs/persistent-surface-clawix.manifest.json"}"

cd "$ROOT/macos"
CLAWIX_PERSISTENT_SURFACE_MANIFEST_OUT="$OUT" \
  swift test --filter PersistentSurfaceRegistryTests/testClawixPersistentSurfaceRegistryCoversLocalDatabaseAndPrefs
