#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const content = read(relativePath);
  if (!content) return null;
  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function scanPublicText(value, label) {
  if (/\/Users\/|~\/|file:\/\/|[A-Z]:\\|BEGIN [A-Z ]*PRIVATE KEY|\bAKIA[0-9A-Z]{16}\b|\bsk-[A-Za-z0-9]{20,}\b|CLAWIX_UI_PRIVATE_[A-Z_]+_ROOT/.test(value)) {
    fail(`${label} must not contain private roots, local paths, or secret-like tokens`);
  }
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function hasWorkflowNodeRun(workflowSource, script) {
  return new RegExp(`^\\s*run:\\s+node\\s+${escapeRegExp(script)}\\s*$`, "m").test(workflowSource);
}

function hasTestScriptNodeRun(testScriptSource, script) {
  return new RegExp(`^\\s*run\\s+node\\s+"\\$ROOT_DIR/${escapeRegExp(script)}"\\s*$`, "m").test(testScriptSource);
}

const manifestPath = "docs/ui/gate-surface.manifest.json";
const manifest = readJson(manifestPath);
const privateVisualValidationPath = "docs/ui/private-visual-validation.manifest.json";
const privateVisualValidation = readJson(privateVisualValidationPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "localTestScript",
  "publicWorkflow",
  "requiredLanes",
  "releaseLaneRequires",
  "publicCiStrategy",
  "requiredPublicCheckScripts",
  "publicCheckCoverage",
  "privateEvidenceCommand",
  "externalPendingExitCode",
]);

if (manifest?.externalPendingExitCode !== 2) {
  fail(`${manifestPath}.externalPendingExitCode must be 2`);
}
if (!String(manifest?.privateEvidenceCommand || "").includes("scripts/ui_private_visual_verify.mjs --require-approved")) {
  fail(`${manifestPath}.privateEvidenceCommand must require the aggregate private visual verifier`);
}
if (manifest?.privateEvidenceCommand !== privateVisualValidation?.verificationCommand) {
  fail(`${manifestPath}.privateEvidenceCommand must match ${privateVisualValidationPath}.verificationCommand`);
}
for (const rootEnv of requireArray(privateVisualValidation, privateVisualValidationPath, "requiredRoots")) {
  if (!String(manifest?.privateEvidenceCommand || "").includes(rootEnv)) {
    fail(`${manifestPath}.privateEvidenceCommand must include ${rootEnv}`);
  }
}

const testScript = read(manifest?.localTestScript || "scripts/test.sh");
const workflow = read(manifest?.publicWorkflow || ".github/workflows/ui-governance.yml");
const config = readJson("docs/ui/interface-governance.config.json");
scanPublicText(testScript, manifest?.localTestScript || "scripts/test.sh");
scanPublicText(workflow, manifest?.publicWorkflow || ".github/workflows/ui-governance.yml");

const publicCiStrategy = manifest?.publicCiStrategy || {};
requireFields(publicCiStrategy, `${manifestPath}.publicCiStrategy`, [
  "job",
  "validates",
  "forbidsPrivateRoots",
  "privateEvidenceMode",
]);
if (!workflow.includes(`${publicCiStrategy.job}:`)) {
  fail(`${manifest.publicWorkflow} must define ${publicCiStrategy.job}`);
}
const publicCiValidates = new Set(requireArray(publicCiStrategy, `${manifestPath}.publicCiStrategy`, "validates"));
for (const required of ["lints", "geometry", "manifests"]) {
  if (!publicCiValidates.has(required)) fail(`${manifestPath}.publicCiStrategy.validates must include ${required}`);
}
if (!publicCiValidates.has("visual-diff")) {
  fail(`${manifestPath}.publicCiStrategy.validates must include visual-diff`);
}
if (publicCiStrategy.forbidsPrivateRoots !== true) {
  fail(`${manifestPath}.publicCiStrategy.forbidsPrivateRoots must be true`);
}
if (publicCiStrategy.diffBaseEnv !== "CLAWIX_UI_GUARD_DIFF_BASE") {
  fail(`${manifestPath}.publicCiStrategy.diffBaseEnv must be CLAWIX_UI_GUARD_DIFF_BASE`);
}
const diffBaseConsumers = new Set(
  requireArray(publicCiStrategy, `${manifestPath}.publicCiStrategy`, "diffBaseConsumers"),
);
for (const script of ["scripts/ui_governance_guard.mjs", "scripts/ui_pattern_mutation_guard.mjs"]) {
  if (!diffBaseConsumers.has(script)) {
    fail(`${manifestPath}.publicCiStrategy.diffBaseConsumers must include ${script}`);
  }
  const source = read(script);
  if (!source.includes(publicCiStrategy.diffBaseEnv)) {
    fail(`${script} must consume ${publicCiStrategy.diffBaseEnv}`);
  }
}
if (publicCiStrategy.privateEvidenceMode !== "external-pending-contract") {
  fail(`${manifestPath}.publicCiStrategy.privateEvidenceMode must be external-pending-contract`);
}
if (/CLAWIX_UI_PRIVATE_[A-Z_]+_ROOT/.test(workflow)) {
  fail(`${manifest.publicWorkflow} must not require private evidence roots`);
}
for (const snippet of [
  "fetch-depth: 0",
  "CLAWIX_UI_GUARD_DIFF_BASE",
  "github.event.pull_request.base.sha",
  "github.event.before",
]) {
  if (!workflow.includes(snippet)) fail(`${manifest.publicWorkflow} must wire UI visual diff base: ${snippet}`);
}

