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

function requireSafePrivateReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

const manifestPath = "docs/ui/approval-authority.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateApprovalAlias",
  "evidenceFilename",
  "requiredPrivateApprovalEvidenceFields",
  "approvalSources",
]);
if (manifest?.privateApprovalAlias !== "private-codex-ui-approval") {
  fail(`${manifestPath}.privateApprovalAlias must be private-codex-ui-approval`);
}
if (manifest?.evidenceFilename !== "approval-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be approval-evidence.json`);
}
const requiredEvidenceFields = new Set(requireArray(manifest, manifestPath, "requiredPrivateApprovalEvidenceFields"));
for (const field of ["sourceId", "privateApprovalReference", "approvedBy", "approvedAt", "approvalHash", "publicRecordHash"]) {
  if (!requiredEvidenceFields.has(field)) {
    fail(`${manifestPath}.requiredPrivateApprovalEvidenceFields must include ${field}`);
  }
}

let checkedRecords = 0;
const requiredSourceIds = new Set([
  "canon-promotions",
  "protected-surfaces",
  "visual-change-scopes",
  "visual-proposals",
  "exceptions",
]);
const requiredApprovedByFields = new Map([
  ["canon-promotions", "approvedBy"],
  ["protected-surfaces", "approvedBy"],
  ["visual-change-scopes", "approvedBy"],
  ["exceptions", "approvedBy"],
]);
const sourceIds = new Set();
for (const [sourceIndex, source] of requireArray(manifest, manifestPath, "approvalSources").entries()) {
  const sourceLabel = `${manifestPath}.approvalSources[${sourceIndex}]`;
  requireFields(source, sourceLabel, ["id", "path", "arrayField"]);
  if (sourceIds.has(source.id)) fail(`${sourceLabel}.id duplicates ${source.id}`);
  sourceIds.add(source.id);
  if (typeof source.privateApprovalField !== "string" || source.privateApprovalField === "") {
    fail(`${sourceLabel}.privateApprovalField must name a private approval reference field`);
  }
  const requiredApprovedByField = requiredApprovedByFields.get(source.id);
  if (requiredApprovedByField && source.approvedByField !== requiredApprovedByField) {
    fail(`${sourceLabel}.approvedByField must be ${requiredApprovedByField}`);
  }
  const approvalRequiredStatuses = Array.isArray(source.approvalRequiredStatuses)
    ? new Set(source.approvalRequiredStatuses)
    : null;
  if (approvalRequiredStatuses && (typeof source.statusField !== "string" || source.statusField === "")) {
    fail(`${sourceLabel}.statusField must be set when approvalRequiredStatuses is present`);
  }
  if (approvalRequiredStatuses && (typeof source.statusValuesField !== "string" || source.statusValuesField === "")) {
    fail(`${sourceLabel}.statusValuesField must be set when approvalRequiredStatuses is present`);
  }
  const registry = readJson(source.path);
  if (approvalRequiredStatuses) {
    const allowedStatuses = new Set(requireArray(registry, source.path, source.statusValuesField));
    for (const status of approvalRequiredStatuses) {
      if (!allowedStatuses.has(status)) {
        fail(`${sourceLabel}.approvalRequiredStatuses contains status not declared in ${source.path}.${source.statusValuesField}: ${status}`);
      }
    }
  }
  const records = requireArray(registry, source.path, source.arrayField, { nonEmpty: false });
  for (const [recordIndex, record] of records.entries()) {
    const label = `${source.path}.${source.arrayField}[${recordIndex}]`;
    if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) {
      continue;
    }
    if (source.approvedByField && record[source.approvedByField] !== "user") {
      fail(`${label}.${source.approvedByField} must be user`);
    }
    if (source.privateApprovalField) {
      const reference = record[source.privateApprovalField];
      requireSafePrivateReference(reference, manifest.privateApprovalAlias, `${label}.${source.privateApprovalField}`);
    }
    checkedRecords += 1;
  }
}
for (const sourceId of requiredSourceIds) {
  if (!sourceIds.has(sourceId)) fail(`${manifestPath}.approvalSources must include ${sourceId}`);
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI approval authority check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI approval authority check passed (${checkedRecords} approval records)`);
