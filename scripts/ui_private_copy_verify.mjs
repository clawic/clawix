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
const requireApproved = hasFlag("--require-approved");
let verified = 0;

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
  assertHash(evidence.copySnapshotHash, `${label}.copySnapshotHash`);
  if (evidence.copySnapshotReference !== surface.copySnapshotReference) {
    fail(`${label}.copySnapshotReference must match the protected surface registry`);
  }
  if (evidence.copySnapshotHash !== surface.copySnapshotHash) {
    fail(`${label}.copySnapshotHash must match the protected surface registry`);
  }
  if (evidence.surfaceId !== surface.id) {
    fail(`${label}.surfaceId must match the protected surface registry`);
  }
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private copy verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private copy verification passed (${verified} protected surface snapshots)`);
