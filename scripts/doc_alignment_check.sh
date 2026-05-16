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
  "docs/agentic-naming-guide.md" \
  "docs/naming-shape-audit.md" \
  "docs/vocabulary.md" \
  "docs/vocabulary.registry.json" \
  "docs/adr/0001-claw-framework-host-boundary.md" \
  "docs/adr/0002-naming-and-stability-surfaces.md" \
  "docs/adr/0004-source-file-boundaries.md" \
  "docs/adr/0009-agentic-naming-and-code-structure.md" \
  "docs/adr/0007-dual-human-programmatic-surfaces.md" \
  "docs/adr/0010-interface-governance.md" \
  "docs/adr/TEMPLATE.md" \
  "docs/ui/README.md" \
  "docs/ui/decision-verification.json" \
  "docs/ui/interface-governance.config.json" \
  "docs/ui/implementation-evidence.manifest.json" \
  "docs/ui/state-coverage.manifest.json" \
  "docs/ui/visual-model-allowlist.manifest.json" \
  "docs/ui/component-extraction.manifest.json" \
  "docs/ui/mechanical-equivalence.manifest.json" \
  "docs/ui/visible-surfaces.inventory.json" \
  "docs/ui/copy.inventory.json" \
  "docs/ui/rendered-geometry.manifest.json" \
  "docs/ui/visual-change-scopes.manifest.json" \
  "docs/ui/visual-change-detectors.manifest.json" \
  "docs/ui/pattern-registry/patterns.registry.json" \
  "docs/ui/pattern-registry/patterns/NOTES.md" \
  "docs/ui/debt.baseline.json" \
  "docs/ui/debt-baseline.manifest.json" \
  "docs/ui/debt-report.registry.json" \
  "docs/ui/exceptions.registry.json" \
  "docs/ui/protected-surfaces.registry.json" \
  "docs/ui/canon-promotions.registry.json" \
  "docs/ui/performance-budgets.registry.json" \
  "docs/ui/private-baselines.manifest.json" \
  "docs/ui/private-visual-validation.manifest.json" \
  "docs/ui/visual-change-proposal.template.md" \
  "docs/ui/inspiration/references.registry.json" \
  ".github/PULL_REQUEST_TEMPLATE.md" \
  "scripts/naming-shape-check.mjs" \
  "scripts/ui_canon_promotion_check.mjs" \
  "scripts/ui_debt_report_check.mjs" \
  "scripts/ui_exception_check.mjs" \
  "scripts/ui_protected_surface_check.mjs" \
  "scripts/ui_implementation_evidence_check.mjs" \
  "scripts/ui_state_coverage_check.mjs" \
  "scripts/ui_copy_governance_check.mjs" \
  "scripts/ui_private_copy_verify.mjs" \
  "scripts/ui_performance_budget_check.mjs" \
  "scripts/ui_component_extraction_check.mjs" \
  "scripts/ui_mechanical_equivalence_check.mjs" \
  "scripts/ui_geometry_contract_check.mjs" \
  "scripts/ui_rendered_geometry_manifest_check.mjs" \
  "scripts/ui_private_geometry_verify.mjs" \
  "scripts/ui_visual_scope_check.mjs" \
  "scripts/ui_visual_detector_check.mjs" \
  "scripts/ui_visual_model_allowlist_check.mjs" \
  "scripts/ui_surface_inventory_check.mjs" \
  "scripts/ui_private_baseline_manifest_check.mjs" \
  "scripts/ui_private_baseline_verify.mjs" \
  "scripts/ui_private_visual_verify.mjs" \
  "scripts/ui_private_visual_validation_manifest_check.mjs" \
  "scripts/ui_governance_guard.mjs" \
  "scripts/storage_boundary_guard.mjs"
do
  require_file "$file"
done

