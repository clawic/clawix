#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

const aliasRoots = {
  "private-codex-ui-baselines": "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "private-codex-ui-rendered-geometry": "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "private-codex-ui-copy-snapshots": "CLAWIX_UI_PRIVATE_COPY_ROOT",
  "private-codex-ui-rendered-drift": "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
  "private-codex-ui-debt-audit": "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
};

const referenceFields = {
  "surface-baseline": "privateBaselineReference",
  "surface-geometry": "geometryEvidenceReference",
  "surface-copy": "copySnapshotReference",
  "critical-flow-baseline": "privateBaselineReference",
  "pattern-geometry": "geometryEvidenceReference",
  "rendered-drift": "privateDriftReportReference",
  "debt-audit": "privateDebtAuditReference",
  "performance-budget": "privateBaselineReference",
};

const idFields = {
  "surface-baseline": "coverageId",
  "surface-geometry": "coverageId",
  "surface-copy": "coverageId",
  "critical-flow-baseline": "flowId",
  "pattern-geometry": "patternId",
  "rendered-drift": "coverageId",
  "debt-audit": "debtId",
  "performance-budget": "flowId",
};

function fail(message) {
  errors.push(message);
}

function hasFlag(name) {
  return args.includes(name);
}

function runEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    process.exit(result.status || 1);
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { evidence: [] };
  }
}

function splitReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.includes("..")) return null;
  return { alias, suffix };
}

function assertRoot(root, envName) {
  const resolved = path.resolve(root);
  const relativeToRepo = path.relative(rootDir, resolved);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    fail(`${envName} must point outside the public repository`);
  }
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
    fail(`${envName} does not point to an existing directory`);
  }
  return resolved;
}

function readJson(file, label) {
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

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return;
  }
  if (/Hash$/.test(field) && (typeof object[field] !== "string" || !/^[a-f0-9]{64}$/i.test(object[field]))) {
    fail(`${label}.${field} must be a 64-character hex hash`);
  }
}

function verifyMetrics(evidence, label) {
  if (!("metrics" in evidence)) return;
  if (!evidence.metrics || typeof evidence.metrics !== "object" || Array.isArray(evidence.metrics)) {
    fail(`${label}.metrics must be an object`);
    return;
  }
  for (const [metric, value] of Object.entries(evidence.metrics)) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      fail(`${label}.metrics.${metric} must be a finite non-negative number`);
    }
  }
}

function verifyMeasurementSamples(evidence, label) {
  if (!("measurementSamples" in evidence)) return;
  if (!Array.isArray(evidence.measurementSamples) || evidence.measurementSamples.length === 0) {
    fail(`${label}.measurementSamples must be a non-empty array`);
    return;
  }
  for (const [index, sample] of evidence.measurementSamples.entries()) {
    const sampleLabel = `${label}.measurementSamples[${index}]`;
    if (!sample || typeof sample !== "object" || Array.isArray(sample)) {
      fail(`${sampleLabel} must be an object`);
      continue;
    }
    if (typeof sample.metric !== "string" || sample.metric === "") {
      fail(`${sampleLabel}.metric must be a non-empty string`);
    }
    if (typeof sample.value !== "number" || !Number.isFinite(sample.value) || sample.value < 0) {
      fail(`${sampleLabel}.value must be a finite non-negative number`);
    }
    if (typeof sample.sampleHash !== "string" || !/^[a-f0-9]{64}$/i.test(sample.sampleHash)) {
      fail(`${sampleLabel}.sampleHash must be a 64-character hex hash`);
    }
  }
}

function verifyMeasurements(evidence, label) {
  if (!("measurements" in evidence)) return;
  if (!evidence.measurements || typeof evidence.measurements !== "object" || Array.isArray(evidence.measurements)) {
    fail(`${label}.measurements must be an object`);
    return;
  }
  const entries = Object.entries(evidence.measurements);
  if (entries.length === 0) {
    fail(`${label}.measurements must not be empty`);
    return;
  }
  for (const [measurement, value] of entries) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      fail(`${label}.measurements.${measurement} must be a finite non-negative number`);
    }
  }
}

