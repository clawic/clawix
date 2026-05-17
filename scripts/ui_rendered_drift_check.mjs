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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  if (value.startsWith("/") || value.includes("/Users/") || value.startsWith("file://")) {
    fail(`${label} must not contain a local path`);
  }
}

const manifestPath = "docs/ui/rendered-drift.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "surfaceBaselineCoveragePath",
  "privateDriftAlias",
  "verificationCommand",
  "driftCategories",
  "reportStatuses",
  "requiredReportFields",
  "requiredEvidenceFields",
  "failureOutputRequirements",
  "evidenceFilename",
  "reports",
]);
if (manifest?.status !== "pending-private-capture" && manifest?.status !== "active") {
  fail(`${manifestPath}.status must be pending-private-capture or active`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_visual_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_visual_verify.mjs`);
}

const expectedCategories = ["geometry", "screenshot", "copy", "performance", "state"];
const categories = new Set(requireArray(manifest, manifestPath, "driftCategories"));
for (const category of expectedCategories) {
  if (!categories.has(category)) fail(`${manifestPath}.driftCategories must include ${category}`);
}
const statuses = new Set(requireArray(manifest, manifestPath, "reportStatuses"));
for (const status of ["pending-private-evidence", "no-drift", "drift-detected", "approved-drift"]) {
  if (!statuses.has(status)) fail(`${manifestPath}.reportStatuses must include ${status}`);
}
const requiredReportFields = requireArray(manifest, manifestPath, "requiredReportFields");
for (const field of ["coverageId", "platform", "privateDriftReportReference", "driftCategories", "status", "reviewAfter"]) {
  if (!requiredReportFields.includes(field)) fail(`${manifestPath}.requiredReportFields must include ${field}`);
}
const requiredEvidenceFields = requireArray(manifest, manifestPath, "requiredEvidenceFields");
for (const field of ["coverageId", "platform", "privateDriftReportReference", "driftCategories", "status", "reportHash", "producedAt"]) {
  if (!requiredEvidenceFields.includes(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}
const failureOutputRequirements = requireArray(manifest, manifestPath, "failureOutputRequirements");
for (const field of ["route", "reason", "required permission", "privateDriftReportReference"]) {
  if (!failureOutputRequirements.includes(field)) fail(`${manifestPath}.failureOutputRequirements must include ${field}`);
}
if (manifest?.evidenceFilename !== "drift-report.json") fail(`${manifestPath}.evidenceFilename must be drift-report.json`);

const coveragePath = manifest?.surfaceBaselineCoveragePath || "docs/ui/surface-baseline-coverage.manifest.json";
const coverage = readJson(coveragePath);
const coverageById = new Map();
for (const entry of requireArray(coverage, coveragePath, "coverage")) {
  coverageById.set(entry.coverageId, entry);
}

const seen = new Set();
for (const [index, report] of requireArray(manifest, manifestPath, "reports").entries()) {
  const label = `${manifestPath}.reports[${index}]`;
  requireFields(report, label, requiredReportFields);
  if (seen.has(report.coverageId)) fail(`${label}.coverageId duplicates ${report.coverageId}`);
  seen.add(report.coverageId);
  const coverageEntry = coverageById.get(report.coverageId);
  if (!coverageEntry) {
    fail(`${label}.coverageId is not listed in ${coveragePath}`);
    continue;
  }
  if (report.platform !== coverageEntry.platform) fail(`${label}.platform must match ${coveragePath}`);
  requireAlias(report.privateDriftReportReference, manifest.privateDriftAlias, `${label}.privateDriftReportReference`);
  if (!statuses.has(report.status)) fail(`${label}.status is not allowed`);
  if (report.reviewAfter < today) fail(`${label}.reviewAfter expired on ${report.reviewAfter}`);
  const reportCategories = new Set(requireArray(report, label, "driftCategories"));
  for (const category of categories) {
    if (!reportCategories.has(category)) fail(`${label}.driftCategories must include ${category}`);
  }
}

for (const coverageId of coverageById.keys()) {
  if (!seen.has(coverageId)) fail(`${manifestPath}.reports must include ${coverageId}`);
}

if (errors.length > 0) {
  console.error("UI rendered drift check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI rendered drift check passed (${seen.size} drift report routes)`);
