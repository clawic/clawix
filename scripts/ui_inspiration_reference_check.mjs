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

const registryPath = "docs/ui/inspiration/references.registry.json";
const registry = readJson(registryPath);
requireFields(registry, registryPath, ["schemaVersion", "policy", "references"]);

const policy = String(registry?.policy || "").toLowerCase();
for (const phrase of ["inspiration", "non-canonical", "explicitly approves"]) {
  if (!policy.includes(phrase)) fail(`${registryPath}.policy must mention ${phrase}`);
}

const references = requireArray(registry, registryPath, "references");
const seenIds = new Set();
for (const [index, reference] of references.entries()) {
  const label = `${registryPath}.references[${index}]`;
  requireFields(reference, label, ["id", "url", "use", "canonical"]);
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(String(reference.id || ""))) {
    fail(`${label}.id must be a stable slug`);
  }
  if (seenIds.has(reference.id)) fail(`${label}.id duplicates ${reference.id}`);
  seenIds.add(reference.id);
  let url = null;
  try {
    url = new URL(reference.url);
  } catch {
    fail(`${label}.url must be a valid URL`);
  }
  if (url && url.protocol !== "https:") fail(`${label}.url must use https`);
  if (reference.canonical !== false) fail(`${label}.canonical must remain false`);
  if (String(reference.use || "").toLowerCase().includes("canonical")) {
    fail(`${label}.use must not describe the reference as canonical`);
  }
}

const patternRegistry = readJson("docs/ui/pattern-registry/patterns.registry.json");
for (const patternId of requireArray(patternRegistry, "docs/ui/pattern-registry/patterns.registry.json", "patterns")) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  for (const [index, reference] of requireArray(pattern, patternPath, "canonicalReferences").entries()) {
    if (String(reference).startsWith("http://") || String(reference).startsWith("https://")) {
      fail(`${patternPath}.canonicalReferences[${index}] must not point to an external inspiration URL`);
    }
  }
}

scanForLocalPaths(registry, registryPath);

if (errors.length > 0) {
  console.error("UI inspiration reference check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI inspiration reference check passed (${seenIds.size} references)`);
