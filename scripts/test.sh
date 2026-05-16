#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE="${1:-fast}"
shift || true
SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clawix-test.XXXXXX")"
trap 'rm -rf "$SCRATCH_ROOT"' EXIT
export CLANG_MODULE_CACHE_PATH="$SCRATCH_ROOT/clang-module-cache"

run() {
  echo "+ $*" >&2
  "$@"
}

policy_guard() {
  for required in \
    "$ROOT_DIR/docs/adr/0003-testing-architecture.md" \
    "$ROOT_DIR/docs/adr/0005-integration-qa-lab.md" \
    "$ROOT_DIR/docs/adr/0007-dual-human-programmatic-surfaces.md" \
    "$ROOT_DIR/docs/adr/TEMPLATE.md" \
    "$ROOT_DIR/playbooks/testing.md" \
    "$ROOT_DIR/playbooks/testing-matrix.md" \
    "$ROOT_DIR/qa/coverage-budgets.json" \
    "$ROOT_DIR/qa/quarantine.json" \
    "$ROOT_DIR/qa/scenarios/external-pending.md" \
    "$ROOT_DIR/qa/scenarios/signed-host-validation.md" \
    "$ROOT_DIR/qa/scenarios/telegram-integration-qa-lab.md"
  do
    if [[ ! -e "$required" ]]; then
      echo "testing policy failed: missing ${required#$ROOT_DIR/}" >&2
      exit 1
    fi
  done

  for lane_root in fast integration e2e host device fixtures live; do
    if [[ ! -d "$ROOT_DIR/tests/$lane_root" ]]; then
      echo "testing policy failed: missing tests/$lane_root" >&2
      exit 1
    fi
  done

  for ignored in 'test-results/' 'artifacts/' 'coverage/' '.tmp/'; do
    if ! grep -Fqx "$ignored" "$ROOT_DIR/.gitignore"; then
      echo "testing policy failed: .gitignore must include $ignored" >&2
      exit 1
    fi
  done

  node - "$ROOT_DIR/qa/quarantine.json" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const today = new Date().toISOString().slice(0, 10);
const quarantine = JSON.parse(fs.readFileSync(file, "utf8"));
if (!Array.isArray(quarantine.entries)) {
  console.error("testing policy failed: qa/quarantine.json must contain entries");
  process.exit(1);
}
for (const entry of quarantine.entries) {
  for (const field of ["id", "owner", "reason", "repair", "expires"]) {
    if (!entry[field]) {
      console.error(`testing policy failed: quarantine entry is missing ${field}`);
      process.exit(1);
    }
  }
  if (entry.expires < today) {
    console.error(`testing policy failed: quarantine entry ${entry.id} expired on ${entry.expires}`);
    process.exit(1);
  }
}
console.error("testing policy passed");
NODE

  node - "$ROOT_DIR/qa/coverage-budgets.json" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const requiredBoundaries = [
  "swift-logic-packages",
  "web-surface",
  "bridge-protocol",
  "daemon-and-local-bridge",
  "macos-host-app",
  "device-clients",
  "live-integrations",
  "connector-qa-display-approval",
];
const budgets = JSON.parse(fs.readFileSync(file, "utf8"));
if (!Array.isArray(budgets.budgets)) {
  console.error("testing policy failed: qa/coverage-budgets.json must contain budgets");
  process.exit(1);
}
const seen = new Set();
for (const budget of budgets.budgets) {
  for (const field of ["boundary", "lane", "metric", "minimum"]) {
    if (budget[field] === undefined || budget[field] === "") {
      console.error(`testing policy failed: coverage budget is missing ${field}`);
      process.exit(1);
    }
  }
  if (typeof budget.minimum !== "number" || budget.minimum < 0) {
    console.error(`testing policy failed: invalid coverage minimum for ${budget.boundary || "<unknown>"}`);
    process.exit(1);
  }
  seen.add(budget.boundary);
}
for (const boundary of requiredBoundaries) {
  if (!seen.has(boundary)) {
    console.error(`testing policy failed: missing coverage budget boundary ${boundary}`);
    process.exit(1);
  }
}
NODE
}

swift_package_tests() {
  local package
  for package in "$@"; do
    [[ -f "$package/Package.swift" ]] || continue
    [[ -d "$package/Tests" ]] || continue
    run swift test --disable-sandbox --package-path "$package" --scratch-path "$SCRATCH_ROOT/$(basename "$package")"
  done
}

fast_swift_packages() {
  printf '%s\n' \
    "$ROOT_DIR/packages/AIProviders" \
    "$ROOT_DIR/packages/ClawixArgon2" \
    "$ROOT_DIR/packages/ClawixCore" \
    "$ROOT_DIR/packages/SecretsModels" \
    "$ROOT_DIR/packages/SecretsProxyCore"
}

