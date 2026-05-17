#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
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

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const requiredChangeKinds = new Set([
  "color",
  "spacing",
  "size",
  "icon",
  "layout",
  "animation",
  "microcopy",
  "visible-name",
  "ordering",
  "hierarchy",
  "typography",
]);

const manifestPath = "docs/ui/visual-change-scopes.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateModelAssignment",
  "defaultAuthorized",
  "scopeSignal",
  "scopeStatuses",
  "requiredApprovalFields",
  "activeScopes",
]);
if (manifest?.defaultAuthorized !== false) {
  fail(`${manifestPath}.defaultAuthorized must be false`);
}
if (manifest?.privateModelAssignment !== "outside-public-repo") {
  fail(`${manifestPath}.privateModelAssignment must stay outside-public-repo`);
}
requireFields(manifest?.scopeSignal, `${manifestPath}.scopeSignal`, ["env", "requiredForVisualMutation"]);
if (manifest?.scopeSignal?.env !== "CLAWIX_UI_VISUAL_SCOPE_ID") {
  fail(`${manifestPath}.scopeSignal.env must be CLAWIX_UI_VISUAL_SCOPE_ID`);
}
if (manifest?.scopeSignal?.requiredForVisualMutation !== true) {
  fail(`${manifestPath}.scopeSignal.requiredForVisualMutation must be true`);
}

const allowedStatuses = new Set(requireArray(manifest, manifestPath, "scopeStatuses"));
for (const status of ["proposed", "approved", "expired", "revoked"]) {
  if (!allowedStatuses.has(status)) fail(`${manifestPath}.scopeStatuses must include ${status}`);
}

const requiredApprovalFields = requireArray(manifest, manifestPath, "requiredApprovalFields");
const requiredApprovalFieldSet = new Set(requiredApprovalFields);
for (const field of ["files", "changeBudget", "approvedBy", "approvedAt", "expiresAt", "privateApprovalReference"]) {
  if (!requiredApprovalFieldSet.has(field)) fail(`${manifestPath}.requiredApprovalFields must include ${field}`);
}

const scopes = requireArray(manifest, manifestPath, "activeScopes", { nonEmpty: false });
for (const [index, scope] of scopes.entries()) {
  const label = `${manifestPath}.activeScopes[${index}]`;
  requireFields(scope, label, requiredApprovalFields);
  if (!allowedStatuses.has(scope.status)) fail(`${label}.status is invalid`);
  if (scope.status === "approved" && scope.expiresAt < today) {
    fail(`${label} approved scope expired on ${scope.expiresAt}`);
  }
  for (const platform of requireArray(scope, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  for (const kind of requireArray(scope, label, "changeKinds")) {
    if (!requiredChangeKinds.has(kind)) fail(`${label}.changeKinds contains unsupported ${kind}`);
  }
  for (const file of requireArray(scope, label, "files")) {
    if (typeof file !== "string" || file.startsWith("/") || file.includes("..")) {
      fail(`${label}.files entries must be public repo relative paths`);
    }
  }
  const changeBudget = scope.changeBudget || {};
  requireFields(changeBudget, `${label}.changeBudget`, ["maxFiles", "maxLines", "allowedChangeKinds"]);
  if (!Number.isInteger(changeBudget.maxFiles) || changeBudget.maxFiles < 1) {
    fail(`${label}.changeBudget.maxFiles must be a positive integer`);
  }
  if (!Number.isInteger(changeBudget.maxLines) || changeBudget.maxLines < 1) {
    fail(`${label}.changeBudget.maxLines must be a positive integer`);
  }
  for (const kind of requireArray(changeBudget, `${label}.changeBudget`, "allowedChangeKinds")) {
    if (!requiredChangeKinds.has(kind)) fail(`${label}.changeBudget.allowedChangeKinds contains unsupported ${kind}`);
    if (!scope.changeKinds.includes(kind)) fail(`${label}.changeBudget.allowedChangeKinds must be within scope.changeKinds`);
  }
  requireSafePrivateReference(scope.privateApprovalReference, "private-codex-ui-approval", `${label}.privateApprovalReference`);
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI visual scope check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual scope check passed (${scopes.length} active scopes)`);
