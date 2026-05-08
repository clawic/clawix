#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TMP_DIR="$(mktemp -d)"
APP_BINARY="$PROJECT_DIR/.build/debug/Clawix"
REPORT="$TMP_DIR/dictation-report.json"
CAPTURE="$TMP_DIR/text-injector.json"

cleanup() {
  pkill -x Clawix >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

(
  cd "$PROJECT_DIR"
  swift build
) >/tmp/clawix_e2e_dictation_build.out 2>/tmp/clawix_e2e_dictation_build.err

pkill -x Clawix >/dev/null 2>&1 || true

CLAWIX_DISABLE_BACKEND=1 \
CLAWIX_E2E_DICTATION_REPORT="$REPORT" \
CLAWIX_E2E_TEXT_INJECTOR_CAPTURE="$CAPTURE" \
CLAWIX_E2E_TRANSCRIPTION_TEXT="um clawix e2e dictation" \
CLAWIX_E2E_TRANSCRIPTION_VAD_FAIL=1 \
CLAWIX_E2E_TRANSCRIPTION_EMPTY_UNTIL_PERMISSIVE=1 \
CLAWIX_E2E_ENHANCEMENT_FAIL=1 \
"$APP_BINARY" >/tmp/clawix_e2e_dictation_app.out 2>/tmp/clawix_e2e_dictation_app.err &

for _ in {1..60}; do
  [[ -s "$REPORT" ]] && break
  sleep 0.25
done

python3 - "$REPORT" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    report = json.load(f)

required = [
    "shortcutStarted",
    "shortcutStopped",
    "vadFallbackPassed",
    "fillerFallbackPassed",
    "replacementPassed",
    "enhancementFallbackPassed",
    "pastePayloadPassed",
    "clipboardRestorePassed",
    "autoSendPassed",
    "missingModelPreflightPassed",
    "cloudMockPassed",
]

missing = [key for key in required if not report.get(key)]
if missing or not report.get("passed"):
    print(json.dumps(report, indent=2, sort_keys=True))
    raise SystemExit(f"Dictation E2E failed: {', '.join(missing)}")
PY

echo "E2E dictation fixture passed"
