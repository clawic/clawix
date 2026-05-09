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

cat > "$TMP_DIR/rollout-computer-use.jsonl" <<'JSONL'
{"timestamp":"2026-05-09T12:00:00.000Z","type":"session_meta","payload":{"id":"session-computer-use","cwd":"/tmp"}}
{"timestamp":"2026-05-09T12:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"inspect the screen"}}
{"timestamp":"2026-05-09T12:00:02.000Z","type":"event_msg","payload":{"type":"mcp_tool_call_end","call_id":"call-computer-use","invocation":{"server":"computer_use","tool":"get_app_state"},"result":{"content":[{"type":"text","text":"ok"}]}}}
{"timestamp":"2026-05-09T12:00:03.000Z","type":"event_msg","payload":{"type":"agent_message","phase":"final_answer","message":"Done."}}
{"timestamp":"2026-05-09T12:00:04.000Z","type":"event_msg","payload":{"type":"turn_completed"}}
JSONL

cat > "$TMP_DIR/desktop.json" <<JSON
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
    "id": "thread-computer-use",
    "cwd": "/tmp",
    "name": "Computer Use fixture",
    "preview": "",
    "path": "$TMP_DIR/rollout-computer-use.jsonl",
    "createdAt": 100,
    "updatedAt": 400,
    "archived": false
  }
]
JSON

(
  cd "$PROJECT_DIR"
  swift build
) >/tmp/clawix_e2e_tool_timeline_build.out 2>/tmp/clawix_e2e_tool_timeline_build.err
pkill -x Clawix >/dev/null 2>&1 || true

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_DESKTOP_STATE_FIXTURE="$TMP_DIR/desktop.json" \
CLAWIX_THREAD_FIXTURE="$TMP_DIR/threads.json" \
CLAWIX_METADATA_FILE="$TMP_DIR/meta/state.json" \
CLAWIX_E2E_STATE_REPORT="$REPORT" \
CLAWIX_E2E_HYDRATE_REPORT=1 \
CLAWIX_E2E_OPEN_FIRST_CHAT=1 \
"$APP_BINARY" >/tmp/clawix_e2e_tool_timeline_app.out 2>/tmp/clawix_e2e_tool_timeline_app.err &

for _ in {1..40}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)

chat = data["chats"][0]
rows = chat["toolRows"]
assert len(rows) == 1, rows
assert rows[0]["id"] == "mcp0", rows
assert rows[0]["icon"] == "clawix.computerUse", rows
assert "Computer Use" in rows[0]["text"], rows
PY

echo "E2E tool timeline fixture passed"
