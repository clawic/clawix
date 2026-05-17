#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ARG="${1:-"$ROOT/docs/persistent-surface-clawix.manifest.json"}"
if [[ "$OUT_ARG" = /* ]]; then
  OUT="$OUT_ARG"
else
  OUT="$ROOT/$OUT_ARG"
fi
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

cd "$ROOT/macos"
CLAWIX_PERSISTENT_SURFACE_MANIFEST_OUT="$TMP" \
  swift test --filter PersistentSurfaceRegistryTests/testClawixPersistentSurfaceRegistryCoversLocalDatabaseAndPrefs

node - "$TMP" "$OUT" "$ROOT/docs/persistent-surface-clawix.manifest.json" <<'NODE'
const fs = require("node:fs");
const [generatedPath, outPath, canonicalPath] = process.argv.slice(2);
const generated = JSON.parse(fs.readFileSync(generatedPath, "utf8"));
let routeGraphSource = {};
for (const candidate of [outPath, canonicalPath]) {
  if (!candidate || !fs.existsSync(candidate)) continue;
  if (fs.statSync(candidate).size === 0) continue;
  const parsed = JSON.parse(fs.readFileSync(candidate, "utf8"));
  if (Array.isArray(parsed.edges) && Array.isArray(parsed.routes)) {
    routeGraphSource = parsed;
    break;
  }
}

function normalizeContractId(contractId) {
  if (contractId === "clawix.protocol.bridge") return "clawix.protocol.bridge.v1";
  return contractId;
}

const merged = {
  nodes: generated.nodes,
  edges: (routeGraphSource.edges ?? []).map((edge) => ({
    ...edge,
    contractId: normalizeContractId(edge.contractId),
  })),
  routes: (routeGraphSource.routes ?? []).map((route) => ({
    ...route,
    steps: (route.steps ?? []).map((step) => ({
      ...step,
      contractId: normalizeContractId(step.contractId),
    })),
  })),
  version: generated.version,
};
const pretty = JSON.stringify(merged, null, 2)
  .replace(/"([^"\\]*(?:\\.[^"\\]*)*)":/g, '"$1" :');
fs.writeFileSync(outPath, `${pretty}\n`);
NODE
