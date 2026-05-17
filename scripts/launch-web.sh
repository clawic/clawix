#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-dev}" in
  dev)
    cd "$ROOT_DIR/web"
    exec pnpm dev
    ;;
  embedded)
    cd "$ROOT_DIR"
    pnpm --dir web build
    exec bash macos/scripts/dev.sh
    ;;
  *)
    echo "usage: scripts/launch-web.sh [dev|embedded]" >&2
    exit 64
    ;;
esac
