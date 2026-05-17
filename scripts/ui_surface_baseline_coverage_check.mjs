#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
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

function requireAlias(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
    return null;
  }
  if (reference.includes("/Users/") || reference.startsWith("/") || reference.startsWith("~/") || reference.startsWith("file://") || /^[A-Z]:\\/.test(reference)) {
    fail(`${label} must not contain a local path`);
  }
  return suffix;
}

function requireHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

const manifestPath = "docs/ui/surface-baseline-coverage.manifest.json";
const manifest = readJson(manifestPath);
if (args.has("--simulate-mismatched-surface-reference") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0] = {
    ...manifest.coverage[0],
    privateBaselineReference: `${manifest.privateBaselineAlias}:surfaces/${manifest.coverage[0].platform}/wrong-surface`,
  };
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "inventoryPath",
  "privateBaselineAlias",
  "privateGeometryAlias",
  "privateCopyAlias",
  "surfaceEvidenceFilename",
  "allowedBaselineStatuses",
  "requiredEvidenceFields",
  "coverage",
]);
if (manifest?.surfaceEvidenceFilename !== "surface-evidence.json") {
  fail(`${manifestPath}.surfaceEvidenceFilename must be surface-evidence.json`);
}

const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
if (manifest?.privateBaselineAlias !== privateBaselines?.privateRootAlias) {
  fail(`${manifestPath}.privateBaselineAlias must match docs/ui/private-baselines.manifest.json`);
}
const renderedGeometry = readJson("docs/ui/rendered-geometry.manifest.json");
if (manifest?.privateGeometryAlias !== renderedGeometry?.privateGeometryAlias) {
  fail(`${manifestPath}.privateGeometryAlias must match docs/ui/rendered-geometry.manifest.json`);
}
const copyInventory = readJson("docs/ui/copy.inventory.json");
if (manifest?.privateCopyAlias !== copyInventory?.privateSnapshotAlias) {
  fail(`${manifestPath}.privateCopyAlias must match docs/ui/copy.inventory.json`);
}

const requiredEvidenceFields = new Set(requireArray(manifest, manifestPath, "requiredEvidenceFields"));
for (const field of [
  "coverageId",
  "platform",
  "privateBaselineReference",
  "captureCommand",
  "screenshotHash",
  "geometryHash",
  "copySnapshotHash",
  "baselineArtifactHash",
  "approvedByUserAt",
  "approvedScope",
]) {
  if (!requiredEvidenceFields.has(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}
const allowedStatuses = new Set(requireArray(manifest, manifestPath, "allowedBaselineStatuses"));

const inventoryPath = manifest?.inventoryPath || "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const inventoryById = new Map();
for (const entry of requireArray(inventory, inventoryPath, "coverage")) {
  inventoryById.set(entry.id, entry);
}

const seen = new Set();
for (const [index, entry] of requireArray(manifest, manifestPath, "coverage").entries()) {
  const label = `${manifestPath}.coverage[${index}]`;
  requireFields(entry, label, [
    "coverageId",
    "platform",
    "classification",
    "baselineStatus",
    "privateBaselineReference",
    "geometryEvidenceReference",
    "copySnapshotReference",
    "requiredEvidence",
  ]);
  if (seen.has(entry.coverageId)) fail(`${label}.coverageId duplicates ${entry.coverageId}`);
  seen.add(entry.coverageId);
  const inventoryEntry = inventoryById.get(entry.coverageId);
  if (!inventoryEntry) {
    fail(`${label}.coverageId is not listed in ${inventoryPath}`);
    continue;
  }
  if (entry.platform !== inventoryEntry.platform) fail(`${label}.platform must match ${inventoryPath}`);
  if (entry.classification !== inventoryEntry.classification) fail(`${label}.classification must match ${inventoryPath}`);
  if (!allowedStatuses.has(entry.baselineStatus)) fail(`${label}.baselineStatus is not allowed`);
  const expectedSurfaceReference = `surfaces/${entry.platform}/${entry.coverageId}`;
  const baselineReferenceSuffix = requireAlias(entry.privateBaselineReference, manifest.privateBaselineAlias, `${label}.privateBaselineReference`);
  const geometryReferenceSuffix = requireAlias(entry.geometryEvidenceReference, manifest.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  const copyReferenceSuffix = requireAlias(entry.copySnapshotReference, manifest.privateCopyAlias, `${label}.copySnapshotReference`);
  if (baselineReferenceSuffix && baselineReferenceSuffix !== expectedSurfaceReference) {
    fail(`${label}.privateBaselineReference must target ${expectedSurfaceReference}`);
  }
  if (geometryReferenceSuffix && geometryReferenceSuffix !== expectedSurfaceReference) {
    fail(`${label}.geometryEvidenceReference must target ${expectedSurfaceReference}`);
  }
  if (copyReferenceSuffix && copyReferenceSuffix !== expectedSurfaceReference) {
    fail(`${label}.copySnapshotReference must target ${expectedSurfaceReference}`);
  }
  const evidence = new Set(requireArray(entry, label, "requiredEvidence"));
  for (const field of requiredEvidenceFields) {
    if (!evidence.has(field)) fail(`${label}.requiredEvidence must include ${field}`);
  }
  if (entry.baselineStatus === "approved") {
    for (const hashField of ["screenshotHash", "geometryHash", "copySnapshotHash", "baselineArtifactHash"]) {
      requireHash(entry[hashField], `${label}.${hashField}`);
    }
  }
}

for (const coverageId of inventoryById.keys()) {
  if (!seen.has(coverageId)) fail(`${manifestPath}.coverage must include ${coverageId}`);
}

if (errors.length > 0) {
  console.error("UI surface baseline coverage check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI surface baseline coverage check passed (${seen.size} surface baselines)`);
