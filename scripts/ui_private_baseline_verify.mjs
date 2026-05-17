#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { privateRootEnvForAlias } from "./ui_private_root_contract.mjs";
import { assertApprovedScopeMetadata, loadApprovedScopeContract } from "./ui_private_approved_scope_contract.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/ui/private-baselines.manifest.json";
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

const requireApproved = hasFlag("--require-approved");
const verifyPending = hasFlag("--include-pending");
const manifest = readJson(manifestPath);
const approvedScopeContract = loadApprovedScopeContract(rootDir, fail);
const alias = manifest?.privateRootAlias || "private-codex-ui-baselines";
const privateRootEnv = privateRootEnvForAlias(rootDir, alias);

if (!requireApproved) {
  console.error("UI private baseline verification requires --require-approved.");
  process.exit(1);
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env[privateRootEnv] || "";
if (!privateRootRaw) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} or pass --root to verify private UI baselines.`);
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private baseline root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private baseline root does not exist: ${privateRoot}`);
}

const surfaceCoverage = readJson("docs/ui/surface-baseline-coverage.manifest.json");
const evidenceFilename = manifest?.evidenceFilename || "evidence.json";
const surfaceEvidenceFilename = surfaceCoverage?.surfaceEvidenceFilename || "surface-evidence.json";
let verifiedFlows = 0;
let verifiedSurfaces = 0;
let pendingFlows = 0;
let pendingSurfaces = 0;

if (Array.isArray(manifest?.flows)) {
  for (const flow of manifest.flows) {
    const label = `${flow.platform}:${flow.id}`;
    if (flow.baselineStatus !== "approved") {
      pendingFlows += 1;
      if (!verifyPending) {
        if (requireApproved) fail(`${label} is pending approved baseline capture`);
        continue;
      }
    }
    if (requireApproved && flow.baselineStatus !== "approved") {
      fail(`${label} is not approved`);
      continue;
    }

    const relativeEvidenceDir = relativePathFromReference(flow.privateBaselineReference, alias);
    if (!relativeEvidenceDir) {
      fail(`${label} has invalid privateBaselineReference`);
      continue;
    }
    const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
    const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
    if (!evidence) continue;

    for (const field of flow.requiredEvidence || []) {
      requireField(evidence, `${label} evidence`, field);
    }
    assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
    assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
    assertHash(evidence.geometryHash, `${label}.geometryHash`);
    assertHash(evidence.screenshotHash, `${label}.screenshotHash`);
    assertHash(evidence.baselineArtifactHash, `${label}.baselineArtifactHash`);
    if (String(evidence.privateBaselineReference || "") !== flow.privateBaselineReference) {
      fail(`${label}.privateBaselineReference must match the public manifest`);
    }
    if (evidence.platform !== flow.platform) fail(`${label}.platform must match the public manifest`);
    if (evidence.flowId !== flow.id) fail(`${label}.flowId must match the public manifest`);
    verifiedFlows += 1;
  }
} else {
  fail(`${manifestPath}.flows must be an array`);
}

if (Array.isArray(surfaceCoverage?.coverage)) {
  for (const [index, entry] of surfaceCoverage.coverage.entries()) {
    const label = `surface:${entry.platform || "unknown"}:${entry.coverageId || index}`;
    if (entry.baselineStatus !== "approved") {
      pendingSurfaces += 1;
      if (!verifyPending) {
        if (requireApproved) fail(`${label} is pending approved surface baseline capture`);
        continue;
      }
    }
    if (requireApproved && entry.baselineStatus !== "approved") {
      fail(`${label} is not approved`);
      continue;
    }

    const relativeEvidenceDir = relativePathFromReference(entry.privateBaselineReference, alias);
    if (!relativeEvidenceDir) {
      fail(`${label} has invalid privateBaselineReference`);
      continue;
    }
    const evidencePath = path.join(privateRoot, relativeEvidenceDir, surfaceEvidenceFilename);
    const evidence = readJsonFile(evidencePath, `${label} ${surfaceEvidenceFilename}`);
    if (!evidence) continue;

    for (const field of entry.requiredEvidence || []) {
      requireField(evidence, `${label} evidence`, field);
    }
    assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
    assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
    assertHash(evidence.geometryHash, `${label}.geometryHash`);
    assertHash(evidence.screenshotHash, `${label}.screenshotHash`);
    assertHash(evidence.copySnapshotHash, `${label}.copySnapshotHash`);
    assertHash(evidence.baselineArtifactHash, `${label}.baselineArtifactHash`);
    if (String(evidence.privateBaselineReference || "") !== entry.privateBaselineReference) {
      fail(`${label}.privateBaselineReference must match the surface coverage manifest`);
    }
    if (evidence.platform !== entry.platform) fail(`${label}.platform must match the surface coverage manifest`);
    if (evidence.coverageId !== entry.coverageId) fail(`${label}.coverageId must match the surface coverage manifest`);
    verifiedSurfaces += 1;
  }
} else {
  fail("docs/ui/surface-baseline-coverage.manifest.json.coverage must be an array");
}

if (errors.length > 0) {
  console.error("UI private baseline verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  `UI private baseline verification passed (${verifiedFlows} flow baselines, ${verifiedSurfaces} surface baselines; ${pendingFlows} flow pending, ${pendingSurfaces} surface pending)`,
);
