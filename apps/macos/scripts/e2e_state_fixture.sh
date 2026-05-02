#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
APP_BINARY="$PROJECT_DIR/.build/debug/Clawix"
REPORT="$TMP_DIR/report.json"

cleanup() {
  pkill -x Clawix >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ROOT_A="$TMP_DIR/Alpha Root"
ROOT_B="$TMP_DIR/Beta Root"
mkdir -p "$ROOT_A/sub" "$ROOT_B" "$TMP_DIR/meta"

cat > "$TMP_DIR/desktop.json" <<JSON
{
  "electron-saved-workspace-roots": ["$ROOT_A", "$ROOT_B"],
  "project-order": ["$ROOT_B", "$ROOT_A"],
  "electron-workspace-root-labels": {
    "$ROOT_A": "Alpha Label",
    "$ROOT_B": "Beta Label"
  },
  "pinned-thread-ids": ["thread-alpha"],
  "thread-workspace-root-hints": {
    "thread-hinted": "$ROOT_A"
  },
  "projectless-thread-ids": ["thread-projectless"]
}
JSON

cat > "$TMP_DIR/threads.json" <<JSON
[
  {
    "id": "thread-alpha",
    "cwd": "$ROOT_A/sub",
    "name": "Runtime Alpha",
    "preview": "Ignored preview",
    "path": "$TMP_DIR/rollout-alpha.jsonl",
    "createdAt": 100,
    "updatedAt": 400,
    "archived": false
  },
  {
    "id": "thread-projectless",
    "cwd": "$ROOT_B",
    "name": null,
    "preview": "Fallback title from first user message that is deliberately long",
    "path": "$TMP_DIR/rollout-projectless.jsonl",
    "createdAt": 90,
    "updatedAt": 300,
    "archived": false
  },
  {
    "id": "thread-hinted",
    "cwd": "$TMP_DIR/elsewhere",
    "name": "Hinted Thread",
    "preview": "",
    "path": "$TMP_DIR/rollout-hinted.jsonl",
    "createdAt": 80,
    "updatedAt": 200,
    "archived": false
  },
  {
    "id": "thread-archived",
    "cwd": "$ROOT_A",
    "name": "Archived Thread",
    "preview": "",
    "path": "$TMP_DIR/rollout-archived.jsonl",
    "createdAt": 70,
    "updatedAt": 100,
    "archived": true
  }
]
JSON

(
  cd "$PROJECT_DIR"
  swift build
) >/tmp/clawix_e2e_state_build.out 2>/tmp/clawix_e2e_state_build.err
pkill -x Clawix >/dev/null 2>&1 || true

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_DESKTOP_STATE_FIXTURE="$TMP_DIR/desktop.json" \
CLAWIX_THREAD_FIXTURE="$TMP_DIR/threads.json" \
CLAWIX_METADATA_FILE="$TMP_DIR/meta/state.json" \
CLAWIX_E2E_STATE_REPORT="$REPORT" \
"$APP_BINARY" >/tmp/clawix_e2e_state_app.out 2>/tmp/clawix_e2e_state_app.err &

for _ in {1..40}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

python3 - "$REPORT" "$ROOT_A" "$ROOT_B" <<'PY'
import json, sys
report, root_a, root_b = sys.argv[1:4]
with open(report) as f:
    data = json.load(f)

projects = data["projects"]
assert [p["path"] for p in projects[:2]] == [root_b, root_a], projects
assert [p["name"] for p in projects[:2]] == ["Beta Label", "Alpha Label"], projects

chats = {c["threadId"]: c for c in data["chats"]}
assert chats["thread-alpha"]["title"] == "Runtime Alpha", chats["thread-alpha"]
assert chats["thread-alpha"]["projectPath"] == root_a, chats["thread-alpha"]
assert chats["thread-alpha"]["isPinned"] is True, chats["thread-alpha"]
assert chats["thread-projectless"]["projectPath"] == "", chats["thread-projectless"]
assert chats["thread-projectless"]["title"].startswith("Fallback title from first user message"), chats["thread-projectless"]
assert chats["thread-hinted"]["projectPath"] == root_a, chats["thread-hinted"]
assert chats["thread-archived"]["isArchived"] is True, chats["thread-archived"]
assert data["pinnedCount"] == 1, data
assert data["archivedCount"] == 1, data
PY

pkill -x Clawix >/dev/null 2>&1 || true
rm -f "$REPORT"
cat > "$TMP_DIR/meta/state.json" <<JSON
{
  "version": 2,
  "projects": [],
  "pinnedThreadIds": ["thread-hinted"],
  "chatProjectPathByThread": {
    "thread-projectless": "$ROOT_A"
  },
  "projectlessThreadIds": [],
  "hasLocalPins": true,
  "localProjects": []
}
JSON

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_DESKTOP_STATE_FIXTURE="$TMP_DIR/desktop.json" \
CLAWIX_THREAD_FIXTURE="$TMP_DIR/threads.json" \
CLAWIX_METADATA_FILE="$TMP_DIR/meta/state.json" \
CLAWIX_E2E_STATE_REPORT="$REPORT" \
"$APP_BINARY" >/tmp/clawix_e2e_state_app_2.out 2>/tmp/clawix_e2e_state_app_2.err &

for _ in {1..40}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

python3 - "$REPORT" "$ROOT_A" <<'PY'
import json, sys
report, root_a = sys.argv[1:3]
with open(report) as f:
    data = json.load(f)
chats = {c["threadId"]: c for c in data["chats"]}
assert chats["thread-alpha"]["isPinned"] is False, chats["thread-alpha"]
assert chats["thread-hinted"]["isPinned"] is True, chats["thread-hinted"]
assert chats["thread-projectless"]["projectPath"] == root_a, chats["thread-projectless"]
assert data["pinnedCount"] == 1, data
PY

echo "E2E runtime state fixture passed"