integration_swift_packages() {
  printf '%s\n' \
    "$ROOT_DIR/packages/SecretsCrypto" \
    "$ROOT_DIR/packages/SecretsPersistence" \
    "$ROOT_DIR/packages/SecretsVault" \
    "$ROOT_DIR/packages/ClawixEngine" \
    "$ROOT_DIR/macos"
}

web_tests() {
  if [[ -d "$ROOT_DIR/web/node_modules" ]]; then
    run npm --prefix "$ROOT_DIR/web" test -- "$@"
  else
    echo "PARTIAL web tests skipped: web/node_modules is not installed" >&2
  fi
}

android_unit_tests() {
  if [[ -x "$ROOT_DIR/android/gradlew" ]]; then
    run "$ROOT_DIR/android/gradlew" -p "$ROOT_DIR/android" testDebugUnitTest
  else
    echo "PARTIAL Android unit tests skipped: Gradle wrapper is not executable" >&2
  fi
}

bridge_fixture_tests() {
  run python3 "$ROOT_DIR/macos/scripts/compile_xcstrings.py"
  run bash "$ROOT_DIR/macos/scripts/e2e_validate.sh"
}

e2e_tests() {
  bridge_fixture_tests
}

host_tests() {
  if [[ -n "${CLAWIX_HOST_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_HOST_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING host lane: set CLAWIX_HOST_TEST_COMMAND for signed-host validation" >&2
  fi
}

device_tests() {
  android_unit_tests
  if [[ -n "${CLAWIX_DEVICE_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_DEVICE_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING device lane: set CLAWIX_DEVICE_TEST_COMMAND for simulator/device validation" >&2
  fi
}

live_tests() {
  if [[ "${CLAWIX_TEST_LIVE:-}" != "1" ]]; then
    echo "CLAWIX_TEST_LIVE=1 is required for the live lane." >&2
    exit 2
  fi
  if [[ -n "${CLAWIX_LIVE_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_LIVE_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING live lane: set CLAWIX_LIVE_TEST_COMMAND for approved live validation" >&2
  fi
}

fast() {
  run bash "$ROOT_DIR/macos/scripts/public_hygiene_check.sh"
  run node "$ROOT_DIR/scripts/tracked-ignored-check.mjs"
  run node "$ROOT_DIR/scripts/check-clawjs-skills-sync.mjs"
  run node "$ROOT_DIR/scripts/ui_governance_guard.mjs"
  run node "$ROOT_DIR/scripts/ui_geometry_contract_check.mjs"
  run node "$ROOT_DIR/scripts/ui_rendered_geometry_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/ui_copy_governance_check.mjs"
  run node "$ROOT_DIR/scripts/ui_component_extraction_check.mjs"
  run node "$ROOT_DIR/scripts/ui_visual_scope_check.mjs"
  run node "$ROOT_DIR/scripts/ui_surface_inventory_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_baseline_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/naming-shape-check.mjs"
  run node "$ROOT_DIR/scripts/source-size-check.mjs"
  run node "$ROOT_DIR/scripts/code-hygiene-check.mjs"
  run node "$ROOT_DIR/scripts/code-hygiene-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/codebase-manifest.mjs" --check
  run node "$ROOT_DIR/scripts/package_surface_guard.mjs"
  policy_guard
  mapfile -t packages < <(fast_swift_packages)
  swift_package_tests "${packages[@]}"
  web_tests "$@"
}

integration() {
  fast "$@"
  run python3 "$ROOT_DIR/macos/scripts/compile_xcstrings.py"
  mapfile -t packages < <(integration_swift_packages)
  swift_package_tests "${packages[@]}"
}

changed() {
  local base
  base="$(git -C "$ROOT_DIR" merge-base HEAD origin/main 2>/dev/null || true)"
  [[ -n "$base" ]] || base="HEAD~1"

  local changed_files
  changed_files="$(git -C "$ROOT_DIR" diff --name-only "$base" -- 2>/dev/null || true)"
  if [[ -z "$changed_files" ]]; then
    fast "$@"
    return
  fi

  if grep -Eq '^(macos/Helpers|macos/scripts/e2e_|packages/(SecretsCrypto|SecretsPersistence|SecretsVault|ClawixEngine)|macos/)' <<< "$changed_files"; then
    integration "$@"
    return
  fi

  fast "$@"
}

case "$LANE" in
  fast)
    fast "$@"
    ;;
  changed)
    changed "$@"
    ;;
  integration)
    integration "$@"
    ;;
  e2e)
    e2e_tests
    ;;
  host)
    host_tests
    ;;
  device)
    device_tests
    ;;
  live)
    live_tests
    ;;
  release)
    integration "$@"
    e2e_tests
    device_tests
    host_tests
    ;;
  *)
    echo "Unknown test lane: $LANE" >&2
    exit 2
    ;;
esac
