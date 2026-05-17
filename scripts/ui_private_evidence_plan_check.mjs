#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];
const plan = [];

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

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function assertPublicSafeReference(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.includes("..")) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (/^\/Users\//.test(reference) || reference.startsWith("file://") || /^[A-Z]:\\/.test(reference)) {
    fail(`${label} must not contain a local absolute path`);
  }
  return suffix;
}

function addPlanItem(item) {
  requireFields(item, item.label, ["type", "id", "platform", "privateReference", "evidenceFilename", "requiredFields"]);
  if (Array.isArray(item.requiredFields) && item.requiredFields.length === 0) {
    fail(`${item.label}.requiredFields must not be empty`);
  }
  plan.push(item);
}

const surfaceCoverage = readJson("docs/ui/surface-baseline-coverage.manifest.json");
const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
const renderedGeometry = readJson("docs/ui/rendered-geometry.manifest.json");
const patternRegistry = readJson("docs/ui/pattern-registry/patterns.registry.json");
const copyInventory = readJson("docs/ui/copy.inventory.json");
const renderedDrift = readJson("docs/ui/rendered-drift.manifest.json");
const performanceBudgets = readJson("docs/ui/performance-budgets.registry.json");
const debtAudit = readJson("docs/ui/debt-audit.manifest.json");

const surfaceRequiredFields = requireArray(surfaceCoverage, "docs/ui/surface-baseline-coverage.manifest.json", "requiredEvidenceFields");
for (const [index, entry] of requireArray(surfaceCoverage, "docs/ui/surface-baseline-coverage.manifest.json", "coverage").entries()) {
  const label = `surface-baseline-coverage[${index}]`;
  requireFields(entry, label, [
    "coverageId",
    "platform",
    "privateBaselineReference",
    "geometryEvidenceReference",
    "copySnapshotReference",
    "requiredEvidence",
  ]);
  assertPublicSafeReference(entry.privateBaselineReference, surfaceCoverage?.privateBaselineAlias, `${label}.privateBaselineReference`);
  assertPublicSafeReference(entry.geometryEvidenceReference, surfaceCoverage?.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  assertPublicSafeReference(entry.copySnapshotReference, surfaceCoverage?.privateCopyAlias, `${label}.copySnapshotReference`);
  addPlanItem({
    label,
    type: "surface-baseline",
    id: entry.coverageId,
    platform: entry.platform,
    privateReference: entry.privateBaselineReference,
    evidenceFilename: "surface-evidence.json",
    requiredFields: surfaceRequiredFields,
  });
  addPlanItem({
    label,
    type: "surface-geometry",
    id: entry.coverageId,
    platform: entry.platform,
    privateReference: entry.geometryEvidenceReference,
    evidenceFilename: "surface-geometry.json",
    requiredFields: ["coverageId", "platform", "geometryHash", "approvedByUserAt", "approvedScope"],
  });
  addPlanItem({
    label,
    type: "surface-copy",
    id: entry.coverageId,
    platform: entry.platform,
    privateReference: entry.copySnapshotReference,
    evidenceFilename: copyInventory?.evidenceFilename || "copy-evidence.json",
    requiredFields: copyInventory?.requiredEvidenceFields || [],
  });
}

for (const [index, flow] of requireArray(privateBaselines, "docs/ui/private-baselines.manifest.json", "flows").entries()) {
  const label = `private-baselines[${index}]`;
  requireFields(flow, label, ["id", "platform", "privateBaselineReference", "requiredEvidence"]);
  assertPublicSafeReference(flow.privateBaselineReference, privateBaselines?.privateRootAlias, `${label}.privateBaselineReference`);
  addPlanItem({
    label,
    type: "critical-flow-baseline",
    id: flow.id,
    platform: flow.platform,
    privateReference: flow.privateBaselineReference,
    evidenceFilename: privateBaselines?.evidenceFilename || "evidence.json",
    requiredFields: flow.requiredEvidence,
  });
}

for (const patternId of requireArray(patternRegistry, "docs/ui/pattern-registry/patterns.registry.json", "patterns")) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  for (const platform of requireArray(pattern, patternPath, "platforms")) {
    const privateReference = `${renderedGeometry?.privateGeometryAlias}:${platform}/${patternId}`;
    assertPublicSafeReference(privateReference, renderedGeometry?.privateGeometryAlias, `${patternPath}.${platform}.geometryReference`);
    addPlanItem({
      label: `${patternPath}:${platform}`,
      type: "pattern-geometry",
      id: patternId,
      platform,
      privateReference,
      evidenceFilename: renderedGeometry?.evidenceFilename || "geometry-evidence.json",
      requiredFields: renderedGeometry?.requiredEvidenceFields || [],
    });
  }
}