const lanes = new Set(requireArray(manifest, manifestPath, "requiredLanes"));
for (const lane of ["fast", "changed", "release"]) {
  if (!lanes.has(lane)) fail(`${manifestPath}.requiredLanes must include ${lane}`);
  if (!new RegExp(`\\n\\s*${lane}\\)`).test(testScript)) fail(`${manifest.localTestScript} must expose ${lane} lane`);
}

const releaseRequires = new Set(requireArray(manifest, manifestPath, "releaseLaneRequires"));
for (const required of ["integration", "e2e", "device", "host"]) {
  if (!releaseRequires.has(required)) fail(`${manifestPath}.releaseLaneRequires must include ${required}`);
}
for (const snippet of ['integration "$@"', "e2e_tests", "device_tests", "host_tests"]) {
  if (!testScript.includes(snippet)) fail(`${manifest.localTestScript} release lane must include ${snippet}`);
}

const configChecks = new Set(requireArray(config, "docs/ui/interface-governance.config.json", "publicChecks"));
if (!configChecks.has("release-gate-contract-check")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include release-gate-contract-check");
}
if (!configChecks.has("pattern-visual-mutation-guard")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include pattern-visual-mutation-guard");
}
const requiredPublicCheckScripts = new Set(requireArray(manifest, manifestPath, "requiredPublicCheckScripts"));
const publicCheckCoverage = manifest?.publicCheckCoverage || {};
if (!publicCheckCoverage || typeof publicCheckCoverage !== "object" || Array.isArray(publicCheckCoverage)) {
  fail(`${manifestPath}.publicCheckCoverage must be an object`);
}
for (const checkId of configChecks) {
  const scripts = publicCheckCoverage?.[checkId];
  if (!Array.isArray(scripts) || scripts.length === 0) {
    fail(`${manifestPath}.publicCheckCoverage must map ${checkId} to at least one public script`);
    continue;
  }
  for (const script of scripts) {
    if (!requiredPublicCheckScripts.has(script)) {
      fail(`${manifestPath}.publicCheckCoverage.${checkId} references script not listed in requiredPublicCheckScripts: ${script}`);
    }
  }
}
for (const checkId of Object.keys(publicCheckCoverage || {})) {
  if (!configChecks.has(checkId)) {
    fail(`${manifestPath}.publicCheckCoverage contains undeclared public check ${checkId}`);
  }
}
const coveredPublicCheckScripts = new Set(Object.values(publicCheckCoverage || {}).flat());
for (const script of requiredPublicCheckScripts) {
  if (!coveredPublicCheckScripts.has(script)) {
    fail(`${manifestPath}.publicCheckCoverage must cover required public script ${script}`);
  }
}

for (const script of requireArray(manifest, manifestPath, "requiredPublicCheckScripts")) {
  if (typeof script !== "string" || !script.startsWith("scripts/") || script.includes("..")) {
    fail(`${manifestPath}.requiredPublicCheckScripts entries must be repo-relative scripts`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, script))) fail(`missing ${script}`);
  if (!hasTestScriptNodeRun(testScript, script)) {
    fail(`${manifest.localTestScript} must run ${script}`);
  }
  if (!hasWorkflowNodeRun(workflow, script)) {
    fail(`${manifest.publicWorkflow} must run ${script}`);
  }
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI release gate check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI release gate check passed (${manifest.requiredPublicCheckScripts.length} public scripts, ${configChecks.size} public checks)`);
