#!/bin/sh
# Drop a built clawjs-bridged tarball into a Clawix.app bundle so the
# Mac app can switch its BackgroundBridgeService over to the Node
# daemon. The legacy Swift `clawix-bridge` helper stays untouched
# under Contents/Helpers/clawix-bridge so the cutover is reversible.
#
# Usage:
#   scripts/bundle_clawjs_bridged.sh \
#     --app /path/to/Clawix.app \
#     --tarball ../../bridge/out/clawjs-bridged-darwin-arm64-0.1.0.tar.gz
#
#   scripts/bundle_clawjs_bridged.sh \
#     --app build/Clawix.app          # auto-pick tarball for the host arch
#
# Resulting layout:
#   Clawix.app/Contents/Helpers/clawjs-bridged/
#     bin/clawjs-bridged
#     lib/start.cjs
#     node_modules/...
#     package.json
#
# Signing: this script does NOT codesign. dev.sh / build_app.sh own
# the deep sign step; run them after bundling so the embedded daemon
# inherits the stable identity.
set -eu

app=""
tarball=""

while [ $# -gt 0 ]; do
  case "$1" in
    --app) app="$2"; shift 2;;
    --tarball) tarball="$2"; shift 2;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

if [ -z "$app" ]; then
  echo "missing --app" >&2
  exit 1
fi

if [ ! -d "$app/Contents" ]; then
  echo "not a .app bundle: $app" >&2
  exit 1
fi

if [ -z "$tarball" ]; then
  arch="$(uname -m)"
  case "$arch" in
    arm64|aarch64) arch="arm64";;
    x86_64|amd64)  arch="x64";;
  esac
  bridge_out="$(cd "$(dirname "$0")/../../bridge/out" 2>/dev/null && pwd || true)"
  if [ -z "$bridge_out" ]; then
    echo "no --tarball passed and bridge/out/ not found" >&2
    exit 1
  fi
  tarball="$(ls -1t "$bridge_out"/clawjs-bridged-darwin-${arch}-*.tar.gz 2>/dev/null | head -1 || true)"
  if [ -z "$tarball" ]; then
    echo "no tarball found in $bridge_out for darwin-$arch" >&2
    echo "run: cd ../bridge && bash scripts/build-tarball.sh --target darwin-$arch" >&2
    exit 1
  fi
fi

if [ ! -f "$tarball" ]; then
  echo "tarball not found: $tarball" >&2
  exit 1
fi

helpers="$app/Contents/Helpers"
target="$helpers/clawjs-bridged"

mkdir -p "$helpers"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "[bundle] extracting $(basename "$tarball")"
tar -xzf "$tarball" -C "$tmp"
entry="$(ls -d "$tmp"/clawjs-bridged-* 2>/dev/null | head -1)"
if [ -z "$entry" ]; then
  echo "tarball did not contain clawjs-bridged-*/ entry" >&2
  exit 1
fi

if [ -d "$target" ]; then
  rm -rf "$target.prev"
  mv "$target" "$target.prev"
fi
mv "$entry" "$target"
rm -rf "$target.prev"

chmod +x "$target/bin/clawjs-bridged"

echo "[bundle] wrote $target"
echo "[bundle] next: re-run codesign (deep) on $app so the embedded daemon inherits the identity"
echo "[bundle] then flip BackgroundBridgeService.swift to launch Helpers/clawjs-bridged/bin/clawjs-bridged"
