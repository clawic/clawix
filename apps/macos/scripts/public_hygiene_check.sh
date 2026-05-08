#!/usr/bin/env bash
# Pre-publish hygiene gate for the Clawix monorepo.
#
# Scans the repo root plus every app under apps/* for things that must
# never reach the public release: developer-machine paths, secret-looking
# literals, hard-coded codesign material, and committed signing config.
#
# Lives inside apps/macos/scripts/. It scans the whole repo, so adding
# apps/ios/ later does not need a second copy: the loop over apps/*/
# picks up the new tree automatically.
#
# Run from any host with `ripgrep`. Exit 0 means clean.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"      # apps/macos
APPS_DIR="$(dirname "$PROJECT_DIR")"        # apps
ROOT_DIR="$(dirname "$APPS_DIR")"           # repo root

FAIL=0

COMMON_GLOBS=(
  --glob '!**/.build/**'
  --glob '!**/build/**'
  --glob '!**/artifacts/**'
  --glob '!**/node_modules/**'
  --glob '!**/Package.resolved'
  --glob '!**/*.icns'
  --glob '!**/scripts/public_hygiene_check.sh'
)

scan() {
  local label="$1"
  local pattern="$2"
  shift 2
  local output
  set +e
  output="$(rg -n "${COMMON_GLOBS[@]}" "$pattern" "$@" 2>/dev/null)"
  local status=$?
  set -e
  if [[ "$status" -eq 0 && -n "$output" ]]; then
    echo "public hygiene failed: $label" >&2
    echo "$output" >&2
    FAIL=1
  fi
}

TARGETS=()
for t in \
  "$ROOT_DIR/CLAUDE.md" \
  "$ROOT_DIR/AGENTS.md" \
  "$ROOT_DIR/README.md"
do
  [[ -e "$t" ]] && TARGETS+=("$t")
done

if [[ -d "$APPS_DIR" ]]; then
  for app in "$APPS_DIR"/*/ ; do
    [[ -d "$app" ]] || continue
    for sub in Package.swift Sources Resources scripts Helpers ; do
      candidate="${app%/}/$sub"
      [[ -e "$candidate" ]] && TARGETS+=("$candidate")
    done
  done
fi

# Top-level npm CLI package: ships to npmjs.com under the public name
# `clawix`, so its source tree is part of the public publish surface
# and must pass the same blacklist scan as the native code.
if [[ -d "$ROOT_DIR/cli" ]]; then
  TARGETS+=("$ROOT_DIR/cli")
fi

# Developer-machine absolute paths almost always come from a personal
# checkout. The placeholder /Users/me/code/foo used in UI copy is allowed
# because it is generic.
scan "developer-machine paths" \
  '/Users/(?!me/code/foo\b)[A-Za-z0-9._-]+/' \
  "${TARGETS[@]}"

scan "secret-looking literals" \
  'sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]+PRIVATE KEY-----' \
  "${TARGETS[@]}"

scan "hex digests" \
  '\b[a-f0-9]{40,64}\b' \
  "${TARGETS[@]}"

scan "hard-coded codesign identity" \
  'Apple Development:|Apple Distribution:|Developer ID Application:' \
  "${TARGETS[@]}"

scan "apple team ids beside codesign markers" \
  '(DEVELOPMENT_TEAM|TEAM_ID)[^A-Z0-9]*[A-Z0-9]{10}' \
  "${TARGETS[@]}"

if compgen -G "$ROOT_DIR/*-[A-Za-z0-9_-]??????[A-Za-z0-9_-]*.js" > /dev/null; then
  echo "public hygiene failed: vendored hashed JS bundles at repo root" >&2
  ls "$ROOT_DIR"/*-*.js 2>/dev/null >&2 || true
  FAIL=1
fi

# Maintainer signing config (.signing.env*) must never end up inside the
# public repo. .signing.env.example is allowed as a reference template.
SIGNING_LEAK="$(find "$ROOT_DIR" -type f \
    \( -name '.signing.env' -o -name '.signing.env.local' \) \
    -not -path "$ROOT_DIR/.git/*" 2>/dev/null || true)"
if [[ -n "$SIGNING_LEAK" ]]; then
  echo "public hygiene failed: .signing.env inside the public repo" >&2
  echo "$SIGNING_LEAK" >&2
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "public hygiene passed"
