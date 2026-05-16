#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function readText(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const text = readText(relativePath);
  if (!text) return null;
  try {
    return JSON.parse(text);
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

function requireIncludes(values, label, expected) {
  const set = new Set(values);
  for (const value of expected) {
    if (!set.has(value)) fail(`${label} must include ${value}`);
  }
}

const manifestPath = "docs/ui/implementation-evidence.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "prTemplatePath",
  "proposalPath",
  "requiredEvidenceFields",
  "mappingKinds",
  "allowedMutationClasses",
  "requiredInteractiveStates",
  "requiredPublicChecks",
  "prTemplateRequiredSnippets",
  "privateDataPolicy",
]);

if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.prTemplatePath !== ".github/PULL_REQUEST_TEMPLATE.md") {
  fail(`${manifestPath}.prTemplatePath must point to .github/PULL_REQUEST_TEMPLATE.md`);
}
if (manifest?.proposalPath !== "docs/ui/visual-change-proposal.template.md") {
  fail(`${manifestPath}.proposalPath must point to docs/ui/visual-change-proposal.template.md`);
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const configMutationClasses = requireArray(config, configPath, "mutationClasses");
const manifestMutationClasses = requireArray(manifest, manifestPath, "allowedMutationClasses");
requireIncludes(manifestMutationClasses, `${manifestPath}.allowedMutationClasses`, configMutationClasses);

const requiredEvidenceFields = [
  "mutationClass",
  "patternOrDebtProtectedExceptionMapping",
  "touchedFiles",
  "visibleSurfaces",
  "requiredInteractiveStates",
  "publicChecks",
  "visualCopyLayoutAuthorization",
];
requireIncludes(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  requiredEvidenceFields,
);

requireIncludes(
  requireArray(manifest, manifestPath, "mappingKinds"),
  `${manifestPath}.mappingKinds`,
  ["pattern", "debt", "protected", "exception"],
);

requireIncludes(
  requireArray(manifest, manifestPath, "requiredInteractiveStates"),
  `${manifestPath}.requiredInteractiveStates`,
  requireArray(config, configPath, "requiredInteractiveStates"),
);

requireIncludes(
  requireArray(manifest, manifestPath, "requiredPublicChecks"),
  `${manifestPath}.requiredPublicChecks`,
  ["node scripts/ui_governance_guard.mjs", "node scripts/ui_surface_inventory_check.mjs"],
);

requireIncludes(
  requireArray(config, configPath, "publicChecks"),
  `${configPath}.publicChecks`,
  ["implementation-evidence-contract-check"],
);

const privateDataPolicy = manifest?.privateDataPolicy || {};
requireIncludes(
  requireArray(privateDataPolicy, `${manifestPath}.privateDataPolicy`, "publicRepoMustNotStore"),
  `${manifestPath}.privateDataPolicy.publicRepoMustNotStore`,
  ["raw screenshot", "private model assignment", "local absolute path", "secret"],
);

const prTemplate = readText(manifest?.prTemplatePath || ".github/PULL_REQUEST_TEMPLATE.md");
for (const snippet of requireArray(manifest, manifestPath, "prTemplateRequiredSnippets")) {
  if (!prTemplate.includes(snippet)) fail(`${manifest?.prTemplatePath} is missing required snippet: ${snippet}`);
}

const skill = readText("skills/ui-implementation/SKILL.md");
for (const snippet of [
  "Declare the UI governance evidence",
  "pattern IDs or debt/protected/exception mapping",
  "public checks to run",
]) {
  if (!skill.includes(snippet)) fail(`skills/ui-implementation/SKILL.md is missing required snippet: ${snippet}`);
}

const proposal = readText(manifest?.proposalPath || "docs/ui/visual-change-proposal.template.md");
if (!proposal.includes("Status: conceptual-only")) {
  fail(`${manifest?.proposalPath} must remain conceptual-only`);
}

if (errors.length > 0) {
  console.error("UI implementation evidence check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI implementation evidence check passed");
