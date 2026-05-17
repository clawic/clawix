#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

const aliasRoots = {
  "private-codex-ui-baselines": "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "private-codex-ui-rendered-geometry": "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "private-codex-ui-copy-snapshots": "CLAWIX_UI_PRIVATE_COPY_ROOT",
  "private-codex-ui-rendered-drift": "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
  "private-codex-ui-debt-audit": "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
};

const referenceFields = {
  "surface-baseline": "privateBaselineReference",
  "surface-geometry": "geometryEvidenceReference",
  "surface-copy": "copySnapshotReference",
  "critical-flow-baseline": "privateBaselineReference",
  "pattern-geometry": "geometryEvidenceReference",
  "rendered-drift": "privateDriftReportReference",
  "debt-audit": "privateDebtAuditReference",
  "performance-budget": "privateBaselineReference",
};

const idFields = {
  "surface-baseline": "coverageId",
  "surface-geometry": "coverageId",
  "surface-copy": "coverageId",
  "critical-flow-baseline": "flowId",
  "pattern-geometry": "patternId",
  "rendered-drift": "coverageId",
  "debt-audit": "debtId",
  "performance-budget": "flowId",
};

function fail(message) {
  errors.push(message);
}

function hasFlag(name) {
  return args.includes(name);
}

const includePending = hasFlag("--include-pending");

function runEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    process.exit(result.status || 1);
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { evidence: [] };
  }
}

function splitReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.includes("..")) return null;
  return { alias, suffix };
}

function assertRoot(root, envName) {
  const resolved = path.resolve(root);
  const relativeToRepo = path.relative(rootDir, resolved);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    fail(`${envName} must point outside the public repository`);
  }
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
    fail(`${envName} does not point to an existing directory`);
  }
  return resolved;
}

