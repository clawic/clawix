#!/usr/bin/env bash
# Pre-publish hygiene gate for the Clawix monorepo.
#
# Scans the repo root plus the native apps and shared packages for things that must
# never reach the public release: developer-machine paths, secret-looking
# literals, hard-coded codesign material, and committed signing config.
#
# Lives inside macos/scripts/. It scans the whole public release surface.
#
# Run from any host with `ripgrep`. Exit 0 means clean.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"      # macos
ROOT_DIR="$(dirname "$PROJECT_DIR")"        # repo root

FAIL=0

COMMON_GLOBS=(
  --glob '!**/.build/**'
  --glob '!**/build/**'
  --glob '!**/artifacts/**'
  --glob '!**/node_modules/**'
  --glob '!**/Package.resolved'
  --glob '!**/*.icns'
  --glob '!**/scripts/public_hygiene_check.sh'
  # Web SPA build output (pnpm --filter @clawix/web build) and the daemon's
  # mirrored copy ship with hashed filenames and minified bundles that are
  # uninteresting for hygiene scans.
  --glob '!**/web/dist/**'
  --glob '!**/Helpers/Bridged/Sources/clawix-bridged/Resources/web-dist/**'
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

for surface in "$ROOT_DIR/macos" "$ROOT_DIR/ios" "$ROOT_DIR/packages"/* ; do
  [[ -d "$surface" ]] || continue
  for sub in Package.swift project.yml Sources Resources scripts Helpers Tests ; do
      candidate="${surface%/}/$sub"
      [[ -e "$candidate" ]] && TARGETS+=("$candidate")
  done
done

# Web SPA target. Same blacklist applies (no Team ID, bundle id real,
# SKU literals, codesign identities). dist/ and node_modules/ are
# excluded above via COMMON_GLOBS so we only scan source code.
if [[ -d "$ROOT_DIR/web" ]]; then
  for sub in package.json tsconfig.json vite.config.ts tailwind.config.ts index.html src public scripts tests README.md ; do
      candidate="$ROOT_DIR/web/$sub"
      [[ -e "$candidate" ]] && TARGETS+=("$candidate")
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

check_git_metadata() {
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  local ranges=("HEAD")
  local upstream
  upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    ranges+=("$upstream..HEAD")
  fi

  local output=""
  for range in "${ranges[@]}"; do
    output+="$(
      git -C "$ROOT_DIR" log --format='%h%x09%an <%ae>%x09%cn <%ce>' "$range" 2>/dev/null \
        | awk -F'\t' '$2 ~ /@[^>]*\\.local>/ || $3 ~ /@[^>]*\\.local>/ { print }'
    )"
  done

  if [[ -n "$output" ]]; then
    echo "public hygiene failed: machine-local git identity" >&2
    echo "$output" | sort -u >&2
    FAIL=1
  fi
}

check_git_metadata

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
