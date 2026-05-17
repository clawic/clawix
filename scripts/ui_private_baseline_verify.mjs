#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/ui/private-baselines.manifest.json";
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

function relativePathFromReference(reference, alias) {
  const prefix = `${alias}:`;
  if (typeof reference !== "string" || !reference.startsWith(prefix)) return null;
  const suffix = reference.slice(prefix.length);
  if (!suffix || suffix.includes("..") || suffix.startsWith("/") || suffix.startsWith("\\")) return null;
  return suffix.split("/").join(path.sep);
}

function assertHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

const requireApproved = hasFlag("--require-approved");
const verifyPending = hasFlag("--include-pending");

if (!requireApproved) {
  console.error("UI private baseline verification requires --require-approved.");
  process.exit(1);
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env.CLAWIX_UI_PRIVATE_BASELINE_ROOT || "";
if (!privateRootRaw) {
  console.error("EXTERNAL PENDING: set CLAWIX_UI_PRIVATE_BASELINE_ROOT or pass --root to verify private UI baselines.");
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private baseline root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private baseline root does not exist: ${privateRoot}`);
}

const manifest = readJson(manifestPath);
const alias = manifest?.privateRootAlias || "private-codex-ui-baselines";
const evidenceFilename = manifest?.evidenceFilename || "evidence.json";
let verified = 0;
let pending = 0;

if (Array.isArray(manifest?.flows)) {
  for (const flow of manifest.flows) {
    const label = `${flow.platform}:${flow.id}`;
    if (flow.baselineStatus !== "approved") {
      pending += 1;
      if (!verifyPending) continue;
    }
    if (requireApproved && flow.baselineStatus !== "approved") {
      fail(`${label} is not approved`);
      continue;
    }

    const relativeEvidenceDir = relativePathFromReference(flow.privateBaselineReference, alias);
    if (!relativeEvidenceDir) {
      fail(`${label} has invalid privateBaselineReference`);
      continue;
    }
    const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
    const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
    if (!evidence) continue;

    for (const field of flow.requiredEvidence || []) {
      requireField(evidence, `${label} evidence`, field);
    }
    assertHash(evidence.geometryHash, `${label}.geometryHash`);
    assertHash(evidence.screenshotHash, `${label}.screenshotHash`);
    assertHash(evidence.baselineArtifactHash, `${label}.baselineArtifactHash`);
    if (String(evidence.privateBaselineReference || "") !== flow.privateBaselineReference) {
      fail(`${label}.privateBaselineReference must match the public manifest`);
    }
    if (evidence.platform !== flow.platform) fail(`${label}.platform must match the public manifest`);
    if (evidence.flowId !== flow.id) fail(`${label}.flowId must match the public manifest`);
    verified += 1;
  }
} else {
  fail(`${manifestPath}.flows must be an array`);
}

if (errors.length > 0) {
  console.error("UI private baseline verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private baseline verification passed (${verified} verified, ${pending} pending)`);
