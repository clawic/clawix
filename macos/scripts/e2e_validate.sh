#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/build/Clawix.app"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_DIR/artifacts/e2e}"
SCREENSHOT="$ARTIFACT_DIR/main-window.png"
PASS=0
FAIL=0
ERRORS=()

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); ERRORS+=("$1"); }
cleanup_launch_env() {
    launchctl unsetenv CLAWIX_DISABLE_BACKEND >/dev/null 2>&1 || true
}
trap cleanup_launch_env EXIT

echo "=== Clawix Desktop - E2E Validation ==="
mkdir -p "$ARTIFACT_DIR"

echo ""
echo "[1/9] Build"
bash "$SCRIPT_DIR/build_app.sh" || { echo "Build failed"; exit 1; }
pass "App bundle present"

echo ""
echo "[2/9] Localization resources"
python3 - "$PROJECT_DIR" <<'PY' || { fail "Localization resources incomplete"; exit 1; }
import json
import plistlib
import re
import sys
from pathlib import Path

project = Path(sys.argv[1])
catalog_path = project / "Sources/Clawix/Resources/Localizable.xcstrings"
data = json.loads(catalog_path.read_text(encoding="utf-8"))
strings = data["strings"]
locales = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans"]

missing = []
for key, entry in strings.items():
    if key.startswith("_zzz_"):
        continue
    for locale in locales:
        loc = entry.get("localizations", {}).get(locale, {})
        if loc.get("stringUnit", {}).get("value"):
            continue
        if loc.get("variations", {}).get("plural"):
            continue
        missing.append(f"{key} [{locale}]")

patterns = [
    r'Text\("((?:[^"\\]|\\.)*)"',
    r'Button\("((?:[^"\\]|\\.)*)"',
    r'Label\("((?:[^"\\]|\\.)*)"',
    r'Toggle\("((?:[^"\\]|\\.)*)"',
    r'Picker\("((?:[^"\\]|\\.)*)"',
    r'TextField\("((?:[^"\\]|\\.)*)"',
    r'SecureField\("((?:[^"\\]|\\.)*)"',
    r'\.help\("((?:[^"\\]|\\.)*)"',
    r'\.accessibilityLabel\("((?:[^"\\]|\\.)*)"',
    r'MCPFieldLabel\("((?:[^"\\]|\\.)*)"',
    r'String\(localized: "((?:[^"\\]|\\.)*)"',
    r'L10n\.t\("((?:[^"\\]|\\.)*)"\)',
]
ignored = {
    "", " ", "•", ">_", "2", "px", "ESC", "26.430.10722",
    "/Users/me/code/foo", r"~/Documents/\(project.name)",
    r"\(index).", r"⌘\(number)", r"\(Int(value))", r"\(percent) %",
    r"\(item.date) · \(item.project)",
}

def unescape(value: str) -> str:
    return value.replace(r"\"", '"').replace(r"\n", "\n").replace(r"\t", "\t").replace(r"\\", "\\")

def swift_key_candidates(value: str) -> set[str]:
    candidates = {value}
    candidates.add(re.sub(r"\\\([^)]*\)", "%@", value))
    candidates.add(re.sub(r"\\\(Int\([^)]*\)\)", "%lld", value))
    candidates.add(re.sub(r"\\\([^)]*\)", "%lld", value))
    return candidates

catalog_keys = set(strings)
source_dir = project / "Sources/Clawix"
unregistered = []
for path in source_dir.rglob("*.swift"):
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        for pattern in patterns:
            for match in re.finditer(pattern, line):
                value = unescape(match.group(1))
                if value in ignored or not value.strip():
                    continue
                if re.fullmatch(r"[0-9%() _./\\>_<⌘·:-]+", value):
                    continue
                if swift_key_candidates(value).isdisjoint(catalog_keys):
                    unregistered.append(f"{path.relative_to(project)}:{lineno}: {value}")

resource_dir = project / "Sources/Clawix/Resources"
app_resource_dir = project / "build/Clawix.app/Contents/Resources"
missing_generated = []
for locale in locales:
    strings_path = resource_dir / f"{locale}.lproj/Localizable.strings"
    stringsdict_path = resource_dir / f"{locale}.lproj/Localizable.stringsdict"
    app_locale = locale.lower() if locale in {"pt-BR", "zh-Hans"} else locale
    app_strings_path = app_resource_dir / f"{app_locale}.lproj/Localizable.strings"
    if not strings_path.exists():
        missing_generated.append(str(strings_path.relative_to(project)))
    if not stringsdict_path.exists():
        missing_generated.append(str(stringsdict_path.relative_to(project)))
    elif len(plistlib.load(stringsdict_path.open("rb"))) < 1:
        missing_generated.append(str(stringsdict_path.relative_to(project)))
    if not app_strings_path.exists():
        missing_generated.append(str(app_strings_path.relative_to(project)))
