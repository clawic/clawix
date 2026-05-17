#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

function fail(message) {
  errors.push(message);
}

function optionValue(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  return args[index + 1] || null;
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

function readJson(relativePath) {
  return readJsonFile(path.join(rootDir, relativePath), relativePath);
}

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
  }
}

function relativePathFromReference(reference, alias) {
  const prefix = `${alias}:`;
  if (typeof reference !== "string" || !reference.startsWith(prefix)) return null;
  const suffix = reference.slice(prefix.length);
  if (!suffix || suffix.includes("..") || suffix.startsWith("/") || suffix.startsWith("\\")) return null;
  return suffix.split("/").join(path.sep);
}

function assertHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function assertIsoTimestamp(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function assertApprovedScope(value, label) {
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

function verifyFindingItems(evidence, label) {
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
    assertHash(item.itemHash, `${itemLabel}.itemHash`);
  }
}

if (!hasFlag("--require-approved")) {
  console.error("UI private debt audit verification requires --require-approved.");
  process.exit(1);
}

const privateRootRaw = optionValue("--root") || process.env.CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT || "";
if (!privateRootRaw) {
  console.error("EXTERNAL PENDING: set CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT or pass --root to verify private UI debt audit evidence.");
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private debt audit root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private debt audit root does not exist: ${privateRoot}`);
}

const manifest = readJson("docs/ui/debt-audit.manifest.json");
const alias = manifest?.privateDebtAuditAlias || "private-codex-ui-debt-audit";
const evidenceFilename = manifest?.evidenceFilename || "debt-audit-evidence.json";
let verified = 0;

for (const [index, entry] of (manifest?.entries || []).entries()) {
  const label = `${entry.debtId || index}`;
  const relativeEvidenceDir = relativePathFromReference(entry.privateDebtAuditReference, alias);
  if (!relativeEvidenceDir) {
    fail(`${label}.privateDebtAuditReference is invalid`);
    continue;
  }
  const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;

  for (const field of entry.requiredEvidence || []) requireField(evidence, `${label} evidence`, field);
  assertIsoTimestamp(evidence.auditedAt, `${label}.auditedAt`);
  assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
  assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
  if (evidence.debtId !== entry.debtId) fail(`${label}.debtId must match the public audit manifest`);
  if (evidence.platform !== entry.platforms?.[0]) fail(`${label}.platform must match the public audit manifest`);
  if (evidence.scope !== entry.scope) fail(`${label}.scope must match the public audit manifest`);
  if (JSON.stringify(evidence.platforms || []) !== JSON.stringify(entry.platforms || [])) {
    fail(`${label}.platforms must match the public audit manifest`);
  }
  if (evidence.privateDebtAuditReference !== entry.privateDebtAuditReference) {
    fail(`${label}.privateDebtAuditReference must match the public audit manifest`);
  }
  assertHash(evidence.findingHash, `${label}.findingHash`);
  assertHash(evidence.visualInventoryHash, `${label}.visualInventoryHash`);
  verifyFindingItems(evidence, label);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private debt audit verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private debt audit verification passed (${verified} debt audit entries)`);
