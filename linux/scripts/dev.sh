#!/usr/bin/env bash
# Linux dev launcher. Mirrors `clawix/macos/scripts/dev.sh`: builds the
# bridge daemon (Swift), starts it under systemd-run --user, then runs
# `cargo tauri dev` against the SolidJS frontend with HMR.
#
# Invoked from the repo workspace via `bash dev.sh` when the cwd is
# `<workspace>/Linux/`. Does NOT bypass the debounce; agents should use
# `bash scripts-dev/restart-app.sh` instead.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_ROOT="$ROOT/linux"
APP_DIR="$LINUX_ROOT/app"
DAEMON_DIR="$ROOT/macos/Helpers/Bridged"

if ! command -v swift >/dev/null 2>&1; then
  echo "[dev] swift toolchain not found; install swift 5.10 or later" >&2
  exit 78
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "[dev] cargo not found; install Rust toolchain (rustup)" >&2
  exit 78
fi

# 1) Build the daemon (debug, fast iteration)
echo "[dev] building clawix-bridged…"
( cd "$DAEMON_DIR" && swift build )
DAEMON_BIN="$DAEMON_DIR/.build/debug/clawix-bridged"

# 2) Make sure the systemd unit points at the freshly built binary by
#    forcing an env var override (the GUI's service_manager honours
#    CLAWIX_BRIDGE_BIN).
export CLAWIX_BRIDGE_BIN="$DAEMON_BIN"

# 3) Tauri dev. Plays the same role as the Mac dev launcher: spawns the
#    SolidJS Vite server and the GTK webview wrapper.
echo "[dev] launching Tauri dev (frontend + shell)…"
( cd "$APP_DIR" && npm install --silent && npx tauri dev )
