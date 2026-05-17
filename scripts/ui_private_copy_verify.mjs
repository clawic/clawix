#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

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

function verifyCopyItems(value, label, allowedKinds) {
  if (!Array.isArray(value) || value.length === 0) {
    fail(`${label} must be a non-empty array`);
    return;
  }
  for (const [index, item] of value.entries()) {
    const itemLabel = `${label}[${index}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      fail(`${itemLabel} must be an object`);
      continue;
    }
    for (const field of ["kind", "textHash", "source"]) {
      if (typeof item[field] !== "string" || item[field] === "") {
        fail(`${itemLabel}.${field} must be a non-empty string`);
      }
    }
    if (typeof item.kind === "string" && !allowedKinds.has(item.kind)) {
      fail(`${itemLabel}.kind must be one of the restricted copy kinds`);
    }
    assertHash(item.textHash, `${itemLabel}.textHash`);
  }
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");

if (!requireApproved) {
  console.error("UI private copy verification requires --require-approved.");
  process.exit(1);
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env.CLAWIX_UI_PRIVATE_COPY_ROOT || "";
if (!privateRootRaw) {
  console.error("EXTERNAL PENDING: set CLAWIX_UI_PRIVATE_COPY_ROOT or pass --root to verify private UI copy snapshots.");
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private copy root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private copy root does not exist: ${privateRoot}`);
}

const copyInventory = readJson("docs/ui/copy.inventory.json");
const protectedSurfaces = readJson("docs/ui/protected-surfaces.registry.json");
const alias = copyInventory?.privateSnapshotAlias || "private-codex-ui-copy-snapshots";
const evidenceFilename = copyInventory?.evidenceFilename || "copy-evidence.json";
const allowedCopyKinds = new Set(Array.isArray(copyInventory?.restrictedCopyKinds) ? copyInventory.restrictedCopyKinds : []);
let verified = 0;
let pending = 0;

const surfaceCoverage = readJson(copyInventory?.surfaceCoverageSource || "docs/ui/surface-baseline-coverage.manifest.json");
for (const [index, coverage] of (surfaceCoverage?.coverage || []).entries()) {
  const label = `surface coverage ${coverage.coverageId || index}`;
  if (coverage.baselineStatus !== "approved") {
    pending += 1;
    if (!includePending) {
      if (requireApproved) fail(`${label} is pending approved copy snapshot`);
      continue;
    }
  }
  requireField(coverage, label, "copySnapshotReference");
  const relativeEvidenceDir = relativePathFromReference(coverage.copySnapshotReference, alias);
  if (!relativeEvidenceDir) {
    fail(`${label} has invalid copySnapshotReference`);
    continue;
  }
  const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;
  for (const field of ["coverageId", "platform", "copySnapshotReference", "copySnapshotHash", "copyHierarchyHash", "approvedByUserAt", "approvedScope"]) {
    requireField(evidence, `${label} evidence`, field);
  }
  assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
  assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
  assertHash(evidence.copySnapshotHash, `${label}.copySnapshotHash`);
  assertHash(evidence.copyHierarchyHash, `${label}.copyHierarchyHash`);
  if (evidence.copySnapshotReference !== coverage.copySnapshotReference) {
    fail(`${label}.copySnapshotReference must match the surface baseline coverage manifest`);
  }
  if (evidence.coverageId !== coverage.coverageId) {
    fail(`${label}.coverageId must match the surface baseline coverage manifest`);
  }
  if (evidence.platform !== coverage.platform) {
    fail(`${label}.platform must match the surface baseline coverage manifest`);
  }
  verifyCopyItems(evidence.copyItems, `${label}.copyItems`, allowedCopyKinds);
  verified += 1;
}

const surfaces = Array.isArray(protectedSurfaces?.surfaces) ? protectedSurfaces.surfaces : [];
for (const [index, surface] of surfaces.entries()) {
  const label = `protected surface ${surface.id || index}`;
  if (requireApproved && !surface.approvedBy) {
    fail(`${label} is missing approvedBy`);
    continue;
  }
  requireField(surface, label, "copySnapshotReference");
  requireField(surface, label, "copySnapshotHash");

  const relativeEvidenceDir = relativePathFromReference(surface.copySnapshotReference, alias);
  if (!relativeEvidenceDir) {
    fail(`${label} has invalid copySnapshotReference`);
    continue;
  }
  const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;

  for (const field of copyInventory?.requiredEvidenceFields || []) {
    requireField(evidence, `${label} evidence`, field);
  }
  assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
  assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
  assertHash(evidence.copySnapshotHash, `${label}.copySnapshotHash`);
  assertHash(evidence.copyHierarchyHash, `${label}.copyHierarchyHash`);
  if (evidence.copySnapshotReference !== surface.copySnapshotReference) {
    fail(`${label}.copySnapshotReference must match the protected surface registry`);
  }
  if (evidence.copySnapshotHash !== surface.copySnapshotHash) {
    fail(`${label}.copySnapshotHash must match the protected surface registry`);
  }
  if (evidence.surfaceId !== surface.id) {
    fail(`${label}.surfaceId must match the protected surface registry`);
  }
  verifyCopyItems(evidence.copyItems, `${label}.copyItems`, allowedCopyKinds);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private copy verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private copy verification passed (${verified} snapshots, ${pending} pending)`);
