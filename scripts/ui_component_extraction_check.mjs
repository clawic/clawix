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

function collectSourceFiles(root, extensions, skippedDirectories) {
  const files = [];
  const absoluteRoot = path.join(rootDir, root);
  if (!fs.existsSync(absoluteRoot)) {
    fail(`source audit root is missing: ${root}`);
    return files;
  }

  const visit = (absolutePath) => {
    const entryName = path.basename(absolutePath);
    if (skippedDirectories.has(entryName)) return;
    const stat = fs.statSync(absolutePath);
    if (stat.isDirectory()) {
      for (const child of fs.readdirSync(absolutePath)) visit(path.join(absolutePath, child));
      return;
    }
    if (stat.isFile() && extensions.has(path.extname(absolutePath))) files.push(absolutePath);
  };

  visit(absoluteRoot);
  return files;
}

const manifestPath = "docs/ui/component-extraction.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "minimumCallSites",
  "requiredRiskSignals",
  "mechanicalEquivalence",
  "allowedPolicies",
  "allowedApis",
  "forbiddenApiSignals",
  "sourceAudit",
]);

if (manifest?.minimumCallSites !== 2) {
  fail(`${manifestPath}.minimumCallSites must be 2`);
}

const requiredRiskSignals = new Set(requireArray(manifest, manifestPath, "requiredRiskSignals"));
for (const signal of ["state", "interaction", "geometry", "accessibility", "performance"]) {
  if (!requiredRiskSignals.has(signal)) fail(`${manifestPath}.requiredRiskSignals must include ${signal}`);
}

const mechanicalEquivalence = manifest?.mechanicalEquivalence || {};
requireFields(mechanicalEquivalence, `${manifestPath}.mechanicalEquivalence`, [
  "manifestPath",
  "privateEvidenceAlias",
  "requiredForPolicies",
  "requiredStatuses",
  "requiredEvidenceFields",
]);
if (mechanicalEquivalence.manifestPath !== "docs/ui/mechanical-equivalence.manifest.json") {
  fail(`${manifestPath}.mechanicalEquivalence.manifestPath must reference docs/ui/mechanical-equivalence.manifest.json`);
}

const mechanicalManifest = readJson(mechanicalEquivalence.manifestPath || "docs/ui/mechanical-equivalence.manifest.json");
if (mechanicalEquivalence.privateEvidenceAlias !== mechanicalManifest?.privateEvidenceAlias) {
  fail(`${manifestPath}.mechanicalEquivalence.privateEvidenceAlias must match ${mechanicalEquivalence.manifestPath}.privateEvidenceAlias`);
}

const requiredMechanicalPolicies = new Set(requireArray(mechanicalEquivalence, `${manifestPath}.mechanicalEquivalence`, "requiredForPolicies"));
for (const policy of ["required", "required-when-repeated-with-state", "allowed"]) {
  if (!requiredMechanicalPolicies.has(policy)) {
    fail(`${manifestPath}.mechanicalEquivalence.requiredForPolicies must include ${policy}`);
  }
}

const requiredMechanicalStatuses = new Set(requireArray(mechanicalEquivalence, `${manifestPath}.mechanicalEquivalence`, "requiredStatuses"));
if (!requiredMechanicalStatuses.has("verified-equivalent")) {
  fail(`${manifestPath}.mechanicalEquivalence.requiredStatuses must include verified-equivalent`);
}

const mechanicalEvidenceFields = new Set(requireArray(mechanicalEquivalence, `${manifestPath}.mechanicalEquivalence`, "requiredEvidenceFields"));
const canonicalMechanicalEvidenceFields = new Set(requireArray(mechanicalManifest, mechanicalEquivalence.manifestPath || "docs/ui/mechanical-equivalence.manifest.json", "requiredEvidenceFields"));
for (const field of canonicalMechanicalEvidenceFields) {
  if (!mechanicalEvidenceFields.has(field)) {
    fail(`${manifestPath}.mechanicalEquivalence.requiredEvidenceFields must include ${field}`);
  }
}

const allowedApis = new Set();
for (const [index, api] of requireArray(manifest, manifestPath, "allowedApis").entries()) {
  const label = `${manifestPath}.allowedApis[${index}]`;
  requireFields(api, label, ["id", "shape", "forbids"]);
  if (api?.id) allowedApis.add(api.id);
  const forbiddenShapes = new Set(requireArray(api, label, "forbids"));
  if (!forbiddenShapes.has("unbounded-prop-bag")) {
    fail(`${label}.forbids must include unbounded-prop-bag`);
  }
}

