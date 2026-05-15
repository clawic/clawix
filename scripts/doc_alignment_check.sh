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
  "docs/decision-map.md" \
  "docs/interface-matrix.md" \
  "docs/interface-surface-clawix.registry.json" \
  "docs/naming-style-guide.md" \
  "docs/adr/0001-claw-framework-host-boundary.md" \
  "docs/adr/0002-naming-and-stability-surfaces.md" \
  "docs/adr/0004-source-file-boundaries.md" \
  "docs/adr/0007-dual-human-programmatic-surfaces.md" \
  "docs/adr/TEMPLATE.md"
do
  require_file "$file"
done

require_snippet "CLAUDE.md" "AGENTS.md"
require_snippet "CLAUDE.md" "docs/host-ownership.md"
require_snippet "CLAUDE.md" "docs/data-storage-boundary.md"
require_snippet "CLAUDE.md" "docs/decision-map.md"
require_snippet "CLAUDE.md" "docs/adr/0001-claw-framework-host-boundary.md"
require_snippet "AGENTS.md" "docs/decision-map.md"
require_snippet "AGENTS.md" "docs/adr/0004-source-file-boundaries.md"
require_snippet "CONSTITUTION.md" "Capabilities are complete only when dual-surfaced"
require_snippet "docs/adr/TEMPLATE.md" "## Surface Parity"
require_snippet "docs/adr/0007-dual-human-programmatic-surfaces.md" "MCP is the model-native surface"
require_snippet "docs/interface-matrix.md" "This matrix is the Clawix gate for ADR 0007"
require_snippet "docs/interface-matrix.md" "Every current surface must be one of"
require_snippet "docs/interface-matrix.md" "EXTERNAL PENDING"
require_snippet "CONTRIBUTING.md" "docs/decision-map.md"
require_snippet "STANDARDS.md" "docs/decision-map.md"
require_snippet "playbooks/README.md" "docs/decision-map.md"

for snippet in \
  "decision -> document" \
  "ClawJS/Claw owns framework contracts" \
  "New workspace-local framework writes use \`.claw/\`" \
  "Sensitive native permissions" \
  "Source file boundaries" \
  "PENDING GUARDRAIL"
do
  require_snippet "docs/decision-map.md" "$snippet"
done

for snippet in \
  "Status: accepted" \
  "\`1200-2000\` lines" \
  "\`>2000\` lines" \
  "Clawix app views split root layout" \
  "scripts/source-size-check.mjs" \
  "docs/source-size-baseline.json"
do
  require_snippet "docs/adr/0004-source-file-boundaries.md" "$snippet"
done

for snippet in \
  "~/.claw" \
  "~/.clawix" \
  ".claw/" \
  "retired pre-public path" \
  "ClawHostKit" \
  "Claw.app" \
  "\`claw\` is the single public CLI" \
  "~/.codex"
do
  require_snippet "docs/host-ownership.md" "$snippet"
done

for snippet in \
  "core.sqlite" \
  "productivity.sqlite" \
  "vault.sqlite" \
  "runtime.sqlite" \
  "search.sqlite" \
  "Plaintext secrets never live"
do
  require_snippet "docs/data-storage-boundary.md" "$snippet"
done

for snippet in \
  "Clawix host env vars use \`CLAWIX_*\`" \
  "The bridge service is \`clawix-bridge\`" \
  "The stable bridge port is \`24080\`" \
  "Use \`sessionId\`, not stable \`chatId\`" \
  "Clawix operational home is \`~/.clawix/\`"
do
  require_snippet "docs/naming-style-guide.md" "$snippet"
done

for snippet in \
  "Status: accepted" \
  "The host bridge service is named \`clawix-bridge\`" \
  "\`24080\` is the stable Clawix host/bridge entrypoint" \
  "Protocol documents and new frames use \`sessionId\`, not \`chatId\`" \
  "Real bundle IDs, Team IDs, signing identities, SKUs, release credentials"
do
  require_snippet "docs/adr/0002-naming-and-stability-surfaces.md" "$snippet"
done

DOC_TARGETS=(
  "$ROOT_DIR/AGENTS.md"
  "$ROOT_DIR/CLAUDE.md"
  "$ROOT_DIR/README.md"
  "$ROOT_DIR/docs"
)

CLI_TARGETS=(
  "$ROOT_DIR/cli/bin"
  "$ROOT_DIR/cli/lib"
  "$ROOT_DIR/cli/README.md"
)

APP_SURFACE_TARGETS=(
  "$ROOT_DIR/macos/Sources/Clawix/ClawJS"
  "$ROOT_DIR/macos/Sources/Clawix/Marketplace"
  "$ROOT_DIR/macos/Sources/Clawix/Settings/IdentitySettingsPage.swift"
  "$ROOT_DIR/macos/Sources/Clawix/AppState.swift"
  "$ROOT_DIR/macos/Sources/Clawix/Telegram"
  "$ROOT_DIR/macos/Sources/Clawix/Memory/MemorySettingsView.swift"
  "$ROOT_DIR/macos/scripts/bundle_clawjs.sh"
)

scan_forbidden() {
  local label="$1"
  local pattern="$2"
  local output
  set +e
  output="$(rg -n --fixed-strings --glob '!persistent-surface-clawix.manifest.json' "$pattern" "${DOC_TARGETS[@]}" 2>/dev/null)"
  local status=$?
  set -e
  if [[ "$status" -eq 0 && -n "$output" ]]; then
    fail "$label"
    echo "$output" >&2
  fi
}

scan_forbidden_file() {
  local file="$1"
  local label="$2"
  local pattern="$3"
  local output
  set +e
  output="$(rg -n --fixed-strings "$pattern" "$ROOT_DIR/$file" 2>/dev/null)"
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
scan_forbidden "stale framework global root" "~/Library/Application Support/Claw"
scan_forbidden "stale main database name" "claw.sqlite"
scan_forbidden_file "AGENTS.md" "stale helper binary name in agent instructions" "clawix-bridged"
scan_forbidden_file "AGENTS.md" "stale bridged env prefix in agent instructions" "CLAWIX_BRIDGED"

for pattern in \
  "clawix mesh" \
  "clawix devices" \
  "clawix scenes" \
  "clawix automations" \
  "clawix homes" \
  "clawix areas" \
  "clawix approvals" \
  "clawix mp" \
  "/v1/mp" \
  "@clawjs/mp" \
  "mp/1.0.0"
do
  output="$(rg -n --fixed-strings "$pattern" "${CLI_TARGETS[@]}" 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    fail "retired Clawix CLI domain/framework surface: $pattern"
    echo "$output" >&2
  fi
done

for pattern in \
  "7790" \
  "7791" \
  "7792" \
  "7793" \
  "7794" \
  "7795" \
  "7796" \
  "7797" \
  "7798" \
  "22011" \
  "BADGER_" \
  "CLAWJS_TELEGRAM_PORT" \
  "/v1/mp" \
  "@clawjs/mp" \
  "clawjs-mp" \
  "mp/1.0.0" \
  "mp/2.0.0"
do
  output="$(rg -n --fixed-strings "$pattern" "${APP_SURFACE_TARGETS[@]}" 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    fail "retired Clawix app service surface: $pattern"
    echo "$output" >&2
  fi
done

if ! node "$ROOT_DIR/scripts/interface_surface_guard.mjs"; then
  fail "interface surface guard failed"
fi

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "doc alignment passed"
