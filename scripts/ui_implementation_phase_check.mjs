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

const manifestPath = "docs/ui/implementation-phases.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "nonAuthorizedAllowedActions",
  "nonAuthorizedForbiddenActions",
  "phases",
]);

const allowedActions = new Set(requireArray(manifest, manifestPath, "nonAuthorizedAllowedActions"));
for (const action of ["governance-manifest", "public-check", "private-verifier", "evidence-wiring", "conceptual-proposal"]) {
  if (!allowedActions.has(action)) fail(`${manifestPath}.nonAuthorizedAllowedActions must include ${action}`);
}
const forbiddenActions = new Set(requireArray(manifest, manifestPath, "nonAuthorizedForbiddenActions"));
for (const action of ["visual-ui", "copy-ui", "layout-change", "style-token-change", "critical-cleanup-execution"]) {
  if (!forbiddenActions.has(action)) fail(`${manifestPath}.nonAuthorizedForbiddenActions must include ${action}`);
}

const expectedPhases = new Map([
  ["public-governance-foundation", "complete"],
  ["private-evidence-capture", "external-pending"],
  ["visual-cleanup-execution", "blocked-without-allowlisted-visual-lane"],
]);
const seen = new Set();
for (const [index, phase] of requireArray(manifest, manifestPath, "phases").entries()) {
  const label = `${manifestPath}.phases[${index}]`;
  requireFields(phase, label, ["id", "status", "evidence"]);
  if (!expectedPhases.has(phase.id)) fail(`${label}.id is not a required implementation phase`);
  if (expectedPhases.get(phase.id) !== phase.status) fail(`${label}.status must be ${expectedPhases.get(phase.id)}`);
  if (seen.has(phase.id)) fail(`${label}.id duplicates ${phase.id}`);
  seen.add(phase.id);
  for (const [evidenceIndex, evidence] of requireArray(phase, label, "evidence").entries()) {
    requireRepoReference(evidence, `${label}.evidence[${evidenceIndex}]`);
  }
}
for (const phaseId of expectedPhases.keys()) {
  if (!seen.has(phaseId)) fail(`${manifestPath}.phases must include ${phaseId}`);
}

if (errors.length > 0) {
  console.error("UI implementation phase check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI implementation phase check passed (${seen.size} phases)`);
