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

function requireArray(object, label, field) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
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
  if (typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("file://") || /^[A-Z]:\\/.test(value))) {
    fail(`${label} must not contain a local path`);
  }
}

const manifestPath = "docs/ui/rendered-geometry.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "patternSource",
  "privateGeometryAlias",
  "evidenceFilename",
  "verificationCommand",
  "requiredEvidenceFields",
  "requiredSurfaceEvidenceFields",
  "publicRepoMustNotStore",
]);

if (manifest?.privateGeometryAlias !== "private-codex-ui-rendered-geometry") {
  fail(`${manifestPath}.privateGeometryAlias must be private-codex-ui-rendered-geometry`);
}
if (manifest?.evidenceFilename !== "geometry-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be geometry-evidence.json`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_geometry_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_geometry_verify.mjs`);
}

const requiredEvidence = new Set(requireArray(manifest, manifestPath, "requiredEvidenceFields"));
for (const field of ["patternId", "platform", "measurements", "geometryHash", "screenshotComparisonHash", "captureCommand", "approvedByUserAt", "approvedScope"]) {
  if (!requiredEvidence.has(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}
const requiredSurfaceEvidence = new Set(requireArray(manifest, manifestPath, "requiredSurfaceEvidenceFields"));
for (const field of ["coverageId", "platform", "measurements", "geometryHash", "screenshotComparisonHash", "captureCommand", "approvedByUserAt", "approvedScope"]) {
  if (!requiredSurfaceEvidence.has(field)) fail(`${manifestPath}.requiredSurfaceEvidenceFields must include ${field}`);
}

const registry = readJson(manifest?.patternSource || "");
requireArray(registry, manifest?.patternSource || "patternSource", "patterns");
scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI rendered geometry manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI rendered geometry manifest check passed");
