#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function assertPublicSafeReference(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.includes("..")) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (/^\/Users\//.test(reference) || reference.startsWith("file://") || /^[A-Z]:\\/.test(reference)) {
    fail(`${label} must not contain a local absolute path`);
  }
}

function sameStringArray(left, right) {
  return JSON.stringify(left || []) === JSON.stringify(right || []);
}

const manifestPath = "docs/ui/debt-audit.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "sourceReport",
  "surfaceCoverageSource",
  "privateDebtAuditAlias",
  "evidenceFilename",
  "verificationCommand",
  "auditStatuses",
  "requiredEvidenceFields",
  "entries",
]);

if (manifest?.privateDebtAuditAlias !== "private-codex-ui-debt-audit") {
  fail(`${manifestPath}.privateDebtAuditAlias must be private-codex-ui-debt-audit`);
}
if (manifest?.evidenceFilename !== "debt-audit-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be debt-audit-evidence.json`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_debt_audit_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_debt_audit_verify.mjs`);
}

const requiredEvidence = new Set(requireArray(manifest, manifestPath, "requiredEvidenceFields"));
for (const field of [
  "debtId",
  "platform",
  "scope",
  "platforms",
  "privateDebtAuditReference",
  "findingHash",
  "visualInventoryHash",
  "auditedAt",
  "approvedByUserAt",
  "approvedScope",
]) {
  if (!requiredEvidence.has(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}

const auditStatuses = new Set(requireArray(manifest, manifestPath, "auditStatuses"));
for (const status of ["pending-private-visual-inventory", "audited-approved"]) {
  if (!auditStatuses.has(status)) fail(`${manifestPath}.auditStatuses must include ${status}`);
}

const debtBaseline = readJson(manifest?.sourceBaseline || "docs/ui/debt.baseline.json");
const debtReport = readJson(manifest?.sourceReport || "docs/ui/debt-report.registry.json");
const surfaceCoverage = readJson(manifest?.surfaceCoverageSource || "docs/ui/surface-baseline-coverage.manifest.json");

const debtById = new Map();
for (const entry of requireArray(debtBaseline, manifest?.sourceBaseline || "docs/ui/debt.baseline.json", "entries")) {
  debtById.set(entry.id, entry);
}

const pendingDebtIds = new Set(
  requireArray(debtReport, manifest?.sourceReport || "docs/ui/debt-report.registry.json", "pendingItems").map((item) => item.debtId),
);

const coverageDebtIds = new Map();
for (const coverage of requireArray(surfaceCoverage, manifest?.surfaceCoverageSource || "docs/ui/surface-baseline-coverage.manifest.json", "coverage")) {
  if (coverage.classification !== "debt") continue;
  for (const debtId of coverage.debtIds || []) coverageDebtIds.set(debtId, coverage.coverageId);
}

const auditDebtIds = new Set();
for (const [index, entry] of requireArray(manifest, manifestPath, "entries").entries()) {
  const label = `${manifestPath}.entries[${index}]`;
  requireFields(entry, label, [
    "debtId",
    "scope",
    "platforms",
    "surfaceCoverageId",
    "auditStatus",
    "privateDebtAuditReference",
    "requiredEvidence",
  ]);
  const debt = debtById.get(entry.debtId);
  if (!debt) {
    fail(`${label}.debtId must reference ${manifest?.sourceBaseline}`);
  } else {
    if (entry.scope !== debt.scope) fail(`${label}.scope must match ${manifest?.sourceBaseline}`);
    if (!sameStringArray(entry.platforms, debt.platforms)) fail(`${label}.platforms must match ${manifest?.sourceBaseline}`);
  }
  if (!pendingDebtIds.has(entry.debtId)) fail(`${label}.debtId must be present in ${manifest?.sourceReport}`);
  if (coverageDebtIds.get(entry.debtId) !== entry.surfaceCoverageId) {
    fail(`${label}.surfaceCoverageId must map the debt entry in ${manifest?.surfaceCoverageSource}`);
  }
  if (!auditStatuses.has(entry.auditStatus)) fail(`${label}.auditStatus is invalid`);
  assertPublicSafeReference(entry.privateDebtAuditReference, manifest?.privateDebtAuditAlias, `${label}.privateDebtAuditReference`);
  const entryRequired = new Set(requireArray(entry, label, "requiredEvidence"));
  for (const field of requiredEvidence) {
    if (!entryRequired.has(field)) fail(`${label}.requiredEvidence must include ${field}`);
  }
  auditDebtIds.add(entry.debtId);
}

for (const debtId of debtById.keys()) {
  if (!auditDebtIds.has(debtId)) fail(`${manifestPath}.entries must include debtId ${debtId}`);
}

if (errors.length > 0) {
  console.error("UI debt audit manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI debt audit manifest check passed (${auditDebtIds.size} debt audit entries)`);
