#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const content = read(relativePath);
  if (!content) return null;
  try {
    return JSON.parse(content);
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

function scanPublicSafety(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanPublicSafety(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanPublicSafety(child, `${label}.${key}`);
    return;
  }
  if (typeof value !== "string") return;
  if (/\/Users\//.test(value) || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not publish a local private path`);
  }
}

const manifestPath = "docs/ui/completion-gate.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "decisionVerificationPath",
  "completionAuditPath",
  "completionSourceManifestPath",
  "privateVisualValidationManifestPath",
  "publicCheckScript",
  "privateVerifierScript",
  "finalVerificationCommand",
  "requiredPublicChecks",
  "goalUpdateRule",
  "externalPendingExitCode",
]);
scanPublicSafety(manifest, manifestPath);

if (manifest?.publicCheckScript !== "scripts/ui_completion_gate_check.mjs") {
  fail(`${manifestPath}.publicCheckScript must be scripts/ui_completion_gate_check.mjs`);
}
if (manifest?.privateVerifierScript !== "scripts/ui_private_completion_verify.mjs") {
  fail(`${manifestPath}.privateVerifierScript must be scripts/ui_private_completion_verify.mjs`);
}
if (!String(manifest?.finalVerificationCommand || "").includes("scripts/ui_private_completion_verify.mjs --require-approved")) {
  fail(`${manifestPath}.finalVerificationCommand must require the private completion verifier`);
}
if (!String(manifest?.goalUpdateRule || "").includes("update_goal")) {
  fail(`${manifestPath}.goalUpdateRule must mention update_goal`);
}
if (manifest?.externalPendingExitCode !== 2) fail(`${manifestPath}.externalPendingExitCode must be 2`);

for (const relativePath of [
  manifest?.decisionVerificationPath,
  manifest?.completionAuditPath,
  manifest?.completionSourceManifestPath,
  manifest?.privateVisualValidationManifestPath,
  manifest?.publicCheckScript,
  manifest?.privateVerifierScript,
]) {
  if (!relativePath || relativePath.includes("..") || path.isAbsolute(relativePath)) {
    fail(`${manifestPath} contains an unsafe relative path ${relativePath}`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, relativePath))) fail(`missing ${relativePath}`);
}

const sourceManifest = readJson(manifest?.completionSourceManifestPath || "docs/ui/completion-source.manifest.json");
const visualManifest = readJson(manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json");
for (const envName of [
  sourceManifest?.privateGoalFileEnv,
  sourceManifest?.privateSourceSessionFileEnv,
  ...(Array.isArray(visualManifest?.requiredRoots) ? visualManifest.requiredRoots : []),
]) {
  if (!String(manifest?.finalVerificationCommand || "").includes(envName)) {
    fail(`${manifestPath}.finalVerificationCommand must include ${envName}`);
  }
}

const config = readJson("docs/ui/interface-governance.config.json");
const publicChecks = new Set(requireArray(config, "docs/ui/interface-governance.config.json", "publicChecks"));
if (!publicChecks.has("completion-final-gate-check")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include completion-final-gate-check");
}
for (const check of requireArray(manifest, manifestPath, "requiredPublicChecks")) {
  if (!publicChecks.has(check)) fail(`${manifestPath}.requiredPublicChecks includes undeclared check ${check}`);
}

const privateVerifier = read(manifest?.privateVerifierScript || "scripts/ui_private_completion_verify.mjs");
for (const snippet of [
  "docs/ui/completion-gate.manifest.json",
  "scripts/ui_private_completion_source_verify.mjs",
  "scripts/ui_private_visual_verify.mjs",
  "EXTERNAL PENDING",
  "process.exit(2)",
  "open decisions",
]) {
  if (!privateVerifier.includes(snippet)) {
    fail(`${manifest.privateVerifierScript} must include ${snippet}`);
  }
}

const gateSurface = readJson("docs/ui/gate-surface.manifest.json");
if (!requireArray(gateSurface, "docs/ui/gate-surface.manifest.json", "requiredPublicCheckScripts").includes(manifest?.publicCheckScript)) {
  fail("docs/ui/gate-surface.manifest.json.requiredPublicCheckScripts must include the completion gate check");
}
const gateCoverage = gateSurface?.publicCheckCoverage || {};
if (!Array.isArray(gateCoverage["completion-final-gate-check"]) || !gateCoverage["completion-final-gate-check"].includes(manifest?.publicCheckScript)) {
  fail("docs/ui/gate-surface.manifest.json.publicCheckCoverage must cover completion-final-gate-check");
}

if (errors.length > 0) {
  console.error("UI completion gate check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI completion gate check passed");