for (const [index, report] of requireArray(renderedDrift, "docs/ui/rendered-drift.manifest.json", "reports").entries()) {
  const label = `rendered-drift[${index}]`;
  requireFields(report, label, ["coverageId", "platform", "privateDriftReportReference"]);
  assertPublicSafeReference(report.privateDriftReportReference, renderedDrift?.privateDriftAlias, `${label}.privateDriftReportReference`);
  addPlanItem({
    label,
    type: "rendered-drift",
    id: report.coverageId,
    platform: report.platform,
    privateReference: report.privateDriftReportReference,
    evidenceFilename: renderedDrift?.evidenceFilename || "drift-report.json",
    requiredFields: renderedDrift?.requiredEvidenceFields || [],
  });
}

for (const [index, entry] of requireArray(debtAudit, "docs/ui/debt-audit.manifest.json", "entries").entries()) {
  const label = `debt-audit[${index}]`;
  requireFields(entry, label, ["debtId", "platforms", "privateDebtAuditReference", "requiredEvidence"]);
  assertPublicSafeReference(entry.privateDebtAuditReference, debtAudit?.privateDebtAuditAlias, `${label}.privateDebtAuditReference`);
  addPlanItem({
    label,
    type: "debt-audit",
    id: entry.debtId,
    platform: entry.platforms?.[0] || "unknown",
    privateReference: entry.privateDebtAuditReference,
    evidenceFilename: debtAudit?.evidenceFilename || "debt-audit-evidence.json",
    requiredFields: entry.requiredEvidence,
  });
}

for (const [index, flow] of requireArray(performanceBudgets, "docs/ui/performance-budgets.registry.json", "flows").entries()) {
  const label = `performance-budgets[${index}]`;
  requireFields(flow, label, ["id", "platform", "privateBaselineReference"]);
  assertPublicSafeReference(flow.privateBaselineReference, privateBaselines?.privateRootAlias, `${label}.privateBaselineReference`);
  addPlanItem({
    label,
    type: "performance-budget",
    id: flow.id,
    platform: flow.platform,
    privateReference: flow.privateBaselineReference,
    evidenceFilename: performanceBudgets?.evidenceFilename || "performance-evidence.json",
    requiredFields: performanceBudgets?.requiredEvidenceFields || [],
  });
}

const counts = new Map();
for (const item of plan) {
  counts.set(item.type, (counts.get(item.type) || 0) + 1);
}

for (const type of [
  "surface-baseline",
  "surface-geometry",
  "surface-copy",
  "critical-flow-baseline",
  "pattern-geometry",
  "rendered-drift",
  "debt-audit",
  "performance-budget",
]) {
  if (!counts.has(type)) fail(`private evidence plan must include ${type}`);
}

if (errors.length > 0) {
  console.error("UI private evidence plan check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (args.includes("--json")) {
  console.log(JSON.stringify({ schemaVersion: 1, counts: Object.fromEntries(counts), evidence: plan }, null, 2));
} else {
  const summary = [...counts.entries()].map(([type, count]) => `${type}:${count}`).join(", ");
  console.log(`UI private evidence plan check passed (${plan.length} evidence records; ${summary})`);
}
