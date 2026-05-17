#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { privateRootEnvForAlias } from "./ui_private_root_contract.mjs";

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

function hasFlag(name) {
  return args.includes(name);
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

function assertIsoTimestamp(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function assertApprovedScope(value, label) {
  if (typeof value === "string") {
    if (value.trim() === "") fail(`${label} must not be empty`);
    return;
  }
  if (Array.isArray(value)) {
    if (value.length === 0) fail(`${label} must not be empty`);
    return;
  }
  if (value && typeof value === "object") {
    if (Object.keys(value).length === 0) fail(`${label} must not be empty`);
    return;
  }
  fail(`${label} must be a non-empty string, array, or object`);
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

function measuredGeometryKeys(pattern, platform) {
  const geometry = pattern?.geometry;
  if (!geometry || typeof geometry !== "object" || Array.isArray(geometry)) return [];
  const platformGeometry = geometry[platform];
  if (platformGeometry && typeof platformGeometry === "object" && !Array.isArray(platformGeometry)) {
    return Object.entries(platformGeometry)
      .filter(([, value]) => typeof value === "number")
      .map(([key]) => key);
  }
  return Object.entries(geometry)
    .filter(([, value]) => typeof value === "number")
    .map(([key]) => key);
}

function verifyRequiredMeasurementKeys(measurements, requiredKeys, label) {
  for (const key of requiredKeys) {
    if (typeof measurements?.[key] !== "number") {
      fail(`${label}.${key} must be measured because it is declared in the public pattern geometry contract`);
    }
  }
}

function splitReference(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.includes("..")) {
    fail(`${label} must use a safe relative private reference`);
    return null;
  }
  return suffix;
}

if (!hasFlag("--require-approved")) {
  console.error("UI private geometry verification requires --require-approved.");
  process.exit(1);
}

const includePending = hasFlag("--include-pending");
const manifest = readJson("docs/ui/rendered-geometry.manifest.json");
const privateGeometryAlias = manifest?.privateGeometryAlias || "private-codex-ui-rendered-geometry";
const privateRootEnv = privateRootEnvForAlias(rootDir, privateGeometryAlias);
const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env[privateRootEnv] || "";
if (!privateRootRaw) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} or pass --root to verify private rendered geometry.`);
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

const registry = readJson(manifest?.patternSource || "docs/ui/pattern-registry/patterns.registry.json");
const surfaceCoverage = readJson("docs/ui/surface-baseline-coverage.manifest.json");
const evidenceFilename = manifest?.evidenceFilename || "geometry-evidence.json";
const surfaceEvidenceFilename = manifest?.surfaceEvidenceFilename || "surface-geometry.json";
const requiredEvidence = Array.isArray(manifest?.requiredEvidenceFields) ? manifest.requiredEvidenceFields : [];
const requiredSurfaceEvidence = Array.isArray(manifest?.requiredSurfaceEvidenceFields) ? manifest.requiredSurfaceEvidenceFields : [];
const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const skipEvidence = manifest?.status !== "approved" && !includePending;
let verifiedPatterns = 0;
let verifiedSurfaces = 0;

if (skipEvidence) {
  fail("docs/ui/rendered-geometry.manifest.json is pending approved rendered geometry evidence");
} else {
  for (const patternId of registry?.patterns || []) {
    const pattern = readJson(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json`);
    for (const platform of pattern?.platforms || []) {
      if (!requiredPlatforms.has(platform)) continue;
      const evidencePath = path.join(privateRoot, platform, patternId, evidenceFilename);
      const label = `${platform}:${patternId}`;
      const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
      if (!evidence) continue;
      for (const field of requiredEvidence) requireField(evidence, `${label} evidence`, field);
      assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
      assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
      if (evidence.patternId !== patternId) fail(`${label}.patternId must match the pattern registry`);
      if (evidence.platform !== platform) fail(`${label}.platform must match the pattern registry`);
      const expectedReference = `${privateGeometryAlias}:${platform}/${patternId}`;
      if (evidence.geometryEvidenceReference !== expectedReference) {
        fail(`${label}.geometryEvidenceReference must be ${expectedReference}`);
      }
      const requiredMeasurementKeys = measuredGeometryKeys(pattern, platform);
      verifyMeasurements(evidence.measurements, `${label}.measurements`);
      verifyRequiredMeasurementKeys(evidence.measurements, requiredMeasurementKeys, `${label}.measurements`);
      assertHash(evidence.geometryHash, `${label}.geometryHash`);
      assertHash(evidence.screenshotComparisonHash, `${label}.screenshotComparisonHash`);
      verifiedPatterns += 1;
    }
  }

  for (const [index, entry] of (surfaceCoverage?.coverage || []).entries()) {
    const label = `surface:${entry?.platform || "unknown"}:${entry?.coverageId || index}`;
    const suffix = splitReference(entry?.geometryEvidenceReference, privateGeometryAlias, `${label}.geometryEvidenceReference`);
    if (!suffix) continue;
    const evidencePath = path.join(privateRoot, suffix.split("/").join(path.sep), surfaceEvidenceFilename);
    const evidence = readJsonFile(evidencePath, `${label} ${surfaceEvidenceFilename}`);
    if (!evidence) continue;
    for (const field of requiredSurfaceEvidence) requireField(evidence, `${label} evidence`, field);
    assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
    assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
    if (evidence.coverageId !== entry.coverageId) fail(`${label}.coverageId must match the surface coverage manifest`);
    if (evidence.platform !== entry.platform) fail(`${label}.platform must match the surface coverage manifest`);
    if (evidence.geometryEvidenceReference !== entry.geometryEvidenceReference) {
      fail(`${label}.geometryEvidenceReference must match the surface coverage manifest`);
    }
    verifyMeasurements(evidence.measurements, `${label}.measurements`);
    assertHash(evidence.geometryHash, `${label}.geometryHash`);
    assertHash(evidence.screenshotComparisonHash, `${label}.screenshotComparisonHash`);
    verifiedSurfaces += 1;
  }
}

if (errors.length > 0) {
  console.error("UI private geometry verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private geometry verification passed (${verifiedPatterns} pattern snapshots; ${verifiedSurfaces} surface snapshots)`);
