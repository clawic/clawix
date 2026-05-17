#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
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
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function runEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("private evidence plan must pass before private visual validation can be verified");
    if (result.stderr) {
      for (const line of result.stderr.trim().split("\n")) fail(`private evidence plan: ${line}`);
    }
    return { counts: {} };
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { counts: {} };
  }
}

const manifestPath = "docs/ui/private-visual-validation.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "verificationCommand",
  "evidencePlanCommand",
  "requiredRoots",
  "rootAliases",
  "optionalRootAliases",
  "delegates",
  "decisionBlockers",
  "decisionBlockerEvidenceTypes",
  "externalPendingExitCode",
]);
const evidencePlan = runEvidencePlan();

if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_visual_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_visual_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private evidence`);
}
if (manifest?.evidencePlanCommand !== "node scripts/ui_private_evidence_plan_check.mjs --json") {
  fail(`${manifestPath}.evidencePlanCommand must run node scripts/ui_private_evidence_plan_check.mjs --json`);
}
if (manifest?.externalPendingExitCode !== 2) {
  fail(`${manifestPath}.externalPendingExitCode must be 2`);
}

const roots = new Set(requireArray(manifest, manifestPath, "requiredRoots"));
const expectedRoots = [
  "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "CLAWIX_UI_PRIVATE_COPY_ROOT",
  "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
  "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
];
for (const root of expectedRoots) {
  if (!roots.has(root)) fail(`${manifestPath}.requiredRoots must include ${root}`);
  if (!String(manifest?.verificationCommand || "").includes(root)) {
    fail(`${manifestPath}.verificationCommand must include ${root}`);
  }
}

const expectedAliasContracts = [
  {
    alias: "private-codex-ui-baselines",
    env: "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
    manifestPath: "docs/ui/private-baselines.manifest.json",
    manifestAliasField: "privateRootAlias",
  },
  {
    alias: "private-codex-ui-rendered-geometry",
    env: "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
    manifestPath: "docs/ui/rendered-geometry.manifest.json",
    manifestAliasField: "privateGeometryAlias",
  },
  {
    alias: "private-codex-ui-copy-snapshots",
    env: "CLAWIX_UI_PRIVATE_COPY_ROOT",
    manifestPath: "docs/ui/copy.inventory.json",
    manifestAliasField: "privateSnapshotAlias",
  },
  {
    alias: "private-codex-ui-rendered-drift",
    env: "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
    manifestPath: "docs/ui/rendered-drift.manifest.json",
    manifestAliasField: "privateDriftAlias",
  },
  {
    alias: "private-codex-ui-debt-audit",
    env: "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
    manifestPath: "docs/ui/debt-audit.manifest.json",
    manifestAliasField: "privateDebtAuditAlias",
  },
];
const expectedOptionalAliasContracts = [
  {
    alias: "private-codex-ui-approval",
    env: "CLAWIX_UI_PRIVATE_APPROVAL_ROOT",
    manifestPath: "docs/ui/approval-authority.manifest.json",
    manifestAliasField: "privateApprovalAlias",
  },
  {
    alias: "private-codex-ui-mechanical-equivalence",
    env: "CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT",
    manifestPath: "docs/ui/mechanical-equivalence.manifest.json",
    manifestAliasField: "privateEvidenceAlias",
  },
];
const rootAliases = requireArray(manifest, manifestPath, "rootAliases");
const optionalRootAliases = requireArray(manifest, manifestPath, "optionalRootAliases");
const aliasesByAlias = new Map();
const aliasesByEnv = new Map();
for (const [index, entry] of [...rootAliases, ...optionalRootAliases].entries()) {
  const isRequiredAlias = index < rootAliases.length;
  const label = isRequiredAlias
    ? `${manifestPath}.rootAliases[${index}]`
    : `${manifestPath}.optionalRootAliases[${index - rootAliases.length}]`;
  requireFields(entry, label, ["alias", "env", "manifestPath", "manifestAliasField"]);
  if (!entry) continue;
  if (aliasesByAlias.has(entry.alias)) fail(`${label}.alias duplicates ${entry.alias}`);
  if (aliasesByEnv.has(entry.env)) fail(`${label}.env duplicates ${entry.env}`);
  aliasesByAlias.set(entry.alias, entry);
  aliasesByEnv.set(entry.env, entry);
  if (isRequiredAlias && !roots.has(entry.env)) fail(`${label}.env must be listed in requiredRoots`);
  const sourceManifest = readJson(entry.manifestPath);
  if (sourceManifest?.[entry.manifestAliasField] !== entry.alias) {
    fail(`${label} must match ${entry.manifestPath}.${entry.manifestAliasField}`);
  }
}
for (const contract of expectedAliasContracts) {
  const entry = aliasesByAlias.get(contract.alias);
  if (!entry) {
    fail(`${manifestPath}.rootAliases must include ${contract.alias}`);
    continue;
  }
  for (const field of ["env", "manifestPath", "manifestAliasField"]) {
    if (entry[field] !== contract[field]) {
      fail(`${manifestPath}.rootAliases entry for ${contract.alias} must set ${field}=${contract[field]}`);
    }
  }
}
for (const contract of expectedOptionalAliasContracts) {
  const entry = aliasesByAlias.get(contract.alias);
  if (!entry) {
    fail(`${manifestPath}.optionalRootAliases must include ${contract.alias}`);
    continue;
  }
  for (const field of ["env", "manifestPath", "manifestAliasField"]) {
    if (entry[field] !== contract[field]) {
      fail(`${manifestPath}.optionalRootAliases entry for ${contract.alias} must set ${field}=${contract[field]}`);
    }
  }
  if (roots.has(entry.env)) {
    fail(`${manifestPath}.optionalRootAliases entry for ${contract.alias} must not add ${entry.env} to requiredRoots`);
  }
}

const delegates = requireArray(manifest, manifestPath, "delegates");
const runnerSource = fs.existsSync(path.join(rootDir, "scripts/ui_private_visual_verify.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_private_visual_verify.mjs"), "utf8")
  : "";
if (!runnerSource) fail("missing scripts/ui_private_visual_verify.mjs");
for (const snippet of ["--require-approved", "EXTERNAL PENDING", "process.exit(2)"]) {
  if (!runnerSource.includes(snippet)) {
    fail(`scripts/ui_private_visual_verify.mjs must include ${snippet}`);
  }
}
for (const snippet of ["docs/ui/private-visual-validation.manifest.json", "requiredRoots", "delegates", "parseDelegate"]) {
  if (!runnerSource.includes(snippet)) {
    fail(`scripts/ui_private_visual_verify.mjs must derive private validation from ${snippet}`);
  }
}
const evidenceVerifierSource = fs.existsSync(path.join(rootDir, "scripts/ui_private_evidence_verify.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_private_evidence_verify.mjs"), "utf8")
  : "";
if (!evidenceVerifierSource.includes("scripts/ui_private_evidence_plan_check.mjs")) {
  fail("scripts/ui_private_evidence_verify.mjs must consume the derived private evidence plan");
}
for (const snippet of ["docs/ui/private-visual-validation.manifest.json", "rootAliases", "optionalRootAliases", "loadPrivateAliasRoots"]) {
  if (!evidenceVerifierSource.includes(snippet)) {
    fail(`scripts/ui_private_evidence_verify.mjs must derive private aliases from ${snippet}`);
  }
}
const rootContractSource = fs.existsSync(path.join(rootDir, "scripts/ui_private_root_contract.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_private_root_contract.mjs"), "utf8")
  : "";
for (const snippet of ["optionalRootAliases", "includeOptional", "required: false"]) {
  if (!rootContractSource.includes(snippet)) {
    fail(`scripts/ui_private_root_contract.mjs must support optional private root aliases via ${snippet}`);
  }
}
for (const script of [
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const source = fs.existsSync(path.join(rootDir, script)) ? fs.readFileSync(path.join(rootDir, script), "utf8") : "";
  if (!source.includes("ui_private_root_contract.mjs") || !source.includes("privateRootEnvForAlias")) {
    fail(`${script} must derive its private root env from rootAliases`);
  }
  if (/process\.env\.CLAWIX_UI_PRIVATE_/.test(source)) {
    fail(`${script} must not hard-code CLAWIX_UI_PRIVATE_* env names`);
  }
}
for (const script of [
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const delegate = delegates.find((delegate) => String(delegate).includes(script));
  if (!delegate) {
    fail(`${manifestPath}.delegates must include ${script}`);
    continue;
  }
  if (!String(delegate).includes("--require-approved")) {
    fail(`${manifestPath}.delegates entry for ${script} must include --require-approved`);
  }
}

const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const openDecisionIds = requireArray(decisionVerification, decisionVerificationPath, "decisions")
  .filter((decision) => decision?.status === "open")
  .map((decision) => decision.id);
const decisionBlockers = requireArray(manifest, manifestPath, "decisionBlockers");
const blockerSet = new Set(decisionBlockers);
if (blockerSet.size !== decisionBlockers.length) {
  fail(`${manifestPath}.decisionBlockers must not contain duplicate decision ids`);
}
for (const decisionId of openDecisionIds) {
  if (!blockerSet.has(decisionId)) {
    fail(`${manifestPath}.decisionBlockers must include open decision ${decisionId}`);
  }
}
for (const decisionId of decisionBlockers) {
  if (!openDecisionIds.includes(decisionId)) {
    fail(`${manifestPath}.decisionBlockers contains non-open decision ${decisionId}`);
  }
}
const evidenceTypeCounts = evidencePlan?.counts || {};
const decisionBlockerEvidenceTypes = requireArray(manifest, manifestPath, "decisionBlockerEvidenceTypes");
const blockerEvidenceByDecision = new Map();
for (const [index, entry] of decisionBlockerEvidenceTypes.entries()) {
  const label = `${manifestPath}.decisionBlockerEvidenceTypes[${index}]`;
  requireFields(entry, label, ["decisionId", "evidenceTypes"]);
  if (!entry) continue;
  if (!blockerSet.has(entry.decisionId)) {
    fail(`${label}.decisionId must be listed in decisionBlockers`);
  }
  if (blockerEvidenceByDecision.has(entry.decisionId)) {
    fail(`${label}.decisionId duplicates ${entry.decisionId}`);
  }
  blockerEvidenceByDecision.set(entry.decisionId, entry);
  const evidenceTypes = requireArray(entry, label, "evidenceTypes");
  const seenTypes = new Set();
  for (const evidenceType of evidenceTypes) {
    if (seenTypes.has(evidenceType)) fail(`${label}.evidenceTypes duplicates ${evidenceType}`);
    seenTypes.add(evidenceType);
    if (!Number.isInteger(evidenceTypeCounts[evidenceType]) || evidenceTypeCounts[evidenceType] <= 0) {
      fail(`${label}.evidenceTypes includes ${evidenceType}, which is not produced by the private evidence plan`);
    }
  }
}
for (const decisionId of decisionBlockers) {
  if (!blockerEvidenceByDecision.has(decisionId)) {
    fail(`${manifestPath}.decisionBlockerEvidenceTypes must include ${decisionId}`);
  }
}

for (const script of [
  "scripts/ui_private_root_contract.mjs",
  "scripts/ui_private_visual_verify.mjs",
  "scripts/ui_private_evidence_plan_check.mjs",
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  if (!fs.existsSync(path.join(rootDir, script))) fail(`missing ${script}`);
}

if (errors.length > 0) {
  console.error("UI private visual validation manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private visual validation manifest check passed");
