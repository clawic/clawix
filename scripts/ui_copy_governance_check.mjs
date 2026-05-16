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

function isPublicSafeReference(value, alias) {
  return typeof value === "string" && value.startsWith(`${alias}:`) && !value.startsWith("/") && !value.includes("/Users/");
}

const copyPath = "docs/ui/copy.inventory.json";
const copyInventory = readJson(copyPath);
requireFields(copyInventory, copyPath, [
  "schemaVersion",
  "status",
  "policy",
  "patternCopySource",
  "privateSnapshotAlias",
  "protectedSurfaceRequirement",
  "restrictedCopyKinds",
  "requiredEvidenceFields",
]);

const requiredCopyKinds = [
  "visible-name",
  "label",
  "placeholder",
  "tooltip",
  "microcopy",
  "empty-state",
  "loading-state",
  "error-state",
  "copy-hierarchy",
];
const copyKinds = new Set(requireArray(copyInventory, copyPath, "restrictedCopyKinds"));
for (const kind of requiredCopyKinds) {
  if (!copyKinds.has(kind)) fail(`${copyPath}.restrictedCopyKinds must include ${kind}`);
}

const requiredEvidence = ["copySnapshotReference", "copySnapshotHash", "approvedByUserAt", "approvedScope"];
const evidence = new Set(requireArray(copyInventory, copyPath, "requiredEvidenceFields"));
for (const field of requiredEvidence) {
  if (!evidence.has(field)) fail(`${copyPath}.requiredEvidenceFields must include ${field}`);
}

const registryPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = requireArray(registry, registryPath, "patterns");
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (!pattern) continue;
  const copy = pattern.copy;
  if (!copy || typeof copy !== "object" || Array.isArray(copy) || Object.keys(copy).length === 0) {
    fail(`${patternPath}.copy must declare a non-empty copy contract`);
    continue;
  }
  for (const [key, value] of Object.entries(copy)) {
    if (!/^[a-z][A-Za-z0-9]*$/.test(key)) {
      fail(`${patternPath}.copy.${key} must use stable lowerCamelCase naming`);
    }
    if (typeof value === "number" && (!Number.isFinite(value) || value < 0)) {
      fail(`${patternPath}.copy.${key} must be a finite non-negative number`);
    } else if (!["boolean", "number", "string"].includes(typeof value)) {
      fail(`${patternPath}.copy.${key} must be a boolean, number, or string`);
    }
  }
}

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const privateAlias = copyInventory?.privateSnapshotAlias || "";
for (const [index, surface] of requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, ["copySnapshotReference", "copySnapshotHash"]);
  if (!isPublicSafeReference(surface.copySnapshotReference, privateAlias)) {
    fail(`${label}.copySnapshotReference must use ${privateAlias}: and must not contain a local path`);
  }
  if (typeof surface.copySnapshotHash !== "string" || surface.copySnapshotHash.length < 16) {
    fail(`${label}.copySnapshotHash must record the approved private copy snapshot hash`);
  }
}

if (errors.length > 0) {
  console.error("UI copy governance check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI copy governance check passed (${patternIds.length} pattern copy contracts)`);
