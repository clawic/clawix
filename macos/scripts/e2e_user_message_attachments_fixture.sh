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

python3 - "$TMP_DIR/first.png" "$TMP_DIR/second.png" <<'PY'
import base64, pathlib, sys
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")
for path in sys.argv[1:]:
    pathlib.Path(path).write_bytes(png)
PY

cat > "$TMP_DIR/rollout-user-attachments.jsonl" <<JSONL
{"timestamp":"2026-05-09T10:52:25.716Z","type":"session_meta","payload":{"id":"session-user-attachments","cwd":"/tmp"}}
{"timestamp":"2026-05-09T10:52:25.723Z","type":"event_msg","payload":{"type":"user_message","message":"# Files mentioned by the user:\n\n## first.png: $TMP_DIR/first.png\n\n## second.png: $TMP_DIR/second.png\n\n## My request for Codex:\nDisable the workflow.\n\nKeep the repo quiet.","local_images":["$TMP_DIR/first.png","$TMP_DIR/second.png"],"images":[]}}
{"timestamp":"2026-05-09T10:52:43.925Z","type":"event_msg","payload":{"type":"agent_message","message":"I will remove it.","phase":"commentary"}}
{"timestamp":"2026-05-09T10:54:33.629Z","type":"event_msg","payload":{"type":"agent_message","message":"Done.","phase":"final_answer"}}
{"timestamp":"2026-05-09T10:54:33.659Z","type":"event_msg","payload":{"type":"task_complete","duration_ms":129980}}
JSONL

cat > "$TMP_DIR/desktop.json" <<'JSON'
{
  "electron-saved-workspace-roots": ["/tmp"],
  "project-order": ["/tmp"],
  "electron-workspace-root-labels": {
    "/tmp": "Tmp"
  }
}
JSON

cat > "$TMP_DIR/threads.json" <<JSON
[
  {
    "id": "thread-user-attachments",
    "cwd": "/tmp",
    "name": "User attachments fixture",
    "preview": "",
    "path": "$TMP_DIR/rollout-user-attachments.jsonl",
    "createdAt": 100,
    "updatedAt": 400,
    "archived": false
  }
]
JSON

(
  cd "$PROJECT_DIR"
  swift build
) >/tmp/clawix_e2e_user_attachments_build.out 2>/tmp/clawix_e2e_user_attachments_build.err
pkill -x Clawix >/dev/null 2>&1 || true

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_BRIDGE_DISABLE=1 \
CLAWIX_DESKTOP_STATE_FIXTURE="$TMP_DIR/desktop.json" \
CLAWIX_THREAD_FIXTURE="$TMP_DIR/threads.json" \
CLAWIX_METADATA_FILE="$TMP_DIR/meta/state.json" \
CLAWIX_E2E_STATE_REPORT="$REPORT" \
CLAWIX_E2E_HYDRATE_REPORT=1 \
CLAWIX_E2E_OPEN_FIRST_CHAT=1 \
"$APP_BINARY" >/tmp/clawix_e2e_user_attachments_app.out 2>/tmp/clawix_e2e_user_attachments_app.err &

for _ in {1..40}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)

messages = data["chats"][0]["messages"]
assert messages[0]["role"] == "user", messages
assert messages[0]["attachmentCount"] == 2, messages[0]
assert messages[0]["renderedImageCount"] == 2, messages[0]
assert messages[0]["renderedText"] == "Disable the workflow.\n\nKeep the repo quiet.", messages[0]
assert "Files mentioned by the user" not in messages[0]["renderedText"], messages[0]
assert messages[1]["role"] == "assistant", messages
assert messages[1]["workElapsedSeconds"] == 129, messages[1]
PY

echo "E2E user message attachments fixture passed"