const policyToApis = new Map();
for (const [index, policy] of requireArray(manifest, manifestPath, "allowedPolicies").entries()) {
  const label = `${manifestPath}.allowedPolicies[${index}]`;
  requireFields(policy, label, ["id", "description", "allowedApis"]);
  const policyApis = requireArray(policy, label, "allowedApis");
  policyToApis.set(policy.id, new Set(policyApis));
  for (const api of policyApis) {
    if (!allowedApis.has(api)) fail(`${label}.allowedApis includes unknown API ${api}`);
  }
}

const requiredPolicies = ["required", "required-when-repeated-with-state", "allowed", "forbidden"];
for (const policy of requiredPolicies) {
  if (!policyToApis.has(policy)) fail(`${manifestPath}.allowedPolicies must include ${policy}`);
}

const compiledForbiddenSignals = [];
for (const [index, signal] of requireArray(manifest, manifestPath, "forbiddenApiSignals").entries()) {
  const label = `${manifestPath}.forbiddenApiSignals[${index}]`;
  requireFields(signal, label, ["id", "pattern", "reason"]);
  try {
    compiledForbiddenSignals.push({
      id: signal.id,
      reason: signal.reason,
      regex: new RegExp(signal.pattern),
    });
  } catch (error) {
    fail(`${label}.pattern is not a valid regex: ${error.message}`);
  }
}

const registryPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = requireArray(registry, registryPath, "patterns");
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (!pattern) continue;
  const extraction = pattern.componentExtraction;
  requireFields(extraction, `${patternPath}.componentExtraction`, ["policy", "api", "riskSignals"]);
  if (!policyToApis.has(extraction?.policy)) {
    fail(`${patternPath}.componentExtraction.policy must be defined in ${manifestPath}`);
    continue;
  }
  if (!allowedApis.has(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api must be defined in ${manifestPath}`);
    continue;
  }
  const allowedForPolicy = policyToApis.get(extraction.policy);
  if (!allowedForPolicy.has(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api ${extraction.api} is not allowed for policy ${extraction.policy}`);
  }
  const riskSignals = new Set(requireArray(extraction, `${patternPath}.componentExtraction`, "riskSignals"));
  for (const signal of riskSignals) {
    if (!requiredRiskSignals.has(signal)) {
      fail(`${patternPath}.componentExtraction.riskSignals contains unknown risk signal ${signal}`);
    }
  }
  if (extraction.policy !== "forbidden" && riskSignals.size === 0) {
    fail(`${patternPath}.componentExtraction.riskSignals must justify extraction when policy is ${extraction.policy}`);
  }
  if (extraction.policy === "required-when-repeated-with-state" && !riskSignals.has("state") && !riskSignals.has("interaction")) {
    fail(`${patternPath}.componentExtraction.riskSignals must include state or interaction for required-when-repeated-with-state`);
  }
}

const sourceAudit = manifest?.sourceAudit || {};
requireFields(sourceAudit, `${manifestPath}.sourceAudit`, ["roots", "fileExtensions", "skippedDirectories"]);
const sourceRoots = requireArray(sourceAudit, `${manifestPath}.sourceAudit`, "roots");
const extensions = new Set(requireArray(sourceAudit, `${manifestPath}.sourceAudit`, "fileExtensions"));
const skippedDirectories = new Set(requireArray(sourceAudit, `${manifestPath}.sourceAudit`, "skippedDirectories"));

let auditedFiles = 0;
for (const sourceRoot of sourceRoots) {
  for (const absoluteFile of collectSourceFiles(sourceRoot, extensions, skippedDirectories)) {
    auditedFiles += 1;
    const relativeFile = path.relative(rootDir, absoluteFile);
    const lines = fs.readFileSync(absoluteFile, "utf8").split("\n");
    for (const [lineIndex, line] of lines.entries()) {
      for (const signal of compiledForbiddenSignals) {
        if (signal.regex.test(line)) {
          fail(`${relativeFile}:${lineIndex + 1} matches ${signal.id}: ${signal.reason}`);
        }
      }
    }
  }
}

if (errors.length > 0) {
  console.error("UI component extraction check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI component extraction check passed (${patternIds.length} patterns, ${auditedFiles} source files)`);
