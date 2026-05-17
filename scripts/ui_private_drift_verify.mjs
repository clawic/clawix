#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { privateRootEnvForAlias } from "./ui_private_root_contract.mjs";
import { assertApprovedScopeMetadata, loadApprovedScopeContract } from "./ui_private_approved_scope_contract.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

function fail(message) {
  errors.push(message);
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

function optionValue(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  return args[index + 1] || null;
}

function hasFlag(name) {
  return args.includes(name);
}

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return false;
  }
  return true;
}

function relativePathFromReference(reference, alias) {
  const prefix = `${alias}:`;
  if (typeof reference !== "string" || !reference.startsWith(prefix)) return null;
  const suffix = reference.slice(prefix.length);
  if (!suffix || suffix.includes("..") || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || /^[A-Z]:\\/.test(suffix)) return null;
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
  assertApprovedScopeMetadata(value, label, approvedScopeContract, fail);
}

function verifyDriftResults(evidence, report, label, allowedStatuses) {
  if (!evidence.driftResults || typeof evidence.driftResults !== "object" || Array.isArray(evidence.driftResults)) {
    fail(`${label}.driftResults must be an object keyed by drift category`);
    return;
  }
  for (const category of report.driftCategories || []) {
    const result = evidence.driftResults[category];
    const resultLabel = `${label}.driftResults.${category}`;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      fail(`${resultLabel} must be an object`);
      continue;
    }
    if (typeof result.status !== "string" || !allowedStatuses.has(result.status)) {
      fail(`${resultLabel}.status is invalid`);
    }
    if (evidence.status !== "pending-private-evidence" && result.status === "pending-private-evidence") {
      fail(`${resultLabel}.status must not be pending when the report is approved`);
    }
    assertHash(result.resultHash, `${resultLabel}.resultHash`);
  }
}

function failReport(report, label, reason) {
  const proposalPath = visualModelAllowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md";
  fail([
    `${label} rendered drift evidence is not approved`,
    `route: ${report.coverageId || label}`,
    `privateDriftReportReference: ${report.privateDriftReportReference || "missing"}`,
    `reason: ${reason}`,
    "required permission: approved private rendered drift evidence from a visual-authorized lane",
    `proposal route: ${proposalPath}`,
  ].join("; "));
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");
const manifest = readJson("docs/ui/rendered-drift.manifest.json");
const visualModelAllowlist = readJson("docs/ui/visual-model-allowlist.manifest.json");
const approvedScopeContract = loadApprovedScopeContract(rootDir, fail);
const alias = manifest?.privateDriftAlias || "private-codex-ui-rendered-drift";
const privateRootEnv = privateRootEnvForAlias(rootDir, alias);

if (!requireApproved) {
  console.error("UI private drift verification requires --require-approved.");
  process.exit(1);
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env[privateRootEnv] || "";
if (!privateRootRaw) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} or pass --root to verify private rendered drift reports.`);
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private drift root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private drift root does not exist: ${privateRoot}`);
}

const evidenceFilename = manifest?.evidenceFilename || "drift-report.json";
const allowedStatuses = new Set(Array.isArray(manifest?.reportStatuses) ? manifest.reportStatuses : []);
const blockingStatuses = new Set(Array.isArray(manifest?.blockingReportStatuses) ? manifest.blockingReportStatuses : []);
const approvalRequiredStatuses = new Set(Array.isArray(manifest?.approvalRequiredStatuses) ? manifest.approvalRequiredStatuses : []);
const requiredEvidenceFields = Array.isArray(manifest?.requiredEvidenceFields) ? manifest.requiredEvidenceFields : [];
const approvedDriftEvidenceFields = Array.isArray(manifest?.approvedDriftEvidenceFields)
  ? manifest.approvedDriftEvidenceFields
  : [];
let verified = 0;
let pending = 0;

for (const [index, report] of (manifest?.reports || []).entries()) {
  const label = `${report.platform || "unknown"}:${report.coverageId || index}`;
  if (blockingStatuses.has(report.status)) {
    pending += 1;
    if (!includePending) {
      if (requireApproved) failReport(report, label, report.status === "drift-detected" ? "drift detected" : "pending private evidence");
      continue;
    }
  }
  if (!allowedStatuses.has(report.status)) fail(`${label}.status is invalid`);
  const relativeEvidenceDir = relativePathFromReference(report.privateDriftReportReference, alias);
  if (!relativeEvidenceDir) {
    fail(`${label} has invalid privateDriftReportReference`);
    continue;
  }
  const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;
  for (const field of requiredEvidenceFields) requireField(evidence, `${label} evidence`, field);
  if (approvalRequiredStatuses.has(evidence.status)) {
    for (const field of approvedDriftEvidenceFields) requireField(evidence, `${label} evidence`, field);
    assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
    assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
  }
  assertIsoTimestamp(evidence.producedAt, `${label}.producedAt`);
  if (evidence.coverageId !== report.coverageId) fail(`${label}.coverageId must match the public manifest`);
  if (evidence.platform !== report.platform) fail(`${label}.platform must match the public manifest`);
  if (evidence.status !== report.status) fail(`${label}.status must match the public manifest`);
  if (evidence.privateDriftReportReference !== report.privateDriftReportReference) {
    fail(`${label}.privateDriftReportReference must match the public manifest`);
  }
  assertHash(evidence.reportHash, `${label}.reportHash`);
  const categories = new Set(Array.isArray(evidence.driftCategories) ? evidence.driftCategories : []);
  for (const category of report.driftCategories || []) {
    if (!categories.has(category)) fail(`${label}.driftCategories must include ${category}`);
  }
  verifyDriftResults(evidence, report, label, allowedStatuses);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private drift verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private drift verification passed (${verified} verified, ${pending} pending)`);
