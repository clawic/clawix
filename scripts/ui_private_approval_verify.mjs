#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { privateRootEnvForAlias } from "./ui_private_root_contract.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

function fail(message) {
  errors.push(message);
}

function hasFlag(name) {
  return args.includes(name);
}

function readJsonFile(file, label) {
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
  return readJsonFile(path.join(rootDir, relativePath), relativePath);
}

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
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

function splitReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) return null;
  if (reference.includes("/Users/") || reference.startsWith("file://")) return null;
  return { alias, suffix };
}

function assertIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function assertHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function approvalRecords(manifest) {
  const records = [];
  for (const [sourceIndex, source] of requireArray(manifest, "docs/ui/approval-authority.manifest.json", "approvalSources").entries()) {
    const sourceLabel = `docs/ui/approval-authority.manifest.json.approvalSources[${sourceIndex}]`;
    for (const field of ["id", "path", "arrayField", "privateApprovalField"]) requireField(source, sourceLabel, field);
    if (!source?.path || !source?.arrayField || !source?.privateApprovalField) continue;
    const registry = readRepoJson(source.path);
    const approvalRequiredStatuses = Array.isArray(source.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const [recordIndex, record] of requireArray(registry, source.path, source.arrayField, { nonEmpty: false }).entries()) {
      if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) continue;
      records.push({
        source,
        record,
        label: `${source.path}.${source.arrayField}[${recordIndex}]`,
      });
    }
  }
  return records;
}

if (!hasFlag("--require-approved")) {
  console.error("UI private approval verification requires --require-approved.");
  process.exit(1);
}

const manifest = readRepoJson("docs/ui/approval-authority.manifest.json");
const alias = manifest?.privateApprovalAlias;
const evidenceFilename = manifest?.evidenceFilename || "approval-evidence.json";
const requiredEvidenceFields = manifest?.requiredPrivateApprovalEvidenceFields || [];
const approvalEntries = approvalRecords(manifest);
const approvals = [];

for (const { source, record, label } of approvalEntries) {
  const reference = record?.[source.privateApprovalField];
  if (!reference) {
    fail(`${label}.${source.privateApprovalField} is required for private approval verification`);
    continue;
  }
  approvals.push({ source, record, label });
}

if (errors.length > 0) {
  console.error("UI private approval verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (approvals.length === 0) {
  console.log("UI private approval verification passed (0 approval records)");
  process.exit(0);
}

let privateRootEnv;
try {
  privateRootEnv = privateRootEnvForAlias(rootDir, alias);
} catch (error) {
  fail(error.message);
}
if (!privateRootEnv || !process.env[privateRootEnv]) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} to verify private approval evidence.`);
  process.exit(2);
}

const privateRoot = path.resolve(process.env[privateRootEnv]);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail(`${privateRootEnv} must point outside the public repository`);
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`${privateRootEnv} does not point to an existing directory`);
}

let verified = 0;
for (const { source, record, label } of approvals) {
  const reference = record[source.privateApprovalField];
  const parsed = splitReference(reference);
  if (!parsed || parsed.alias !== alias) {
    fail(`${label}.${source.privateApprovalField} must use ${alias}:`);
    continue;
  }

  const evidencePath = path.join(privateRoot, parsed.suffix.split("/").join(path.sep), evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;
  for (const field of requiredEvidenceFields) requireField(evidence, `${label} evidence`, field);
  if (evidence.sourceId !== source.id) fail(`${label}.sourceId must match ${source.id}`);
  if (evidence.privateApprovalReference !== reference) {
    fail(`${label}.privateApprovalReference must match public approval reference`);
  }
  if (evidence.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  if (record.approvedBy !== undefined && evidence.approvedBy !== record.approvedBy) {
    fail(`${label}.approvedBy must match public approval record`);
  }
  assertIsoDate(evidence.approvedAt, `${label}.approvedAt`);
  if (record.approvedAt !== undefined && evidence.approvedAt !== record.approvedAt) {
    fail(`${label}.approvedAt must match public approval record`);
  }
  assertHash(evidence.approvalHash, `${label}.approvalHash`);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private approval verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private approval verification passed (${verified} approval records)`);
