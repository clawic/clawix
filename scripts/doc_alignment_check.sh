#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

fail() {
  echo "doc alignment failed: $*" >&2
  FAIL=1
}

require_file() {
  [[ -f "$ROOT_DIR/$1" ]] || fail "missing $1"
}

require_snippet() {
  local file="$1"
  local snippet="$2"
  if ! grep -Fq "$snippet" "$ROOT_DIR/$file"; then
    fail "$file is missing required snippet: $snippet"
  fi
}

for file in \
  "AGENTS.md" \
  "CLAUDE.md" \
  "docs/host-ownership.md" \
  "docs/data-storage-boundary.md" \
  "docs/adr/0001-claw-framework-host-boundary.md"
do
  require_file "$file"
done

require_snippet "CLAUDE.md" "AGENTS.md"
require_snippet "CLAUDE.md" "docs/host-ownership.md"
require_snippet "CLAUDE.md" "docs/data-storage-boundary.md"
require_snippet "CLAUDE.md" "docs/adr/0001-claw-framework-host-boundary.md"

for snippet in \
  "~/Library/Application Support/Claw" \
  ".claw/" \
  "ClawHostKit" \
  "Claw.app" \
  "\`claw\` is the single public CLI" \
  "~/.codex"
do
  require_snippet "docs/host-ownership.md" "$snippet"
done

for snippet in \
  "claw.sqlite" \
  "productivity.sqlite" \
  "vault.sqlite" \
  "runtime.sqlite" \
  "search.sqlite" \
  "Plaintext secrets never live"
do
  require_snippet "docs/data-storage-boundary.md" "$snippet"
done

DOC_TARGETS=(
  "$ROOT_DIR/AGENTS.md"
  "$ROOT_DIR/CLAUDE.md"
  "$ROOT_DIR/README.md"
  "$ROOT_DIR/docs"
)

scan_forbidden() {
  local label="$1"
  local pattern="$2"
  local output
  set +e
  output="$(rg -n --fixed-strings "$pattern" "${DOC_TARGETS[@]}" 2>/dev/null)"
  local status=$?
  set -e
  if [[ "$status" -eq 0 && -n "$output" ]]; then
    fail "$label"
    echo "$output" >&2
  fi
}

scan_forbidden "stale Clawix-as-Codex-only description" "Native clients for the [\`codex\`](https://github.com/openai/codex) CLI"
scan_forbidden "stale macOS Codex-only description" "Native macOS client (SwiftUI) for the \`codex\` CLI"
scan_forbidden "stale framework storage root" "~/Library/Application Support/Clawix/clawjs"

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "doc alignment passed"
