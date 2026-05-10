#!/usr/bin/env bash
# Guided performance workout for reproducible Clawix traces.
#
# Run this while `perf-capture.sh` is recording. It writes timestamped
# phase markers to /tmp/clawix-renders.log so the analysis pass can
# compare idle, hover, scroll, chat switching, typing and resize phases
# across captures.

set -euo pipefail

LOG_PATH="/tmp/clawix-renders.log"
PROFILE="standard"

usage() {
    cat <<USAGE
Usage: $0 [--profile standard|sidebar|chat]

Profiles:
  standard  Broad smoke workout for subjective slowness.
  sidebar   Sidebar hover, scroll and chat switching phases.
  chat      Open a heavy chat, scroll it, then type without sending.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

mark() {
    local tag="$1"
    local stamp
    stamp="$(perl -MTime::HiRes=time -e 'printf "%.3f", time()')"
    printf '[%s] === MARK: %s ===\n' "$stamp" "$tag" >> "$LOG_PATH"
}

prep() {
    local name="$1"
    local seconds="$2"
    local instructions="$3"
    printf '\n=== %s (%ss) ===\n' "$name" "$seconds"
    printf '%s\n' "$instructions"
    printf 'Starting in '
    for i in 3 2 1; do
        printf '%s ' "$i"
        sleep 1
    done
    printf 'GO\n'
}

run_phase() {
    local name="$1"
    local seconds="$2"
    local instructions="$3"
    prep "$name" "$seconds" "$instructions"
    mark "${name}-start"
    sleep "$seconds"
    mark "${name}-end"
    printf 'Done.\n'
}

reset_log() {
    : > "$LOG_PATH"
    printf 'Clean render log: %s\n' "$LOG_PATH"
    printf 'Keep the app focused and perform each action when GO appears.\n'
}

run_sidebar() {
    run_phase "idle" 7 "Do not touch the app. Keep the pointer outside the sidebar."
    run_phase "hover-sidebar-rows" 8 "Move the pointer up and down over recent chat rows without clicking."
    run_phase "scroll-sidebar" 8 "Scroll the sidebar up and down several times."
    run_phase "switch-chats" 10 "Click several chats in sequence, preferably from different projects."
    run_phase "idle-end" 7 "Do not touch the app."
}

run_chat() {
    run_phase "idle" 7 "Do not touch the app."
    run_phase "open-heavy-chat" 10 "Open the largest or slowest chat available."
    run_phase "expand-work-summary" 10 "Expand and collapse the longest Worked for summary in the visible chat."
    run_phase "scroll-chat" 12 "Scroll the chat up and down through older messages."
    run_phase "type-composer" 8 "Type about twenty characters in the composer. Do not send."
    run_phase "idle-end" 7 "Do not touch the app."
}

run_standard() {
    run_sidebar
    run_phase "resize-window" 8 "Drag the right edge of the window wider and narrower several times."
    run_chat
}

reset_log
case "$PROFILE" in
    standard) run_standard ;;
    sidebar) run_sidebar ;;
    chat) run_chat ;;
    *)
        echo "ERROR: unknown profile: $PROFILE" >&2
        usage >&2
        exit 1
        ;;
esac

printf '\nAll phases complete. Render log: %s\n' "$LOG_PATH"