function verifyCopyItems(evidence, label) {
  if (!("copyItems" in evidence)) return;
  if (!Array.isArray(evidence.copyItems) || evidence.copyItems.length === 0) {
    fail(`${label}.copyItems must be a non-empty array`);
    return;
  }
  for (const [index, item] of evidence.copyItems.entries()) {
    const itemLabel = `${label}.copyItems[${index}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      fail(`${itemLabel} must be an object`);
      continue;
    }
    for (const field of ["kind", "textHash", "source"]) {
      if (typeof item[field] !== "string" || item[field] === "") {
        fail(`${itemLabel}.${field} must be a non-empty string`);
      }
    }
    if (typeof item.textHash !== "string" || !/^[a-f0-9]{64}$/i.test(item.textHash)) {
      fail(`${itemLabel}.textHash must be a 64-character hex hash`);
    }
  }
}

function verifyDriftResults(evidence, label) {
  if (!("driftResults" in evidence)) return;
  if (!evidence.driftResults || typeof evidence.driftResults !== "object" || Array.isArray(evidence.driftResults)) {
    fail(`${label}.driftResults must be an object keyed by drift category`);
    return;
  }
  const entries = Object.entries(evidence.driftResults);
  if (entries.length === 0) {
    fail(`${label}.driftResults must not be empty`);
    return;
  }
  for (const [category, result] of entries) {
    const resultLabel = `${label}.driftResults.${category}`;
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      fail(`${resultLabel} must be an object`);
      continue;
    }
    if (typeof result.status !== "string" || result.status === "") {
      fail(`${resultLabel}.status must be a non-empty string`);
    }
    if (typeof result.resultHash !== "string" || !/^[a-f0-9]{64}$/i.test(result.resultHash)) {
      fail(`${resultLabel}.resultHash must be a 64-character hex hash`);
    }
  }
}

function verifyFindingItems(evidence, label) {
  if (!("findingItems" in evidence)) return;
  if (!Array.isArray(evidence.findingItems) || evidence.findingItems.length === 0) {
    fail(`${label}.findingItems must be a non-empty array`);
    return;
  }
  for (const [index, item] of evidence.findingItems.entries()) {
    const itemLabel = `${label}.findingItems[${index}]`;
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      fail(`${itemLabel} must be an object`);
      continue;
    }
    for (const field of ["category", "source"]) {
      if (typeof item[field] !== "string" || item[field] === "") {
        fail(`${itemLabel}.${field} must be a non-empty string`);
      }
    }
    if (typeof item.itemHash !== "string" || !/^[a-f0-9]{64}$/i.test(item.itemHash)) {
      fail(`${itemLabel}.itemHash must be a 64-character hex hash`);
    }
  }
}

if (!hasFlag("--require-approved")) {
  console.error("UI private evidence verification requires --require-approved.");
  process.exit(1);
}

const plan = runEvidencePlan();
const aliases = new Set();
for (const item of plan.evidence || []) {
  const parsed = splitReference(item.privateReference);
  if (!parsed) {
    fail(`${item.type}:${item.platform}:${item.id} has invalid privateReference`);
    continue;
  }
  aliases.add(parsed.alias);
}

const missingEnv = [...aliases]
  .map((alias) => aliasRoots[alias])
  .filter((envName, index, values) => envName && !process.env[envName] && values.indexOf(envName) === index);
const unknownAliases = [...aliases].filter((alias) => !aliasRoots[alias]);
if (unknownAliases.length > 0) fail(`unknown private evidence aliases: ${unknownAliases.join(", ")}`);
if (missingEnv.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingEnv.join(", ")} to verify the private UI evidence plan.`);
  process.exit(2);
}

const roots = new Map();
for (const alias of aliases) {
  const envName = aliasRoots[alias];
  if (!envName) continue;
  roots.set(alias, assertRoot(process.env[envName], envName));
}

let verified = 0;
for (const item of plan.evidence || []) {
  const parsed = splitReference(item.privateReference);
  if (!parsed) continue;
  const root = roots.get(parsed.alias);
  if (!root) continue;
  const evidencePath = path.join(root, parsed.suffix.split("/").join(path.sep), item.evidenceFilename);
  const label = `${item.type}:${item.platform}:${item.id}`;
  const evidence = readJson(evidencePath, `${label} ${item.evidenceFilename}`);
  if (!evidence) continue;

  for (const field of item.requiredFields || []) requireField(evidence, label, field);

  const idField = idFields[item.type];
  if (idField && evidence[idField] !== item.id) fail(`${label}.${idField} must match the public evidence plan`);
  if (evidence.platform !== item.platform) fail(`${label}.platform must match the public evidence plan`);

  const referenceField = referenceFields[item.type];
  if (referenceField && evidence[referenceField] !== item.privateReference) {
    fail(`${label}.${referenceField} must match the public evidence plan`);
  }

  verifyMetrics(evidence, label);
  verifyMeasurementSamples(evidence, label);
  verifyMeasurements(evidence, label);
  verifyCopyItems(evidence, label);
  verifyDriftResults(evidence, label);
  verifyFindingItems(evidence, label);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private evidence verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private evidence verification passed (${verified} evidence records)`);