require_snippet "CLAUDE.md" "AGENTS.md"
require_snippet "CLAUDE.md" "docs/host-ownership.md"
require_snippet "CLAUDE.md" "docs/data-storage-boundary.md"
require_snippet "CLAUDE.md" "docs/decision-map.md"
require_snippet "CLAUDE.md" "docs/naming-style-guide.md"
require_snippet "CLAUDE.md" "docs/agentic-naming-guide.md"
require_snippet "CLAUDE.md" "docs/vocabulary.md"
require_snippet "CLAUDE.md" "docs/adr/0001-claw-framework-host-boundary.md"
require_snippet "AGENTS.md" "docs/decision-map.md"
require_snippet "AGENTS.md" "docs/adr/0004-source-file-boundaries.md"
require_snippet "CONSTITUTION.md" "Capabilities are complete only when dual-surfaced"
require_snippet "docs/adr/TEMPLATE.md" "## Surface Parity"
require_snippet "docs/adr/0007-dual-human-programmatic-surfaces.md" "MCP is the model-native surface"
require_snippet "docs/adr/0010-interface-governance.md" "Only explicitly authorized visual lanes"
require_snippet "docs/adr/0010-interface-governance.md" "Existing visual drift is recorded"
require_snippet "docs/adr/0010-interface-governance.md" "Extract reusable components only when repeated UI carries risk"
require_snippet "docs/ui/README.md" "Only an explicitly authorized visual lane may make"
require_snippet "docs/ui/README.md" "If a guard finds visual debt outside the current authorized scope"
require_snippet "docs/ui/README.md" "scripts/ui_surface_inventory_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_canon_promotion_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_debt_report_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_exception_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_protected_surface_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_geometry_contract_check.mjs"
require_snippet "docs/ui/README.md" "implementation-evidence.manifest.json"
require_snippet "docs/ui/README.md" "scripts/ui_implementation_evidence_check.mjs"
require_snippet "docs/ui/README.md" "state-coverage.manifest.json"
require_snippet "docs/ui/README.md" "scripts/ui_state_coverage_check.mjs"
require_snippet "docs/ui/README.md" "rendered-geometry.manifest.json"
require_snippet "docs/ui/README.md" "scripts/ui_rendered_geometry_manifest_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_copy_governance_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_performance_budget_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_component_extraction_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_mechanical_equivalence_check.mjs"
require_snippet "docs/ui/README.md" "visual-change-scopes.manifest.json"
require_snippet "docs/ui/README.md" "scripts/ui_visual_scope_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_visual_detector_check.mjs"
require_snippet "docs/ui/README.md" "scripts/ui_visual_model_allowlist_check.mjs"
require_snippet "docs/ui/README.md" "private-baselines.manifest.json"
require_snippet "docs/ui/README.md" "scripts/ui_private_visual_verify.mjs"
require_snippet "docs/ui/README.md" "visual-change-proposal.template.md"
require_snippet "docs/ui/decision-verification.json" "019e2b5e-fe48-7231-8e13-49411999b001"
require_snippet "docs/ui/decision-verification.json" "critical_cleanup_owner"
require_snippet "docs/ui/visible-surfaces.inventory.json" "Every current visible UI candidate"
require_snippet "docs/ui/visible-surfaces.inventory.json" "macos-chat-and-composer"
require_snippet "docs/ui/copy.inventory.json" "private-codex-ui-copy-snapshots"
require_snippet "docs/ui/copy.inventory.json" "approvalBlockedWithoutSnapshot"
require_snippet "docs/ui/copy.inventory.json" "ui_private_copy_verify.mjs"
require_snippet "docs/ui/component-extraction.manifest.json" "unbounded-prop-bag"
require_snippet "docs/ui/component-extraction.manifest.json" "minimumCallSites"
require_snippet "docs/ui/mechanical-equivalence.manifest.json" "beforeSnapshotReference"
require_snippet "docs/ui/mechanical-equivalence.manifest.json" "private-codex-ui-mechanical-equivalence"
require_snippet "docs/ui/canon-promotions.registry.json" "Only the user can promote"
require_snippet "docs/ui/canon-promotions.registry.json" "private-codex-ui-approval"
require_snippet "docs/ui/canon-promotions.registry.json" "geometryEvidenceHash"
require_snippet "docs/ui/debt-baseline.manifest.json" "docs/ui/debt-baseline.*"
require_snippet "docs/ui/debt-baseline.manifest.json" "docs/ui/debt.baseline.json"
require_snippet "docs/ui/debt-report.registry.json" "Report only."
require_snippet "docs/ui/debt-report.registry.json" "pending-visual-authorized-cleanup"
require_snippet "docs/ui/exceptions.registry.json" "UI exceptions are temporary"
require_snippet "docs/ui/exceptions.registry.json" "expiresAt"
require_snippet "docs/ui/protected-surfaces.registry.json" "requiredFreezeFields"
require_snippet "docs/ui/protected-surfaces.registry.json" "geometryEvidenceReference"
require_snippet "docs/ui/rendered-geometry.manifest.json" "private-codex-ui-rendered-geometry"
require_snippet "docs/ui/rendered-geometry.manifest.json" "ui_private_geometry_verify.mjs"
require_snippet "docs/ui/visual-change-scopes.manifest.json" "\"defaultAuthorized\": false"
require_snippet "docs/ui/visual-change-scopes.manifest.json" "privateModelAssignment"
require_snippet "docs/ui/visual-change-scopes.manifest.json" "changeBudget"
require_snippet "docs/ui/visual-change-detectors.manifest.json" "platform-specific source tokens"
require_snippet "docs/ui/visual-change-detectors.manifest.json" "swiftui-layout"
require_snippet "docs/ui/visual-model-allowlist.manifest.json" "claude-opus-4.7"
require_snippet "docs/ui/visual-model-allowlist.manifest.json" "CLAWIX_UI_VISUAL_MODEL"
require_snippet "docs/ui/implementation-evidence.manifest.json" ".github/PULL_REQUEST_TEMPLATE.md"
require_snippet ".github/PULL_REQUEST_TEMPLATE.md" "## UI governance evidence"
require_snippet ".github/PULL_REQUEST_TEMPLATE.md" "Pattern/debt/protected/exception mapping:"
require_snippet "docs/ui/state-coverage.manifest.json" "android-domain-surfaces"
require_snippet "docs/ui/state-coverage.manifest.json" "pending-implementation-evidence"
require_snippet "docs/ui/private-baselines.manifest.json" "private-codex-ui-baselines"
require_snippet "docs/ui/private-baselines.manifest.json" "ui_private_baseline_verify.mjs"
require_snippet "docs/ui/private-baselines.manifest.json" "pending-user-approved-capture"
require_snippet "docs/ui/private-visual-validation.manifest.json" "ui_private_visual_verify.mjs"
require_snippet "docs/ui/private-visual-validation.manifest.json" "EXTERNAL PENDING"
require_snippet "docs/ui/visual-change-proposal.template.md" "Status: conceptual-only"
require_snippet "macos/PERF.md" "docs/ui/performance-budgets.registry.json"
require_snippet "skills/ui-implementation/SKILL.md" "Declare the UI governance evidence"
require_snippet "skills/ui-implementation/SKILL.md" "pattern IDs or debt/protected/exception mapping"
require_snippet "skills/ui-performance-budget/SKILL.md" "docs/ui/performance-budgets.registry.json"
require_snippet "docs/ui/pattern-registry/patterns/NOTES.md" "## sidebar-row"
require_snippet "docs/ui/pattern-registry/patterns/NOTES.md" "## terminal-surface"
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
  "docs/source-size-baseline.json" \
  "compressed enum/union/list patterns"
