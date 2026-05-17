#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
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

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))) {
    fail(`${label} must not contain a local path`);
  }
}

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const requiredEvidence = new Set(["private-baseline", "copy-snapshot", "rendered-geometry"]);

const debtPath = "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
const debtEntries = requireArray(debt, debtPath, "entries");
const debtIds = new Set();
for (const [index, entry] of debtEntries.entries()) {
  const label = `${debtPath}.entries[${index}]`;
  requireFields(entry, label, ["id", "scope", "platforms", "status", "reviewAfter", "allowedAction"]);
  if (entry?.id) debtIds.add(entry.id);
  if (entry.reviewAfter < today) fail(`${label} expired on ${entry.reviewAfter}`);
}

const aliasPath = "docs/ui/debt-baseline.manifest.json";
const alias = readJson(aliasPath);
requireFields(alias, aliasPath, ["schemaVersion", "status", "policy", "canonicalBaseline", "reportRegistry"]);
if (alias?.canonicalBaseline !== debtPath) fail(`${aliasPath}.canonicalBaseline must be ${debtPath}`);

const reportPath = "docs/ui/debt-report.registry.json";
const report = readJson(reportPath);
requireFields(report, reportPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "reportStatusValues",
  "fixPolicy",
  "pendingItems",
]);
if (report?.sourceBaseline !== debtPath) fail(`${reportPath}.sourceBaseline must be ${debtPath}`);
if (alias?.reportRegistry !== reportPath) fail(`${aliasPath}.reportRegistry must be ${reportPath}`);

const reportStatuses = new Set(requireArray(report, reportPath, "reportStatusValues"));
for (const status of ["pending-visual-authorized-cleanup", "blocked-without-private-baseline", "resolved"]) {
  if (!reportStatuses.has(status)) fail(`${reportPath}.reportStatusValues must include ${status}`);
}

const fixPolicy = report?.fixPolicy || {};
requireFields(fixPolicy, `${reportPath}.fixPolicy`, [
  "nonAuthorizedAction",
  "cleanupActionBeforeApproval",
  "requiredAuthorization",
  "requiredPrivateEvidenceBeforeCleanup",
  "forbiddenWithoutApproval",
]);
if (fixPolicy.nonAuthorizedAction !== "report-only") {
  fail(`${reportPath}.fixPolicy.nonAuthorizedAction must be report-only`);
}
if (fixPolicy.cleanupActionBeforeApproval !== "queue-only") {
  fail(`${reportPath}.fixPolicy.cleanupActionBeforeApproval must be queue-only`);
}
if (fixPolicy.requiredAuthorization !== "visual-authorized-lane") {
  fail(`${reportPath}.fixPolicy.requiredAuthorization must be visual-authorized-lane`);
}
const fixPolicyEvidence = new Set(requireArray(fixPolicy, `${reportPath}.fixPolicy`, "requiredPrivateEvidenceBeforeCleanup"));
for (const evidence of requiredEvidence) {
  if (!fixPolicyEvidence.has(evidence)) {
    fail(`${reportPath}.fixPolicy.requiredPrivateEvidenceBeforeCleanup must include ${evidence}`);
  }
}
const forbiddenWithoutApproval = new Set(requireArray(fixPolicy, `${reportPath}.fixPolicy`, "forbiddenWithoutApproval"));
for (const action of ["presentation-edit", "copy-edit", "layout-edit", "opportunistic-fix"]) {
  if (!forbiddenWithoutApproval.has(action)) {
    fail(`${reportPath}.fixPolicy.forbiddenWithoutApproval must include ${action}`);
  }
}

const reportedDebtIds = new Set();
for (const [index, item] of requireArray(report, reportPath, "pendingItems").entries()) {
  const label = `${reportPath}.pendingItems[${index}]`;
  requireFields(item, label, [
    "id",
    "debtId",
    "status",
    "scope",
    "platforms",
    "requiredAuthorization",
    "requiredEvidence",
    "allowedCurrentAction",
  ]);
  if (!debtIds.has(item.debtId)) fail(`${label}.debtId must reference ${debtPath}`);
  if (!reportStatuses.has(item.status)) fail(`${label}.status is invalid`);
  if (item.requiredAuthorization !== "visual-authorized-lane") {
    fail(`${label}.requiredAuthorization must be visual-authorized-lane`);
  }
  if (item.allowedCurrentAction !== "Report only.") {
    fail(`${label}.allowedCurrentAction must remain Report only.`);
  }
  for (const platform of requireArray(item, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  const itemEvidence = new Set(requireArray(item, label, "requiredEvidence"));
  for (const evidence of requiredEvidence) {
    if (!itemEvidence.has(evidence)) fail(`${label}.requiredEvidence must include ${evidence}`);
  }
  reportedDebtIds.add(item.debtId);
}

for (const debtId of debtIds) {
  if (!reportedDebtIds.has(debtId)) fail(`${reportPath}.pendingItems must include debtId ${debtId}`);
}

scanForLocalPaths(report, reportPath);

if (errors.length > 0) {
  console.error("UI debt report check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI debt report check passed (${reportedDebtIds.size} pending items)`);
