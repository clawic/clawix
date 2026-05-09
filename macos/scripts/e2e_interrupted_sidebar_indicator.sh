#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
APP_BUNDLE="$PROJECT_DIR/build/Clawix.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Clawix"
REPORT="$TMP_DIR/meta/report.json"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_DIR/artifacts/e2e}"
SCREENSHOT="$ARTIFACT_DIR/interrupted-sidebar-no-yellow.png"

cleanup() {
  pkill -x Clawix >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/meta" "$ARTIFACT_DIR"

cat > "$TMP_DIR/desktop.json" <<JSON
{
  "electron-saved-workspace-roots": ["$TMP_DIR"],
  "project-order": ["$TMP_DIR"],
  "electron-workspace-root-labels": {
    "$TMP_DIR": "Interrupted Indicator Fixture"
  },
  "pinned-thread-ids": ["thread-interrupted"]
}
JSON

cat > "$TMP_DIR/rollout-interrupted.jsonl" <<JSONL
{"timestamp":"2026-05-09T12:00:00.000Z","type":"session_meta","payload":{"id":"thread-interrupted","cwd":"$TMP_DIR"}}
{"timestamp":"2026-05-09T12:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"interrupted sidebar indicator fixture"}}
{"timestamp":"2026-05-09T12:00:02.000Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"working"}}
JSONL

cat > "$TMP_DIR/threads.json" <<JSON
[
  {
    "id": "thread-interrupted",
    "cwd": "$TMP_DIR",
    "name": "Interrupted indicator fixture",
    "preview": "",
    "path": "$TMP_DIR/rollout-interrupted.jsonl",
    "createdAt": 1770465602,
    "updatedAt": 1770465602,
    "archived": false
  }
]
JSON

(
  cd "$PROJECT_DIR"
  bash "$SCRIPT_DIR/build_app.sh"
) >/tmp/clawix_e2e_interrupted_indicator_build.out 2>/tmp/clawix_e2e_interrupted_indicator_build.err

pkill -x Clawix >/dev/null 2>&1 || true

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_DESKTOP_STATE_FIXTURE="$TMP_DIR/desktop.json" \
CLAWIX_THREAD_FIXTURE="$TMP_DIR/threads.json" \
CLAWIX_METADATA_FILE="$TMP_DIR/meta/state.json" \
CLAWIX_E2E_OPEN_FIRST_CHAT=1 \
CLAWIX_E2E_HYDRATE_REPORT=1 \
CLAWIX_E2E_STATE_REPORT="$REPORT" \
"$APP_BINARY" >/tmp/clawix_e2e_interrupted_indicator_app.out 2>/tmp/clawix_e2e_interrupted_indicator_app.err &
APP_PID="$!"

for _ in {1..80}; do
  kill -0 "$APP_PID" >/dev/null 2>&1 || break
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
  echo "Clawix did not launch" >&2
  exit 1
fi

python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
titles = [chat["title"] for chat in data["chats"]]
assert titles[:1] == ["Interrupted indicator fixture"], titles
PY

sleep 1

WINDOW_INFO="$(swift - "$APP_PID" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}

var best: (id: Int, area: CGFloat)?
for window in windows {
    guard
        let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
        ownerPID == pid,
        let id = window[kCGWindowNumber as String] as? Int,
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? CGFloat,
        let height = bounds["Height"] as? CGFloat
    else { continue }
    let area = width * height
    if best == nil || area > best!.area {
        best = (id, area)
    }
}

if let best {
    print(best.id)
    exit(0)
}
exit(1)
SWIFT
)" || true

if ! [[ "$WINDOW_INFO" =~ ^[0-9]+$ ]]; then
  echo "Clawix window not found" >&2
  exit 1
fi

/usr/sbin/screencapture -x -l "$WINDOW_INFO" "$SCREENSHOT"

swift - "$SCREENSHOT" <<'SWIFT'
import AppKit
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let image = NSImage(contentsOf: url),
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff)
else {
    print("Unable to load screenshot")
    exit(2)
}

let width = bitmap.pixelsWide
let height = bitmap.pixelsHigh
let sidebarSearchLimit = min(width, Int(Double(width) * 0.55))
var yellowPixels = 0

for y in 0..<height {
    for x in 0..<sidebarSearchLimit {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        if red > 0.86,
           green > 0.55,
           green < 0.92,
           blue < 0.45,
           red - blue > 0.35,
           green - blue > 0.25 {
            yellowPixels += 1
        }
    }
}

print("yellow_pixels=\(yellowPixels)")
exit(yellowPixels <= 20 ? 0 : 1)
SWIFT

echo "E2E interrupted sidebar indicator passed"