do
  require_snippet "docs/adr/0004-source-file-boundaries.md" "$snippet"
done

for snippet in \
  "Status: accepted" \
  "ClawJS remains canonical for shared framework vocabulary" \
  "docs/vocabulary.registry.json" \
  "scripts/naming-shape-check.mjs" \
  "Use \`session\` / \`sessionId\` in bridge"
do
  require_snippet "docs/adr/0009-agentic-naming-and-code-structure.md" "$snippet"
done

for snippet in \
  "Stable bridge, protocol, storage, cache, and framework-facing names use" \
  "Do not add new stable bridge fields such as \`chatId\`" \
  "JSON/YAML owned by Clawix"
do
  require_snippet "docs/agentic-naming-guide.md" "$snippet"
done

for snippet in \
  "\"schemaVersion\": 1" \
  "\"owner\": \"clawix\"" \
  "\"preferredTerm\": \"session\"" \
  "\"preferredTerm\": \"clawix-bridge\""
do
  require_snippet "docs/vocabulary.registry.json" "$snippet"
done

for snippet in \
  "Status: initial report" \
  "Critical naming failures: 0" \
  "Cleanup families"
do
  require_snippet "docs/naming-shape-audit.md" "$snippet"
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
  "Clawix operational home is \`~/.clawix/\`" \
  "docs/agentic-naming-guide.md"
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

if ! node "$ROOT_DIR/scripts/storage_boundary_guard.mjs"; then
  fail "storage boundary guard failed"
fi

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi

echo "doc alignment passed"
