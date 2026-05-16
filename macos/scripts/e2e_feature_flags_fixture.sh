#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
APP_BINARY="$PROJECT_DIR/.build/debug/Clawix"
REPORT="$TMP_DIR/report.json"
PREF_DOMAIN="clawix.desktop"
PREV_DEVELOPER_SURFACES="$TMP_DIR/prev-developer-surfaces.txt"

save_pref() {
  local key="$1"
  local out="$2"
  if defaults read "$PREF_DOMAIN" "$key" >"$out" 2>/dev/null; then
    return 0
  fi
  printf '__missing__' >"$out"
}

restore_pref() {
  local key="$1"
  local in="$2"
  local value
  value="$(cat "$in")"
  if [[ "$value" == "__missing__" ]]; then
    defaults delete "$PREF_DOMAIN" "$key" >/dev/null 2>&1 || true
  elif [[ "$value" == "1" || "$value" == "true" || "$value" == "TRUE" || "$value" == "YES" ]]; then
    defaults write "$PREF_DOMAIN" "$key" -bool true
  else
    defaults write "$PREF_DOMAIN" "$key" -bool false
  fi
}

cleanup() {
  pkill -x Clawix >/dev/null 2>&1 || true
  restore_pref FeatureFlags.developerSurfaces "$PREV_DEVELOPER_SURFACES"
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

save_pref FeatureFlags.developerSurfaces "$PREV_DEVELOPER_SURFACES"
defaults write "$PREF_DOMAIN" FeatureFlags.developerSurfaces -bool false

cat > "$TMP_DIR/desktop.json" <<'JSON'
{
  "electron-saved-workspace-roots": [],
  "project-order": [],
  "electron-workspace-root-labels": {}
}
JSON

cat > "$TMP_DIR/threads.json" <<'JSON'
[]
JSON
mkdir -p "$TMP_DIR/meta"

(
  cd "$PROJECT_DIR"
  swift build
) >/tmp/clawix_e2e_feature_flags_build.out 2>/tmp/clawix_e2e_feature_flags_build.err
pkill -x Clawix >/dev/null 2>&1 || true

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_BRIDGE_DISABLE=1 \
CLAWIX_DESKTOP_STATE_FIXTURE="$TMP_DIR/desktop.json" \
CLAWIX_THREAD_FIXTURE="$TMP_DIR/threads.json" \
CLAWIX_METADATA_FILE="$TMP_DIR/meta/state.json" \
CLAWIX_E2E_STATE_REPORT="$REPORT" \
"$APP_BINARY" >/tmp/clawix_e2e_feature_flags_app.out 2>/tmp/clawix_e2e_feature_flags_app.err &

for _ in {1..40}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

python3 - "$REPORT" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

assert data["featureVisibility"]["remoteMesh"] is True, data
assert data["featureVisibility"]["simulators"] is False, data
assert "machines" in data["visibleSettingsCategories"], data
assert data["selectedMeshTarget"] == "local", data
PY

echo "E2E feature flags fixture passed"
