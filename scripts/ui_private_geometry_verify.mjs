#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJsonFile(file, label) {
  if (!fs.existsSync(file)) {
    fail(`missing ${label}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
    return null;
  }
}

function readJson(relativePath) {
  return readJsonFile(path.join(rootDir, relativePath), relativePath);
}

function optionValue(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  return args[index + 1] || null;
}

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return false;
  }
  return true;
}

function assertHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function verifyMeasurements(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object`);
    return;
  }
  const entries = Object.entries(value);
  if (entries.length === 0) {
    fail(`${label} must not be empty`);
    return;
  }
  for (const [key, child] of entries) {
    if (typeof child !== "number" || !Number.isFinite(child) || child < 0) {
      fail(`${label}.${key} must be a finite non-negative number`);
    }
  }
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env.CLAWIX_UI_PRIVATE_GEOMETRY_ROOT || "";
if (!privateRootRaw) {
  console.error("EXTERNAL PENDING: set CLAWIX_UI_PRIVATE_GEOMETRY_ROOT or pass --root to verify private rendered geometry.");
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private geometry root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private geometry root does not exist: ${privateRoot}`);
}

const manifest = readJson("docs/ui/rendered-geometry.manifest.json");
const registry = readJson(manifest?.patternSource || "docs/ui/pattern-registry/patterns.registry.json");
const evidenceFilename = manifest?.evidenceFilename || "geometry-evidence.json";
const requiredEvidence = Array.isArray(manifest?.requiredEvidenceFields) ? manifest.requiredEvidenceFields : [];
const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
let verified = 0;

for (const patternId of registry?.patterns || []) {
  const pattern = readJson(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json`);
  for (const platform of pattern?.platforms || []) {
    if (!requiredPlatforms.has(platform)) continue;
    const evidencePath = path.join(privateRoot, platform, patternId, evidenceFilename);
    const label = `${platform}:${patternId}`;
    const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
    if (!evidence) continue;
    for (const field of requiredEvidence) requireField(evidence, `${label} evidence`, field);
    if (evidence.patternId !== patternId) fail(`${label}.patternId must match the pattern registry`);
    if (evidence.platform !== platform) fail(`${label}.platform must match the pattern registry`);
    verifyMeasurements(evidence.measurements, `${label}.measurements`);
    assertHash(evidence.geometryHash, `${label}.geometryHash`);
    verified += 1;
  }
}

if (errors.length > 0) {
  console.error("UI private geometry verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private geometry verification passed (${verified} rendered geometry snapshots)`);
