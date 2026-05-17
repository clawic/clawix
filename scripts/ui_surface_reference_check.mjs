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

function isPublicSafeReference(reference) {
  if (typeof reference !== "string" || reference.length === 0) return false;
  if (path.isAbsolute(reference)) return false;
  if (reference.startsWith("~/") || reference.includes("\\") || reference.includes("/Users/")) return false;
  if (reference.startsWith("private-") || reference.includes(":")) return false;
  return true;
}

function referenceTarget(reference) {
  return reference.split("#", 1)[0];
}

function requireExistingReference(reference, label) {
  if (!isPublicSafeReference(reference)) {
    fail(`${label} must be a public-safe repo-relative reference`);
    return;
  }
  const target = referenceTarget(reference);
  if (!target) {
    fail(`${label} must include a file or directory target`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, target))) {
    fail(`${label} points to missing target ${target}`);
  }
}

const manifestPath = "docs/ui/surface-references.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "inventoryPath",
  "patternRegistryPath",
  "debtRegistryPath",
  "protectedSurfaceRegistryPath",
  "exceptionRegistryPath",
  "requiredReferenceKinds",
  "publicReferencePolicy",
]);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
for (const kind of ["pattern", "debt", "protected", "exception"]) {
  if (!requireArray(manifest, manifestPath, "requiredReferenceKinds").includes(kind)) {
    fail(`${manifestPath}.requiredReferenceKinds must include ${kind}`);
  }
}
requireFields(manifest?.publicReferencePolicy, `${manifestPath}.publicReferencePolicy`, [
  "allowRepoRelativePath",
  "allowMarkdownAnchor",
  "forbidAbsolutePath",
  "forbidHomePath",
  "forbidPrivateRootAlias",
]);
for (const [field, expected] of Object.entries({
  allowRepoRelativePath: true,
  allowMarkdownAnchor: true,
  forbidAbsolutePath: true,
  forbidHomePath: true,
  forbidPrivateRootAlias: true,
})) {
  if (manifest?.publicReferencePolicy?.[field] !== expected) {
    fail(`${manifestPath}.publicReferencePolicy.${field} must be ${expected}`);
  }
}

const inventoryPath = manifest?.inventoryPath || "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const registryPath = manifest?.patternRegistryPath || "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = new Set(requireArray(registry, registryPath, "patterns"));
const patternReferences = new Map();
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  const references = requireArray(pattern, patternPath, "canonicalReferences");
  for (const [index, reference] of references.entries()) {
    requireExistingReference(reference, `${patternPath}.canonicalReferences[${index}]`);
  }
  patternReferences.set(patternId, references);
}

const debtPath = manifest?.debtRegistryPath || "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
const debtIds = new Set(requireArray(debt, debtPath, "entries").map((entry) => entry.id));

const protectedPath = manifest?.protectedSurfaceRegistryPath || "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const protectedIds = new Set(requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).map((entry) => entry.id));

const exceptionPath = manifest?.exceptionRegistryPath || "docs/ui/exceptions.registry.json";
const exceptions = readJson(exceptionPath);
const exceptionIds = new Set(requireArray(exceptions, exceptionPath, "exceptions", { nonEmpty: false }).map((entry) => entry.id));

const seenCoverage = new Set();
for (const [index, entry] of requireArray(inventory, inventoryPath, "coverage").entries()) {
  const label = `${inventoryPath}.coverage[${index}]`;
  requireFields(entry, label, ["id", "classification", "scopes"]);
  if (seenCoverage.has(entry.id)) fail(`${label}.id duplicates ${entry.id}`);
  seenCoverage.add(entry.id);
  for (const [scopeIndex, scope] of requireArray(entry, label, "scopes").entries()) {
    requireExistingReference(scope.replace(/\*\*.*$/, "").replace(/\*.*$/, ""), `${label}.scopes[${scopeIndex}]`);
  }
  if (entry.classification === "pattern") {
    for (const patternId of requireArray(entry, label, "patterns")) {
      if (!patternIds.has(patternId)) fail(`${label}.patterns references unknown pattern ${patternId}`);
      if ((patternReferences.get(patternId) || []).length === 0) fail(`${label}.patterns ${patternId} has no canonical references`);
    }
  } else if (entry.classification === "debt") {
    for (const debtId of requireArray(entry, label, "debtIds")) {
      if (!debtIds.has(debtId)) fail(`${label}.debtIds references unknown debt ${debtId}`);
    }
  } else if (entry.classification === "protected") {
    for (const surfaceId of requireArray(entry, label, "surfaceIds")) {
      if (!protectedIds.has(surfaceId)) fail(`${label}.surfaceIds references unknown protected surface ${surfaceId}`);
    }
  } else if (entry.classification === "exception") {
    for (const exceptionId of requireArray(entry, label, "exceptionIds")) {
      if (!exceptionIds.has(exceptionId)) fail(`${label}.exceptionIds references unknown exception ${exceptionId}`);
    }
  } else {
    fail(`${label}.classification must be pattern, debt, protected, or exception`);
  }
}

if (errors.length > 0) {
  console.error("UI surface reference check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI surface reference check passed (${seenCoverage.size} surface coverage entries)`);
