#!/usr/bin/env bash
set -euo pipefail

REQUIRED=0
if [[ "${1:-}" == "--required" ]]; then
    REQUIRED=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WEB_PKG="$PROJECT_DIR/../web"
WEB_DIST_SRC="$WEB_PKG/dist"
WEB_DIST_DEST="$PROJECT_DIR/Helpers/Bridged/Sources/clawix-bridge/Resources/web-dist"

skip_or_fail() {
    local message="$1"
    if [[ "$REQUIRED" == "1" ]]; then
        echo "ERROR: $message" >&2
        exit 1
    fi
    echo "WARN: $message" >&2
    exit 0
}

[[ -f "$WEB_PKG/package.json" ]] || skip_or_fail "web package not found at $WEB_PKG"
command -v node >/dev/null 2>&1 || skip_or_fail "node is required to build the web SPA"
command -v pnpm >/dev/null 2>&1 || skip_or_fail "pnpm is required to build the web SPA"

echo "==> Building clawix/web/ SPA"
if ! (cd "$WEB_PKG" && pnpm install --silent --frozen-lockfile && pnpm --silent build); then
    skip_or_fail "web SPA build failed"
fi

[[ -d "$WEB_DIST_SRC" ]] || skip_or_fail "web SPA build did not produce $WEB_DIST_SRC"

mkdir -p "$WEB_DIST_DEST"
rsync -a --delete "$WEB_DIST_SRC/" "$WEB_DIST_DEST/"
: > "$WEB_DIST_DEST/.gitkeep"
echo "==> Staged web SPA bundle at $WEB_DIST_DEST"
