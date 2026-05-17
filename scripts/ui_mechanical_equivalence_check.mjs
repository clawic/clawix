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
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function hasLocalPath(value) {
  return (
    typeof value === "string" &&
    (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))
  );
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

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value)) {
    fail(`${label} must not contain a local path`);
  }
}

function requireIsoTimestamp(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function requireApprovedScope(value, requiredFields, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object with approved user scope metadata`);
    return;
  }
  requireFields(value, label, requiredFields);
  if (value.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  requireIsoTimestamp(value.approvedAt, `${label}.approvedAt`);
  requireAlias(value.privateApprovalReference, "private-codex-ui-approvals", `${label}.privateApprovalReference`);
  if (typeof value.scopeId !== "string" || value.scopeId === "") {
    fail(`${label}.scopeId must be a non-empty string`);
  }
}

const manifestPath = "docs/ui/mechanical-equivalence.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateEvidenceAlias",
  "evidenceFilename",
  "recordRequirement",
  "requiredEvidenceFields",
  "requiredPrivateEvidenceFields",
  "requiredApprovedScopeFields",
  "allowedTokenDiffStatuses",
  "equivalenceStatuses",
  "records",
]);

if (manifest?.privateEvidenceAlias !== "private-codex-ui-mechanical-equivalence") {
  fail(`${manifestPath}.privateEvidenceAlias must be private-codex-ui-mechanical-equivalence`);
}
if (manifest?.evidenceFilename !== "mechanical-equivalence-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be mechanical-equivalence-evidence.json`);
}

const recordRequirement = manifest?.recordRequirement || {};
requireFields(recordRequirement, `${manifestPath}.recordRequirement`, [
  "requiredForMutationClass",
  "emptyRecordsAllowedOnlyWhenNoRefactorInScope",
  "mergeBlockingStatuses",
  "requiredPassingStatus",
]);
if (recordRequirement.requiredForMutationClass !== "mechanical-equivalent-refactor") {
  fail(`${manifestPath}.recordRequirement.requiredForMutationClass must be mechanical-equivalent-refactor`);
}
if (recordRequirement.emptyRecordsAllowedOnlyWhenNoRefactorInScope !== true) {
  fail(`${manifestPath}.recordRequirement.emptyRecordsAllowedOnlyWhenNoRefactorInScope must be true`);
}

const requiredEvidenceFields = requireArray(manifest, manifestPath, "requiredEvidenceFields");
const requiredEvidenceFieldSet = new Set(requiredEvidenceFields);
for (const field of [
  "beforeSnapshotReference",
  "beforeSnapshotHash",
  "afterSnapshotReference",
  "afterSnapshotHash",
  "geometryBeforeReference",
  "geometryAfterReference",
  "copyBeforeReference",
  "copyAfterReference",
  "tokenDiffStatus",
  "approvedByUserAt",
  "approvedScope",
]) {
  if (!requiredEvidenceFieldSet.has(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}
const requiredApprovedScopeFields = requireArray(manifest, manifestPath, "requiredApprovedScopeFields");
const requiredApprovedScopeFieldSet = new Set(requiredApprovedScopeFields);
for (const field of ["scopeId", "approvedBy", "approvedAt", "privateApprovalReference"]) {
  if (!requiredApprovedScopeFieldSet.has(field)) fail(`${manifestPath}.requiredApprovedScopeFields must include ${field}`);
}
const requiredPrivateEvidenceFields = requireArray(manifest, manifestPath, "requiredPrivateEvidenceFields");
const requiredPrivateEvidenceFieldSet = new Set(requiredPrivateEvidenceFields);
for (const field of ["recordId", "platform", "status", "privateEvidenceReference"]) {
  if (!requiredPrivateEvidenceFieldSet.has(field)) fail(`${manifestPath}.requiredPrivateEvidenceFields must include ${field}`);
}

const tokenStatuses = new Set(requireArray(manifest, manifestPath, "allowedTokenDiffStatuses"));
for (const status of ["no-token-diff", "approved-token-diff"]) {
  if (!tokenStatuses.has(status)) fail(`${manifestPath}.allowedTokenDiffStatuses must include ${status}`);
}

const equivalenceStatuses = new Set(requireArray(manifest, manifestPath, "equivalenceStatuses"));
for (const status of ["pending-private-evidence", "verified-equivalent", "blocked-visible-diff"]) {
  if (!equivalenceStatuses.has(status)) fail(`${manifestPath}.equivalenceStatuses must include ${status}`);
}
const mergeBlockingStatuses = new Set(requireArray(recordRequirement, `${manifestPath}.recordRequirement`, "mergeBlockingStatuses"));
for (const status of ["pending-private-evidence", "blocked-visible-diff"]) {
  if (!mergeBlockingStatuses.has(status)) fail(`${manifestPath}.recordRequirement.mergeBlockingStatuses must include ${status}`);
}
if (recordRequirement.requiredPassingStatus !== "verified-equivalent") {
  fail(`${manifestPath}.recordRequirement.requiredPassingStatus must be verified-equivalent`);
}

const records = requireArray(manifest, manifestPath, "records", { nonEmpty: false });
for (const [index, record] of records.entries()) {
  const label = `${manifestPath}.records[${index}]`;
  requireFields(record, label, [
    "id",
    "status",
    "scope",
    "platforms",
    "changedFiles",
    ...requiredEvidenceFields,
  ]);
  if (!equivalenceStatuses.has(record.status)) fail(`${label}.status is invalid`);
  if (!tokenStatuses.has(record.tokenDiffStatus)) fail(`${label}.tokenDiffStatus is invalid`);
  requireIsoTimestamp(record.approvedByUserAt, `${label}.approvedByUserAt`);
  requireApprovedScope(record.approvedScope, requiredApprovedScopeFields, `${label}.approvedScope`);
  for (const field of [
    "beforeSnapshotReference",
    "afterSnapshotReference",
    "geometryBeforeReference",
    "geometryAfterReference",
    "copyBeforeReference",
    "copyAfterReference",
  ]) {
    requireAlias(record[field], manifest.privateEvidenceAlias, `${label}.${field}`);
  }
  for (const hashField of ["beforeSnapshotHash", "afterSnapshotHash"]) {
    if (typeof record[hashField] !== "string" || record[hashField].length < 16) {
      fail(`${label}.${hashField} must record a private evidence hash`);
    }
  }
  requireArray(record, label, "platforms");
  requireArray(record, label, "changedFiles");
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI mechanical equivalence check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI mechanical equivalence check passed (${records.length} records)`);
