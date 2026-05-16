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

const manifestPath = "docs/ui/private-visual-validation.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "verificationCommand",
  "requiredRoots",
  "delegates",
  "externalPendingExitCode",
]);

if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_visual_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_visual_verify.mjs`);
}
if (manifest?.externalPendingExitCode !== 2) {
  fail(`${manifestPath}.externalPendingExitCode must be 2`);
}

const roots = new Set(requireArray(manifest, manifestPath, "requiredRoots"));
for (const root of [
  "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "CLAWIX_UI_PRIVATE_COPY_ROOT",
]) {
  if (!roots.has(root)) fail(`${manifestPath}.requiredRoots must include ${root}`);
}

const delegates = requireArray(manifest, manifestPath, "delegates");
for (const script of [
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
]) {
  if (!delegates.some((delegate) => String(delegate).includes(script))) {
    fail(`${manifestPath}.delegates must include ${script}`);
  }
}

for (const script of [
  "scripts/ui_private_visual_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
]) {
  if (!fs.existsSync(path.join(rootDir, script))) fail(`missing ${script}`);
}

if (errors.length > 0) {
  console.error("UI private visual validation manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private visual validation manifest check passed");