if not (app_resource_dir / "Clawix_Clawix.bundle").exists():
    missing_generated.append(str((app_resource_dir / "Clawix_Clawix.bundle").relative_to(project)))

if missing or unregistered or missing_generated:
    for label, items in [
        ("missing catalog localizations", missing),
        ("unregistered UI strings", unregistered),
        ("missing generated resources", missing_generated),
    ]:
        if items:
            print(label)
            for item in items[:80]:
                print("  " + item)
    sys.exit(1)
PY
pass "Localization catalog complete"

echo ""
echo ""
echo "[3/9] Runtime surface regression guards"
if grep -R -nE 'Fusionar|No trabajar en un proyecto|Preguntar siempre|Sitio web' "$PROJECT_DIR/Sources/Clawix" --include='*.swift' >/tmp/clawix_e2e_spanish_ui.out; then
    fail "Spanish text leaked into Swift UI source: $(head -n 1 /tmp/clawix_e2e_spanish_ui.out)"
else
    pass "Swift UI source has no accidental Spanish labels"
fi

if grep -Fq 'func openBrowser(initialURL: URL = URL(string: "about:blank")!)' "$PROJECT_DIR/Sources/Clawix/AppState.swift" \
   && grep -Fq 'func newBrowserTab(url: URL = URL(string: "about:blank")!)' "$PROJECT_DIR/Sources/Clawix/AppState.swift"; then
    pass "Browser opens blank tabs by default"
else
    fail "Browser default tab still performs external navigation"
fi

if grep -Fq 'readyFromDaemon' "$PROJECT_DIR/Sources/Clawix/ClawJS/ClawJSServiceStatus.swift" \
   && grep -Fq 'daemonUnavailable' "$PROJECT_DIR/Sources/Clawix/ClawJS/ClawJSServiceStatus.swift"; then
    pass "ClawJS daemon-owned service states are explicit"
else
    fail "ClawJS daemon-owned service states are missing"
fi

echo ""
echo "[4/9] Speech recognition language"
if grep -Fq 'Locale(identifier: "es-ES")' "$PROJECT_DIR/Sources/Clawix/VoiceRecorder.swift"; then
    fail "Voice transcription is hard-coded to a single locale"
else
    pass "Voice transcription is not hard-coded to a single locale"
fi

for expected in "en-US" "es-ES" "fr-FR" "de-DE" "it-IT" "pt-BR" "ja-JP" "zh-CN" "ko-KR" "ru-RU"; do
    if grep -Fq "Locale(identifier: \"$expected\")" "$PROJECT_DIR/Sources/Clawix/Localization/AppLanguage.swift"; then
        pass "Speech locale mapped: $expected"
    else
        fail "Missing speech locale mapping: $expected"
    fi
done

echo ""
echo "[5/9] Launch"
pkill -x Clawix >/dev/null 2>&1 || true
launchctl setenv CLAWIX_DISABLE_BACKEND 1 >/dev/null 2>&1 || true
open -n "$APP_BUNDLE"
sleep 3
cleanup_launch_env

APP_PID="$(pgrep -x Clawix | head -n 1 || true)"
if [[ -n "$APP_PID" ]]; then
    pass "Process running"
else
    fail "Process not found after launch"
    exit 1
fi

echo ""
echo "[6/9] Window discovery"
WINDOW_INFO="$(swift - "$APP_PID" <<'SWIFT'
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}

var best: (id: Int, width: CGFloat, height: CGFloat, area: CGFloat)?
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
        best = (id, width, height, area)
    }
}

if let best {
    print("\(best.id) \(Int(best.width)) \(Int(best.height))")
    exit(0)
}
exit(1)
SWIFT
)" || true

WINDOW_ID="$(awk '{print $1}' <<<"$WINDOW_INFO")"
WINDOW_W="$(awk '{print $2}' <<<"$WINDOW_INFO")"
WINDOW_H="$(awk '{print $3}' <<<"$WINDOW_INFO")"

if [[ "$WINDOW_ID" =~ ^[0-9]+$ && "$WINDOW_W" -ge 900 && "$WINDOW_H" -ge 560 ]]; then
    pass "Native window visible"
else
    fail "Native window not found or too small ($WINDOW_INFO)"
