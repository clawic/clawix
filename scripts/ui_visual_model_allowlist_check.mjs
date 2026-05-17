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

function hasLocalPath(value) {
  return (
    typeof value === "string" &&
    (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))
  );
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function requireSafePrivateReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

const manifestPath = "docs/ui/visual-model-allowlist.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateAssignment",
  "authorizationSignal",
  "modelSignal",
  "proposalPath",
  "privateApprovalAlias",
  "initialActiveModels",
  "additionalActiveModelPolicy",
  "allowedVisualModels",
]);

if (manifest?.privateAssignment !== "outside-public-repo") {
  fail(`${manifestPath}.privateAssignment must stay outside-public-repo`);
}
requireFields(manifest?.authorizationSignal, `${manifestPath}.authorizationSignal`, ["env", "value"]);
requireFields(manifest?.modelSignal, `${manifestPath}.modelSignal`, ["env", "requiredForVisualMutation"]);
if (manifest?.modelSignal?.requiredForVisualMutation !== true) {
  fail(`${manifestPath}.modelSignal.requiredForVisualMutation must be true`);
}
if (manifest?.proposalPath !== "docs/ui/visual-change-proposal.template.md") {
  fail(`${manifestPath}.proposalPath must point to docs/ui/visual-change-proposal.template.md`);
}
const approvalAuthority = readJson("docs/ui/approval-authority.manifest.json");
if (manifest?.privateApprovalAlias !== approvalAuthority?.privateApprovalAlias) {
  fail(`${manifestPath}.privateApprovalAlias must match docs/ui/approval-authority.manifest.json.privateApprovalAlias`);
}
requireFields(manifest?.additionalActiveModelPolicy, `${manifestPath}.additionalActiveModelPolicy`, [
  "requiresExplicitUserApproval",
  "privateApprovalReferenceRequired",
  "publicRepoStoresApprovalAliasOnly",
]);
if (manifest?.additionalActiveModelPolicy?.requiresExplicitUserApproval !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.requiresExplicitUserApproval must be true`);
}
if (manifest?.additionalActiveModelPolicy?.privateApprovalReferenceRequired !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.privateApprovalReferenceRequired must be true`);
}
if (manifest?.additionalActiveModelPolicy?.publicRepoStoresApprovalAliasOnly !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.publicRepoStoresApprovalAliasOnly must be true`);
}
const initialActiveModels = new Set(requireArray(manifest, manifestPath, "initialActiveModels"));
if (!initialActiveModels.has("claude-opus-4.7")) {
  fail(`${manifestPath}.initialActiveModels must include claude-opus-4.7`);
}

const allowedMutationClasses = new Set(["visual-ui", "copy-ui", "mechanical-equivalent-refactor"]);
let activeVisualModelCount = 0;
for (const [index, model] of requireArray(manifest, manifestPath, "allowedVisualModels").entries()) {
  const label = `${manifestPath}.allowedVisualModels[${index}]`;
  requireFields(model, label, [
    "id",
    "label",
    "status",
    "allowedMutationClasses",
    "scopeSource",
    "privateApprovalRequired",
  ]);
  if (!["active", "revoked"].includes(model.status)) fail(`${label}.status is invalid`);
  if (model.status === "active") activeVisualModelCount += 1;
  if (model.privateApprovalRequired !== true) fail(`${label}.privateApprovalRequired must be true`);
  if (model.status === "active" && !initialActiveModels.has(model.id)) {
    requireSafePrivateReference(model.privateApprovalReference, manifest.privateApprovalAlias, `${label}.privateApprovalReference`);
  }
  if (model.scopeSource !== "docs/ui/visual-change-scopes.manifest.json") {
    fail(`${label}.scopeSource must be docs/ui/visual-change-scopes.manifest.json`);
  }
  for (const mutationClass of requireArray(model, label, "allowedMutationClasses")) {
    if (!allowedMutationClasses.has(mutationClass)) fail(`${label}.allowedMutationClasses contains ${mutationClass}`);
  }
}
if (activeVisualModelCount < 1) fail(`${manifestPath}.allowedVisualModels must include at least one active model`);

const activeIds = new Set(
  (manifest?.allowedVisualModels || []).filter((model) => model.status === "active").map((model) => model.id),
);
if (!activeIds.has("claude-opus-4.7")) {
  fail(`${manifestPath}.allowedVisualModels must include active claude-opus-4.7`);
}

const guardPath = "scripts/ui_governance_guard.mjs";
const guardSource = fs.existsSync(path.join(rootDir, guardPath))
  ? fs.readFileSync(path.join(rootDir, guardPath), "utf8")
  : "";
for (const snippet of [
  "required permission:",
  "current model signal:",
  "proposal route:",
  "reason=",
  "active visual model",
]) {
  if (!guardSource.includes(snippet)) fail(`${guardPath} must include clear visual guard diagnostic snippet: ${snippet}`);
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI visual model allowlist check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual model allowlist check passed (${activeVisualModelCount} active model)`);
