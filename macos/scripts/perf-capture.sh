#!/usr/bin/env bash
# Capture an Instruments trace of Clawix for post-mortem perf analysis.
#
# Use this when the user reports "X feels slow" / "RAM keeps growing"
# / "frames drop". The script:
#   1. Builds the dev .app via `dev.sh` (signed with the same identity
#      so TCC permissions are not lost), but skips the launch.
#   2. Kills any leftover Clawix instance.
#   3. Runs `xctrace record` with the requested template, launching the
#      built binary so xctrace owns the process from t=0 (launch
#      timeline included).
#   4. After the trace ends (Ctrl-C, --time-limit, or app quit) copies
#      the live RenderProbe log, the most recent MetricKit JSON
#      payloads, the last-resources.json snapshot, and a filtered
#      `log show` console capture into the trace directory.
#   5. Prints the absolute path so the caller can `open trace.trace`
#      in Instruments.
#
# Templates supported (see PERF.md for which to pick per symptom):
#   "Time Profiler"        → CPU samples per thread.
#   "SwiftUI"              → body invalidations, animations.
#   "Animation Hitches"    → frame budget violations.
#   "Allocations"          → live allocation graph; pair with mark
#                            generations between interactions.
#   "Leaks"                → reachability cycles.
#   "os_signpost"          → our taxonomy lit up alongside the system
#                            signposts. Default; cheapest for triage.
#
# Examples:
#   bash macos/scripts/perf-capture.sh --template "os_signpost" --name sidebar-lag
#   bash macos/scripts/perf-capture.sh --template "Animation Hitches" --duration 30
#   bash macos/scripts/perf-capture.sh --template "Allocations" --name long-session
#
# Prerequisites: Xcode Command Line Tools (`xcrun xctrace --version`
# must succeed). Sign identity comes from `.signing.env` like dev.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Clawix"
DEV_DIR="$HOME/Library/Caches/Clawix-Dev"
BUNDLE="$DEV_DIR/${APP_NAME}.app"
BIN="$BUNDLE/Contents/MacOS/${APP_NAME}"

TEMPLATE="os_signpost"
LABEL=""
DURATION=""

usage() {
    cat <<USAGE
Usage: $0 [--template <name>] [--name <label>] [--duration <seconds>]

Defaults:
  --template "os_signpost"
  --name <unset>          (label appears in the trace directory name)
  --duration <unset>      (record until Ctrl-C / app quit)

See the header comment of this script for the list of templates and
PERF.md for which to pick per symptom.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --template) TEMPLATE="$2"; shift 2 ;;
        --name)     LABEL="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! command -v xcrun >/dev/null 2>&1; then
    echo "ERROR: xcrun not found. Install Xcode Command Line Tools." >&2
    exit 1
fi
if ! xcrun xctrace version >/dev/null 2>&1; then
    echo "ERROR: xctrace not available. Install Xcode (full IDE, not just CLT)." >&2
    exit 1
fi

# 1) Build via dev.sh, skipping the launch. dev.sh handles squircle
#    lint, swift build, helper bundling, codesign with the maintainer
#    identity, and produces the .app at $BUNDLE. CLAWIX_DEV_NOLAUNCH
#    short-circuits the `open -n` call.
echo "==> Building $APP_NAME (no launch)"
CLAWIX_DEV_NOLAUNCH=1 bash "$SCRIPT_DIR/dev.sh"

if [[ ! -x "$BIN" ]]; then
    echo "ERROR: built binary missing at $BIN" >&2
    exit 1
fi

# 2) Kill any previous instance so xctrace owns the only one. Same
#    PID-collection logic as dev.sh.
PIDS=$({
    pgrep -f "${DEV_DIR}/.*/${APP_NAME}" 2>/dev/null || true
    pgrep -f "${PROJECT_DIR}/build/.*/${APP_NAME}" 2>/dev/null || true
    pgrep -x "$APP_NAME" 2>/dev/null || true
} | sort -u)
if [[ -n "$PIDS" ]]; then
    echo "==> Stopping previous ${APP_NAME} (PIDs: $PIDS)"
    kill $PIDS 2>/dev/null || true
    sleep 1
    REMAIN=$(pgrep -x "$APP_NAME" 2>/dev/null | sort -u || true)
    [[ -n "$REMAIN" ]] && kill -9 $REMAIN 2>/dev/null || true