fi

echo ""
echo "[7/9] Accessibility tree budget"
swift - "$APP_PID" <<'SWIFT' || { fail "Accessibility tree exposes oversized repeated message labels"; exit 1; }
import ApplicationServices
import Foundation

let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
var visited = 0
var offenders: [String] = []

func copyAttribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return result == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    copyAttribute(element, name) as? String
}

func repeatedRolePrefixCount(_ text: String) -> Int {
    max(
        text.components(separatedBy: "Assistant:").count - 1,
        text.components(separatedBy: "You:").count - 1
    )
}

func inspect(_ element: AXUIElement, depth: Int = 0) {
    if visited > 6000 || depth > 14 || offenders.count >= 8 { return }
    visited += 1

    let values = [
        stringAttribute(element, kAXTitleAttribute),
        stringAttribute(element, kAXValueAttribute),
        stringAttribute(element, kAXDescriptionAttribute)
    ].compactMap { $0 }

    for value in values {
        if value.count > 3000 || repeatedRolePrefixCount(value) >= 3 {
            offenders.append(String(value.prefix(180)).replacingOccurrences(of: "\n", with: " "))
        }
    }

    guard let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
    for child in children { inspect(child, depth: depth + 1) }
}

inspect(app)
if offenders.isEmpty {
    exit(0)
}
for offender in offenders {
    print(offender)
}
exit(1)
SWIFT
pass "Accessibility labels stay bounded"

echo ""
echo "[8/9] Window screenshot"
rm -f "$SCREENSHOT" /tmp/clawix_e2e_capture.out
SCREENSHOT_CAPTURED=0
SCREENSHOT_SKIPPED=0
if /usr/sbin/screencapture -x -l "$WINDOW_ID" "$SCREENSHOT" >/tmp/clawix_e2e_capture.out 2>&1 && [[ -s "$SCREENSHOT" ]]; then
    pass "Window screenshot captured"
    SCREENSHOT_CAPTURED=1
else
    CAPTURE_ACCESS="$(swift - <<'SWIFT'
import CoreGraphics
print(CGPreflightScreenCaptureAccess() ? "granted" : "denied")
SWIFT
)"
    if [[ "$CAPTURE_ACCESS" == "denied" ]]; then
        pass "Window screenshot skipped because Screen Recording permission is unavailable"
        SCREENSHOT_SKIPPED=1
    else
        fail "Window screenshot failed: $(cat /tmp/clawix_e2e_capture.out 2>/dev/null || true)"
    fi
fi

if [[ "$SCREENSHOT_CAPTURED" -eq 1 ]]; then
    PIXEL_W="$(sips -g pixelWidth "$SCREENSHOT" 2>/dev/null | awk '/pixelWidth/ {print $2}' || echo 0)"
    PIXEL_H="$(sips -g pixelHeight "$SCREENSHOT" 2>/dev/null | awk '/pixelHeight/ {print $2}' || echo 0)"
    if [[ "$PIXEL_W" -ge 900 && "$PIXEL_H" -ge 560 ]]; then
        pass "Screenshot dimensions plausible"
    else
        fail "Screenshot dimensions too small (${PIXEL_W}x${PIXEL_H})"
    fi
elif [[ "$SCREENSHOT_SKIPPED" -eq 1 ]]; then
    pass "Screenshot dimensions skipped because no screenshot was captured"
else
    fail "Screenshot dimensions unavailable"
fi

if [[ -s "$APP_BUNDLE/Contents/Resources/Clawix.icns" ]]; then
    pass "App icon bundled"
else
    fail "App icon missing from bundle"
fi

echo ""
echo "[9/9] Public hygiene"
bash "$SCRIPT_DIR/public_hygiene_check.sh" || {
    fail "Public hygiene scan failed"
    exit 1
}
pass "Public hygiene scan passed"

echo ""
echo "Cleanup"
pkill -x Clawix >/dev/null 2>&1 || true
launchctl unsetenv CLAWIX_DISABLE_BACKEND >/dev/null 2>&1 || true
sleep 1
pass "App terminated"

echo ""
echo "=== Results ==="
printf "  Passed: %d\n" "$PASS"
printf "  Failed: %d\n" "$FAIL"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "  Failures:"
    for e in "${ERRORS[@]}"; do echo "    - $e"; done
fi

if [[ $FAIL -eq 0 ]]; then
    echo "VALIDATION PASSED"
    echo "artifact:screenshot=$SCREENSHOT"
    exit 0
fi

echo "VALIDATION FAILED"
exit 1
