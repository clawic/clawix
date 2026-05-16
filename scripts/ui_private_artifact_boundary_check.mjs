#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const uiDir = path.join(rootDir, "docs/ui");
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

function requireField(object, label, field, expected) {
  if (!object || object[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return;
  }
  if (expected !== undefined && object[field] !== expected) {
    fail(`${label}.${field} must be ${expected}`);
  }
}

function walk(directory) {
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(absolute));
    if (entry.isFile()) files.push(absolute);
  }
  return files;
}

function scanValue(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanValue(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanValue(child, `${label}.${key}`);
    return;
  }
  if (typeof value !== "string") return;
  if (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not contain a local private path`);
  }
  if (/BEGIN [A-Z ]*PRIVATE KEY/.test(value) || /\bAKIA[0-9A-Z]{16}\b/.test(value) || /\bsk-[A-Za-z0-9]{20,}\b/.test(value)) {
    fail(`${label} looks like a secret`);
  }
}

const forbiddenExtensions = new Set([
  ".apng",
  ".avif",
  ".gif",
  ".heic",
  ".jpeg",
  ".jpg",
  ".mov",
  ".mp4",
  ".pdf",
  ".png",
  ".trace",
  ".webm",
  ".webp",
  ".zip",
]);

for (const file of walk(uiDir)) {
  const relativePath = path.relative(rootDir, file);
  const extension = path.extname(file).toLowerCase();
  if (forbiddenExtensions.has(extension)) {
    fail(`${relativePath} must not store private visual evidence in the public repo`);
  }
  const content = fs.readFileSync(file, "utf8");
  if (/\/Users\/|file:\/\/|BEGIN [A-Z ]*PRIVATE KEY|\bAKIA[0-9A-Z]{16}\b|\bsk-[A-Za-z0-9]{20,}\b/.test(content)) {
    fail(`${relativePath} contains a private path or secret-like token`);
  }
  if (extension === ".json") scanValue(JSON.parse(content), relativePath);
}

const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
requireField(privateBaselines, "docs/ui/private-baselines.manifest.json", "privateRootAlias", "private-codex-ui-baselines");

const renderedGeometry = readJson("docs/ui/rendered-geometry.manifest.json");
requireField(renderedGeometry, "docs/ui/rendered-geometry.manifest.json", "privateGeometryAlias", "private-codex-ui-rendered-geometry");

const copyInventory = readJson("docs/ui/copy.inventory.json");
requireField(copyInventory, "docs/ui/copy.inventory.json", "privateSnapshotAlias", "private-codex-ui-copy-snapshots");

const renderedDrift = readJson("docs/ui/rendered-drift.manifest.json");
requireField(renderedDrift, "docs/ui/rendered-drift.manifest.json", "privateDriftAlias", "private-codex-ui-rendered-drift");

const visualModelAllowlist = readJson("docs/ui/visual-model-allowlist.manifest.json");
requireField(visualModelAllowlist, "docs/ui/visual-model-allowlist.manifest.json", "privateAssignment", "outside-public-repo");

const visualScopes = readJson("docs/ui/visual-change-scopes.manifest.json");
requireField(visualScopes, "docs/ui/visual-change-scopes.manifest.json", "privateModelAssignment", "outside-public-repo");

const privateValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const requiredRoots = new Set(Array.isArray(privateValidation?.requiredRoots) ? privateValidation.requiredRoots : []);
for (const root of [
  "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "CLAWIX_UI_PRIVATE_COPY_ROOT",
]) {
  if (!requiredRoots.has(root)) fail("docs/ui/private-visual-validation.manifest.json.requiredRoots is missing " + root);
}

if (errors.length > 0) {
  console.error("UI private artifact boundary check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private artifact boundary check passed");
