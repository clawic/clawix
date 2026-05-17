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

function requireRepoReference(reference, label) {
  if (typeof reference !== "string" || reference.length === 0) {
    fail(`${label} must be a repo-relative reference`);
    return;
  }
  if (path.isAbsolute(reference) || reference.startsWith("~/") || reference.includes("/Users/") || reference.includes(":")) {
    fail(`${label} must be public-safe and repo-relative`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, reference.split("#", 1)[0]))) {
    fail(`${label} points to missing target ${reference}`);
  }
}

const manifestPath = "docs/ui/canon-units.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "primaryUnit",
  "patternRegistry",
  "promotionRegistry",
  "approvalAuthority",
  "allowedUnitStatuses",
  "requiredUnitFields",
  "units",
]);
if (manifest?.primaryUnit !== "pattern") fail(`${manifestPath}.primaryUnit must be pattern`);
for (const field of ["patternRegistry", "promotionRegistry", "approvalAuthority"]) {
  requireRepoReference(manifest?.[field], `${manifestPath}.${field}`);
}

const statuses = new Set(requireArray(manifest, manifestPath, "allowedUnitStatuses"));
for (const status of ["candidate", "promoted", "revoked"]) {
  if (!statuses.has(status)) fail(`${manifestPath}.allowedUnitStatuses must include ${status}`);
}
const requiredFields = requireArray(manifest, manifestPath, "requiredUnitFields");
for (const field of ["id", "unitKind", "status", "source", "promotionRequired"]) {
  if (!requiredFields.includes(field)) fail(`${manifestPath}.requiredUnitFields must include ${field}`);
}

const unitsById = new Map();
for (const [index, unit] of requireArray(manifest, manifestPath, "units").entries()) {
  const label = `${manifestPath}.units[${index}]`;
  requireFields(unit, label, requiredFields);
  if (unitsById.has(unit.id)) fail(`${label}.id duplicates ${unit.id}`);
  unitsById.set(unit.id, unit);
  if (!statuses.has(unit.status)) fail(`${label}.status is invalid`);
  requireRepoReference(unit.source, `${label}.source`);
  if (unit.id === manifest.primaryUnit && unit.promotionRequired !== false) {
    fail(`${label}.promotionRequired must be false for the primary canon unit`);
  }
  if (unit.id !== manifest.primaryUnit && unit.promotionRequired !== true) {
    fail(`${label}.promotionRequired must be true for narrower canon units`);
  }
}
for (const requiredUnit of ["pattern", "component", "surface"]) {
  if (!unitsById.has(requiredUnit)) fail(`${manifestPath}.units must include ${requiredUnit}`);
}

const registry = readJson(manifest?.patternRegistry || "docs/ui/pattern-registry/patterns.registry.json");
const governanceConfig = readJson("docs/ui/interface-governance.config.json");
const allowedMutationClasses = new Set(requireArray(governanceConfig, "docs/ui/interface-governance.config.json", "mutationClasses"));
for (const patternId of requireArray(registry, manifest.patternRegistry, "patterns")) {
  const pattern = readJson(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json`);
  const mutationClasses = Array.isArray(pattern?.mutationClass)
    ? pattern.mutationClass
    : typeof pattern?.mutationClass === "string"
      ? [pattern.mutationClass]
      : [];
  if (mutationClasses.length === 0) {
    fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.mutationClass must be declared`);
  }
  for (const mutationClass of mutationClasses) {
    if (!allowedMutationClasses.has(mutationClass)) {
      fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.mutationClass contains unknown class ${mutationClass}`);
    }
  }
}

const promotions = readJson(manifest?.promotionRegistry || "docs/ui/canon-promotions.registry.json");
for (const [index, promotion] of requireArray(promotions, manifest.promotionRegistry, "promotions", { nonEmpty: false }).entries()) {
  const label = `${manifest.promotionRegistry}.promotions[${index}]`;
  requireFields(promotion, label, ["patterns", "privateApprovalReference"]);
  for (const patternId of requireArray(promotion, label, "patterns")) {
    if (!registry.patterns.includes(patternId)) fail(`${label}.patterns references unknown pattern ${patternId}`);
  }
}

if (errors.length > 0) {
  console.error("UI canon unit check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI canon unit check passed (${unitsById.size} units)`);
