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

function verifyMeasurementSamples(evidence, label, requiredMetrics) {
  if (!Array.isArray(evidence.measurementSamples) || evidence.measurementSamples.length === 0) {
    fail(`${label}.measurementSamples must be a non-empty array`);
    return;
  }
  const seenMetrics = new Set();
  for (const [index, sample] of evidence.measurementSamples.entries()) {
    const sampleLabel = `${label}.measurementSamples[${index}]`;
    if (!sample || typeof sample !== "object" || Array.isArray(sample)) {
      fail(`${sampleLabel} must be an object`);
      continue;
    }
    if (typeof sample.metric !== "string" || !requiredMetrics.includes(sample.metric)) {
      fail(`${sampleLabel}.metric must be one of the required metrics`);
    } else {
      seenMetrics.add(sample.metric);
    }
    if (typeof sample.value !== "number" || !Number.isFinite(sample.value) || sample.value < 0) {
      fail(`${sampleLabel}.value must be a finite non-negative number`);
    }
    assertHash(sample.sampleHash, `${sampleLabel}.sampleHash`);
  }
  for (const metric of requiredMetrics) {
    if (!seenMetrics.has(metric)) fail(`${label}.measurementSamples must include ${metric}`);
  }
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");
const budgets = readJson("docs/ui/performance-budgets.registry.json");
const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
const alias = privateBaselines?.privateRootAlias || "private-codex-ui-baselines";
const privateRootEnv = privateRootEnvForAlias(rootDir, alias);

if (!requireApproved) {
  console.error("UI private performance budget verification requires --require-approved.");
  process.exit(1);
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env[privateRootEnv] || "";
if (!privateRootRaw) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} or pass --root to verify private UI performance budgets.`);
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private performance root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private performance root does not exist: ${privateRoot}`);
}

const evidenceFilename = budgets?.evidenceFilename || "performance-evidence.json";
const requiredEvidenceFields = Array.isArray(budgets?.requiredEvidenceFields) ? budgets.requiredEvidenceFields : [];
const requiredMetrics = Array.isArray(budgets?.requiredMetrics) ? budgets.requiredMetrics : [];
let verified = 0;
let pending = 0;

for (const [index, flow] of (budgets?.flows || []).entries()) {
  const label = `${flow.platform || "unknown"}:${flow.id || index}`;
  if (flow.budgetStatus === "pending-approved-measurement" || flow.baselineStatus !== "approved") {
    pending += 1;
    if (!includePending) {
      if (requireApproved) fail(`${label} is pending approved performance measurement`);
      continue;
    }
  }
  const relativeEvidenceDir = relativePathFromReference(flow.privateBaselineReference, alias);
  if (!relativeEvidenceDir) {
    fail(`${label} has invalid privateBaselineReference`);
    continue;
  }
  const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;
  for (const field of requiredEvidenceFields) requireField(evidence, `${label} evidence`, field);
  assertIsoTimestamp(evidence.measuredAt, `${label}.measuredAt`);
  assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
  assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
  if (evidence.flowId !== flow.id) fail(`${label}.flowId must match the budget registry`);
  if (evidence.platform !== flow.platform) fail(`${label}.platform must match the budget registry`);
  if (evidence.privateBaselineReference !== flow.privateBaselineReference) {
    fail(`${label}.privateBaselineReference must match the budget registry`);
  }
  assertHash(evidence.measurementHash, `${label}.measurementHash`);
  const metrics = evidence.metrics || {};
  for (const metric of requiredMetrics) {
    if (typeof metrics[metric] !== "number" || !Number.isFinite(metrics[metric]) || metrics[metric] < 0) {
      fail(`${label}.metrics.${metric} must be a finite non-negative number`);
    }
  }
  verifyMeasurementSamples(evidence, label, requiredMetrics);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private performance budget verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private performance budget verification passed (${verified} verified, ${pending} pending)`);
