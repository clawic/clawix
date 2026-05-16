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
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
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
  }
}

function requireHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
requireFields(protectedSurfaces, protectedPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateBaselineAlias",
  "privateCopyAlias",
  "privateGeometryAlias",
  "requiredFreezeFields",
  "surfaces",
]);

for (const [field, expected] of [
  ["privateBaselineAlias", "private-codex-ui-baselines"],
  ["privateCopyAlias", "private-codex-ui-copy-snapshots"],
  ["privateGeometryAlias", "private-codex-ui-rendered-geometry"],
]) {
  if (protectedSurfaces?.[field] !== expected) fail(`${protectedPath}.${field} must be ${expected}`);
}

const requiredFreezeFields = requireArray(protectedSurfaces, protectedPath, "requiredFreezeFields");
const requiredFreezeFieldSet = new Set(requiredFreezeFields);
for (const field of [
  "id",
  "scope",
  "platform",
  "patterns",
  "approvedBy",
  "approvedAt",
  "contract",
  "privateBaselineReference",
  "privateBaselineHash",
  "copySnapshotReference",
  "copySnapshotHash",
  "geometryEvidenceReference",
  "geometryEvidenceHash",
  "changePolicy",
]) {
  if (!requiredFreezeFieldSet.has(field)) fail(`${protectedPath}.requiredFreezeFields must include ${field}`);
}

const registry = readJson("docs/ui/pattern-registry/patterns.registry.json");
const patternIds = new Set(requireArray(registry, "docs/ui/pattern-registry/patterns.registry.json", "patterns"));

const surfaces = requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false });
const ids = new Set();
for (const [index, surface] of surfaces.entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, requiredFreezeFields);
  if (ids.has(surface.id)) fail(`${label}.id duplicates ${surface.id}`);
  ids.add(surface.id);
  if (!requiredPlatforms.has(surface.platform)) fail(`${label}.platform is not governed`);
  if (surface.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  for (const pattern of requireArray(surface, label, "patterns")) {
    if (!patternIds.has(pattern)) fail(`${label}.patterns references unknown pattern ${pattern}`);
  }
  requireFields(surface.contract, `${label}.contract`, ["geometry", "copy", "states", "performance"]);
  requireAlias(surface.privateBaselineReference, protectedSurfaces.privateBaselineAlias, `${label}.privateBaselineReference`);
  requireAlias(surface.copySnapshotReference, protectedSurfaces.privateCopyAlias, `${label}.copySnapshotReference`);
  requireAlias(surface.geometryEvidenceReference, protectedSurfaces.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  requireHash(surface.privateBaselineHash, `${label}.privateBaselineHash`);
  requireHash(surface.copySnapshotHash, `${label}.copySnapshotHash`);
  requireHash(surface.geometryEvidenceHash, `${label}.geometryEvidenceHash`);
  requireFields(surface.changePolicy, `${label}.changePolicy`, [
    "requiresExplicitUserApproval",
    "requiresVisualModelAllowlist",
    "requiresScopeBudget",
  ]);
  if (surface.changePolicy.requiresExplicitUserApproval !== true) {
    fail(`${label}.changePolicy.requiresExplicitUserApproval must be true`);
  }
  if (surface.changePolicy.requiresVisualModelAllowlist !== true) {
    fail(`${label}.changePolicy.requiresVisualModelAllowlist must be true`);
  }
  if (surface.changePolicy.requiresScopeBudget !== true) {
    fail(`${label}.changePolicy.requiresScopeBudget must be true`);
  }
}

scanForLocalPaths(protectedSurfaces, protectedPath);

if (errors.length > 0) {
  console.error("UI protected surface check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI protected surface check passed (${surfaces.length} protected surfaces)`);