fi

# 3) Resolve trace output directory. Slot under macos/artifacts/
#    so the .gitignore'd directory keeps everything together.
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LABEL_SLUG="$(echo "${LABEL:-trace}" | tr -cs '[:alnum:]_.-' '-' | sed 's/^-*//;s/-*$//')"
[[ -z "$LABEL_SLUG" ]] && LABEL_SLUG="trace"
OUT_DIR="$PROJECT_DIR/artifacts/traces/${STAMP}-${LABEL_SLUG}"
mkdir -p "$OUT_DIR"
TRACE_PATH="$OUT_DIR/trace.trace"
LAUNCH_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

XCTRACE_ARGS=(
    record
    --template "$TEMPLATE"
    --output "$TRACE_PATH"
)
if [[ -n "$DURATION" ]]; then
    XCTRACE_ARGS+=( --time-limit "${DURATION}s" )
fi
XCTRACE_ARGS+=( --launch -- "$BIN" )

echo ""
echo "==> Recording trace"
echo "    template:  $TEMPLATE"
echo "    target:    $BIN"
echo "    output:    $TRACE_PATH"
[[ -n "$DURATION" ]] && echo "    duration:  ${DURATION}s"
echo ""
echo "Reproduce the slow interaction in the app. Press Ctrl-C (or"
echo "quit the app) to stop the recording."
echo ""

# Forward Ctrl-C to xctrace so it flushes the trace cleanly.
trap 'echo "==> Stopping trace…"; kill -INT %1 2>/dev/null || true' INT TERM
xcrun xctrace "${XCTRACE_ARGS[@]}" || true
trap - INT TERM

# 4) Collect supplementary artifacts.
echo ""
echo "==> Collecting supplementary artifacts"

# Live RenderProbe log (counts of body re-evals, hitch buckets per
# 0.5 s window). Lives in /tmp/ as documented at the top of
# RenderProbe.swift.
if [[ -f /tmp/clawix-renders.log ]]; then
    cp /tmp/clawix-renders.log "$OUT_DIR/clawix-renders.log"
fi

# MetricKit JSON payloads + last-resources.json snapshot.
DIAG_DIR="$HOME/Library/Application Support"
if [[ -d "$DIAG_DIR" ]]; then
    while IFS= read -r d; do
        bn="$(basename "$d")"
        # Match anything that owns a Diagnostics subdir under the user
        # Application Support: any bundle id of any Clawix-family
        # build (the maintainer's real id, the dev placeholder, or a
        # fork). We don't hardcode the literal value here.
        if [[ -d "$d/Diagnostics" ]]; then
            cp -R "$d/Diagnostics" "$OUT_DIR/Diagnostics-$bn"
        fi
    done < <(find "$DIAG_DIR" -maxdepth 1 -type d -name '*clawix*' -o -name '*Clawix*' 2>/dev/null | sort)
fi

# Filtered console capture from the trace window. We grep our
# subsystem so the log isn't 50 MB of unrelated system noise. `log
# show` requires the timestamp in local time.
SUBSYSTEM="${BUNDLE_ID:-com.example.clawix.desktop}"
echo "    subsystem: $SUBSYSTEM"
log show \
    --predicate "subsystem == \"$SUBSYSTEM\"" \
    --start "$LAUNCH_TIME" \
    --style ndjson \
    > "$OUT_DIR/console.ndjson" 2>"$OUT_DIR/console.err" || true

# Stuff a small README so the directory is self-explanatory weeks later.
cat > "$OUT_DIR/README.txt" <<EOF
Clawix performance trace
========================

Template:   $TEMPLATE
Label:      ${LABEL:-<none>}
Captured:   $LAUNCH_TIME
Bundle id:  $SUBSYSTEM

Files
-----
  trace.trace                 Open in Instruments.app:  open trace.trace
  console.ndjson              \`log show\` output filtered by subsystem
  clawix-renders.log          RenderProbe per-window counters
  Diagnostics-*/              MetricKit JSON payloads + last-resources.json

See macos/PERF.md for the symptom-to-template mapping and what
to look for in each lane of the trace.
EOF

echo ""
echo "Done."
echo "Trace directory: $OUT_DIR"
echo "Open trace:      open '$TRACE_PATH'"