function readJson(file, label) {
  if (!fs.existsSync(file)) {
    fail(`missing ${label}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
    return null;
  }
}

function readRepoJson(relativePath) {
  return readJson(path.join(rootDir, relativePath), relativePath);
}

function loadAllowedFindingCategories() {
  const detectorManifest = readRepoJson("docs/ui/visual-change-detectors.manifest.json");
  return new Set((detectorManifest?.classificationBuckets || []).map((bucket) => bucket?.id).filter(Boolean));
}

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return;
  }
  if (/Hash$/.test(field) && (typeof object[field] !== "string" || !/^[a-f0-9]{64}$/i.test(object[field]))) {
    fail(`${label}.${field} must be a 64-character hex hash`);
  }
  if (["approvedByUserAt", "measuredAt", "auditedAt", "producedAt"].includes(field)) {
    verifyIsoTimestamp(object[field], `${label}.${field}`);
  }
  if (field === "approvedScope") {
    verifyApprovedScope(object[field], `${label}.${field}`);
  }
}

function verifyIsoTimestamp(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function verifyApprovedScope(value, label) {
  if (typeof value === "string") {
    if (value.trim() === "") fail(`${label} must not be empty`);
    return;
  }
  if (Array.isArray(value)) {
    if (value.length === 0) fail(`${label} must not be empty`);
    return;
  }
  if (value && typeof value === "object") {
    if (Object.keys(value).length === 0) fail(`${label} must not be empty`);
    return;
  }
  fail(`${label} must be a non-empty string, array, or object`);
}

function verifyMetrics(evidence, label, requiredMetrics = []) {
  if (!("metrics" in evidence)) return;
  if (!evidence.metrics || typeof evidence.metrics !== "object" || Array.isArray(evidence.metrics)) {
    fail(`${label}.metrics must be an object`);
    return;
  }
  for (const metric of requiredMetrics) {
    if (typeof evidence.metrics[metric] !== "number" || !Number.isFinite(evidence.metrics[metric]) || evidence.metrics[metric] < 0) {
      fail(`${label}.metrics.${metric} must be a finite non-negative number`);
    }
  }
  for (const [metric, value] of Object.entries(evidence.metrics)) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      fail(`${label}.metrics.${metric} must be a finite non-negative number`);
    }
  }
}

function verifyMeasurementSamples(evidence, label, requiredMetrics = []) {
  if (!("measurementSamples" in evidence)) return;
  if (!Array.isArray(evidence.measurementSamples) || evidence.measurementSamples.length === 0) {
    fail(`${label}.measurementSamples must be a non-empty array`);
    return;
  }
  const seenMetrics = new Set();
  for (const [index, sample] of evidence.measurementSamples.entries()) {
    const sampleLabel = `${label}.measurementSamples[${index}]`;
    if (!sample || typeof sample !== "object" || Array.isArray(sample)) {
      fail(`${sampleLabel} must be an object`);
      continue;
    }
    if (typeof sample.metric !== "string" || sample.metric === "") {
      fail(`${sampleLabel}.metric must be a non-empty string`);
    } else {
      seenMetrics.add(sample.metric);
      if (requiredMetrics.length > 0 && !requiredMetrics.includes(sample.metric)) {
        fail(`${sampleLabel}.metric must be one of the required metrics`);
      }
    }
    if (typeof sample.value !== "number" || !Number.isFinite(sample.value) || sample.value < 0) {
      fail(`${sampleLabel}.value must be a finite non-negative number`);
    }
    if (typeof sample.sampleHash !== "string" || !/^[a-f0-9]{64}$/i.test(sample.sampleHash)) {
      fail(`${sampleLabel}.sampleHash must be a 64-character hex hash`);
    }
  }
  for (const metric of requiredMetrics) {
    if (!seenMetrics.has(metric)) fail(`${label}.measurementSamples must include ${metric}`);
  }
}

function verifyMeasurements(evidence, label) {
  if (!("measurements" in evidence)) return;
  if (!evidence.measurements || typeof evidence.measurements !== "object" || Array.isArray(evidence.measurements)) {
    fail(`${label}.measurements must be an object`);
    return;
  }
  const entries = Object.entries(evidence.measurements);
  if (entries.length === 0) {
    fail(`${label}.measurements must not be empty`);
    return;
  }
  for (const [measurement, value] of entries) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      fail(`${label}.measurements.${measurement} must be a finite non-negative number`);
    }
  }
}

function patternMeasurementKeys(patternId, platform) {
  const pattern = readRepoJson(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json`);
  const geometry = pattern?.geometry;
  if (!geometry || typeof geometry !== "object" || Array.isArray(geometry)) return [];
  const platformGeometry = geometry[platform];
  if (platformGeometry && typeof platformGeometry === "object" && !Array.isArray(platformGeometry)) {
    return Object.entries(platformGeometry)
      .filter(([, value]) => typeof value === "number")
      .map(([key]) => key);
  }
  return Object.entries(geometry)
    .filter(([, value]) => typeof value === "number")
    .map(([key]) => key);
}

function verifyPatternMeasurementKeys(evidence, item, label) {
  if (item.type !== "pattern-geometry") return;
  for (const key of patternMeasurementKeys(item.id, item.platform)) {
    if (typeof evidence.measurements?.[key] !== "number") {
      fail(`${label}.measurements.${key} must be measured because it is declared in the public pattern geometry contract`);
    }
  }
}

function verifyCopyItems(evidence, label, allowedKinds = new Set()) {
  if (!("copyItems" in evidence)) return;
  if (!Array.isArray(evidence.copyItems) || evidence.copyItems.length === 0) {
    fail(`${label}.copyItems must be a non-empty array`);
    return;
  }
  for (const [index, item] of evidence.copyItems.entries()) {
    const itemLabel = `${label}.copyItems[${index}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      fail(`${itemLabel} must be an object`);
      continue;
    }
    for (const field of ["kind", "textHash", "source"]) {
      if (typeof item[field] !== "string" || item[field] === "") {
        fail(`${itemLabel}.${field} must be a non-empty string`);
      }
    }
    if (typeof item.kind === "string" && allowedKinds.size > 0 && !allowedKinds.has(item.kind)) {
      fail(`${itemLabel}.kind must be one of the restricted copy kinds`);
    }
    if (typeof item.textHash !== "string" || !/^[a-f0-9]{64}$/i.test(item.textHash)) {
      fail(`${itemLabel}.textHash must be a 64-character hex hash`);
    }
  }
}

function verifyCopyHierarchyHash(evidence, label) {
  if (!("copyHierarchyHash" in evidence)) return;
  if (typeof evidence.copyHierarchyHash !== "string" || !/^[a-f0-9]{64}$/i.test(evidence.copyHierarchyHash)) {
    fail(`${label}.copyHierarchyHash must be a 64-character hex hash`);
  }
}

function verifyDriftResults(evidence, label, driftPolicy = {}) {
  if (!("driftResults" in evidence)) return;
  if (!evidence.driftResults || typeof evidence.driftResults !== "object" || Array.isArray(evidence.driftResults)) {
    fail(`${label}.driftResults must be an object keyed by drift category`);
    return;
  }
  const allowedStatuses = driftPolicy.allowedStatuses || new Set();
  const blockingStatuses = driftPolicy.blockingStatuses || new Set();
  const approvalRequiredStatuses = driftPolicy.approvalRequiredStatuses || new Set();
  if (blockingStatuses.has(evidence.status)) {
    fail(`${label}.status ${evidence.status} is blocking and cannot satisfy approved private evidence`);
  }
  if (approvalRequiredStatuses.has(evidence.status)) {
    requireField(evidence, label, "approvedByUserAt");
    requireField(evidence, label, "approvedScope");
  }
  const entries = Object.entries(evidence.driftResults);
  if (entries.length === 0) {
    fail(`${label}.driftResults must not be empty`);
    return;
  }
  for (const [category, result] of entries) {
    const resultLabel = `${label}.driftResults.${category}`;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      fail(`${resultLabel} must be an object`);
      continue;
    }
    if (typeof result.status !== "string" || result.status === "") {
      fail(`${resultLabel}.status must be a non-empty string`);
    } else if (allowedStatuses.size > 0 && !allowedStatuses.has(result.status)) {
      fail(`${resultLabel}.status is invalid`);
    }
    if (evidence.status !== "pending-private-evidence" && result.status === "pending-private-evidence") {
      fail(`${resultLabel}.status must not be pending when the report is approved`);
    }
    if (typeof result.resultHash !== "string" || !/^[a-f0-9]{64}$/i.test(result.resultHash)) {
      fail(`${resultLabel}.resultHash must be a 64-character hex hash`);
    }
  }
}

function verifyFindingItems(evidence, label, allowedCategories) {
  if (!("findingItems" in evidence)) return;
  if (!Array.isArray(evidence.findingItems) || evidence.findingItems.length === 0) {
    fail(`${label}.findingItems must be a non-empty array`);
    return;
  }
  for (const [index, item] of evidence.findingItems.entries()) {
    const itemLabel = `${label}.findingItems[${index}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      fail(`${itemLabel} must be an object`);
      continue;
    }
    for (const field of ["category", "source"]) {
      if (typeof item[field] !== "string" || item[field] === "") {
        fail(`${itemLabel}.${field} must be a non-empty string`);
      }
    }
    if (typeof item.category === "string" && item.category !== "" && !allowedCategories.has(item.category)) {
      fail(`${itemLabel}.category must be one of ${[...allowedCategories].join(", ")}`);
    }
    if (typeof item.itemHash !== "string" || !/^[a-f0-9]{64}$/i.test(item.itemHash)) {
      fail(`${itemLabel}.itemHash must be a 64-character hex hash`);
    }
  }
}

function mapByKey(items, keyFn) {
  const result = new Map();
  for (const item of items || []) result.set(keyFn(item), item);
  return result;
}

function verifyPublicApprovalState(item, registries, label) {
  if (includePending) return true;
  if (["surface-baseline", "surface-geometry", "surface-copy"].includes(item.type)) {
    const coverage = registries.surfaceCoverageById.get(item.id);
    if (coverage?.baselineStatus !== "approved") {
      fail(`${label} is pending approved surface baseline capture`);
      return false;
    }
    return true;
  }
  if (item.type === "critical-flow-baseline") {
    const flow = registries.privateBaselineByKey.get(`${item.platform}:${item.id}`);
    if (flow?.baselineStatus !== "approved") {
      fail(`${label} is pending approved baseline capture`);
      return false;
    }
    return true;
  }
  if (item.type === "pattern-geometry") {
    if (registries.renderedGeometryStatus !== "approved") {
      fail(`${label} is pending approved rendered geometry evidence`);
      return false;
    }
    return true;
  }
  if (item.type === "rendered-drift") {
    const report = registries.renderedDriftById.get(item.id);
    if (registries.driftBlockingStatuses.has(report?.status)) {
      fail(`${label} rendered drift evidence is not approved; status=${report?.status || "missing"}`);
      return false;
    }
    return true;
  }
  if (item.type === "debt-audit") {
    const audit = registries.debtAuditById.get(item.id);
    if (audit?.auditStatus !== "audited-approved") {
      fail(`${label} is pending approved private debt audit`);
      return false;
    }
    return true;
  }
  if (item.type === "performance-budget") {
    const budget = registries.performanceBudgetByKey.get(`${item.platform}:${item.id}`);
    if (budget?.baselineStatus !== "approved" || budget?.budgetStatus !== "enforced") {
      fail(`${label} is pending approved performance measurement`);
      return false;
    }
  }
  return true;
}

if (!hasFlag("--require-approved")) {
  console.error("UI private evidence verification requires --require-approved.");
  process.exit(1);
}

const plan = runEvidencePlan();
const allowedFindingCategories = loadAllowedFindingCategories();
const aliases = new Set();
for (const item of plan.evidence || []) {
  const parsed = splitReference(item.privateReference);
  if (!parsed) {
    fail(`${item.type}:${item.platform}:${item.id} has invalid privateReference`);
    continue;
  }
  aliases.add(parsed.alias);
}

const missingEnv = [...aliases]
  .map((alias) => aliasRoots[alias])
  .filter((envName, index, values) => envName && !process.env[envName] && values.indexOf(envName) === index);
const unknownAliases = [...aliases].filter((alias) => !aliasRoots[alias]);
if (unknownAliases.length > 0) fail(`unknown private evidence aliases: ${unknownAliases.join(", ")}`);
if (missingEnv.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingEnv.join(", ")} to verify the private UI evidence plan.`);
  process.exit(2);
}

const roots = new Map();
for (const alias of aliases) {
  const envName = aliasRoots[alias];
  if (!envName) continue;
  roots.set(alias, assertRoot(process.env[envName], envName));
}

const performanceBudgets = readRepoJson("docs/ui/performance-budgets.registry.json");
const requiredPerformanceMetrics = Array.isArray(performanceBudgets?.requiredMetrics)
  ? performanceBudgets.requiredMetrics
  : [];
const surfaceCoverage = readRepoJson("docs/ui/surface-baseline-coverage.manifest.json");
const privateBaselines = readRepoJson("docs/ui/private-baselines.manifest.json");
const debtAudit = readRepoJson("docs/ui/debt-audit.manifest.json");
const copyInventory = readRepoJson("docs/ui/copy.inventory.json");
const allowedCopyKinds = new Set(Array.isArray(copyInventory?.restrictedCopyKinds) ? copyInventory.restrictedCopyKinds : []);
const renderedGeometry = readRepoJson("docs/ui/rendered-geometry.manifest.json");
const renderedDrift = readRepoJson("docs/ui/rendered-drift.manifest.json");
const driftPolicy = {
  allowedStatuses: new Set(Array.isArray(renderedDrift?.reportStatuses) ? renderedDrift.reportStatuses : []),
  blockingStatuses: new Set(Array.isArray(renderedDrift?.blockingReportStatuses) ? renderedDrift.blockingReportStatuses : []),
  approvalRequiredStatuses: new Set(
    Array.isArray(renderedDrift?.approvalRequiredStatuses) ? renderedDrift.approvalRequiredStatuses : [],
  ),
};
const publicRegistries = {
  surfaceCoverageById: mapByKey(surfaceCoverage?.coverage, (entry) => entry.coverageId),
  privateBaselineByKey: mapByKey(privateBaselines?.flows, (flow) => `${flow.platform}:${flow.id}`),
  renderedDriftById: mapByKey(renderedDrift?.reports, (report) => report.coverageId),
  debtAuditById: mapByKey(debtAudit?.entries, (entry) => entry.debtId),
  performanceBudgetByKey: mapByKey(performanceBudgets?.flows, (flow) => `${flow.platform}:${flow.id}`),
  renderedGeometryStatus: renderedGeometry?.status,
  driftBlockingStatuses: driftPolicy.blockingStatuses,
};

let verified = 0;
for (const item of plan.evidence || []) {
  const parsed = splitReference(item.privateReference);
  if (!parsed) continue;
  const root = roots.get(parsed.alias);
  if (!root) continue;
  const evidencePath = path.join(root, parsed.suffix.split("/").join(path.sep), item.evidenceFilename);
  const label = `${item.type}:${item.platform}:${item.id}`;
  if (!verifyPublicApprovalState(item, publicRegistries, label)) continue;
  const evidence = readJson(evidencePath, `${label} ${item.evidenceFilename}`);
  if (!evidence) continue;

  for (const field of item.requiredFields || []) requireField(evidence, label, field);

  const idField = idFields[item.type];
  if (idField && evidence[idField] !== item.id) fail(`${label}.${idField} must match the public evidence plan`);
  if (evidence.platform !== item.platform) fail(`${label}.platform must match the public evidence plan`);

  const referenceField = referenceFields[item.type];
  if (referenceField && evidence[referenceField] !== item.privateReference) {
    fail(`${label}.${referenceField} must match the public evidence plan`);
  }

  const itemRequiredMetrics = item.type === "performance-budget" ? requiredPerformanceMetrics : [];
  verifyMetrics(evidence, label, itemRequiredMetrics);
  verifyMeasurementSamples(evidence, label, itemRequiredMetrics);
  verifyMeasurements(evidence, label);
  verifyPatternMeasurementKeys(evidence, item, label);
  verifyCopyItems(evidence, label, allowedCopyKinds);
  verifyCopyHierarchyHash(evidence, label);
  verifyDriftResults(evidence, label, item.type === "rendered-drift" ? driftPolicy : {});
  verifyFindingItems(evidence, label, allowedFindingCategories);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private evidence verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private evidence verification passed (${verified} evidence records)`);
