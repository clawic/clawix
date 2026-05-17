#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const args = new Set(process.argv.slice(2));
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
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
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

function requireIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    fail(`${label} must be an ISO yyyy-mm-dd date`);
    return null;
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    fail(`${label} must be a valid calendar date`);
    return null;
  }
  return value;
}

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const registryPath = "docs/ui/exceptions.registry.json";
const registry = readJson(registryPath);
requireFields(registry, registryPath, [
  "schemaVersion",
  "status",
  "policy",
  "exceptionStatuses",
  "requiredExceptionFields",
  "exceptions",
]);

const statuses = new Set(requireArray(registry, registryPath, "exceptionStatuses"));
for (const status of ["active", "expired", "resolved", "revoked"]) {
  if (!statuses.has(status)) fail(`${registryPath}.exceptionStatuses must include ${status}`);
}

const requiredExceptionFields = requireArray(registry, registryPath, "requiredExceptionFields");
const requiredExceptionFieldSet = new Set(requiredExceptionFields);
for (const field of [
  "id",
  "status",
  "scope",
  "platforms",
  "owner",
  "reason",
  "createdAt",
  "reviewAfter",
  "expiresAt",
  "allowedAction",
  "privateApprovalReference",
]) {
  if (!requiredExceptionFieldSet.has(field)) fail(`${registryPath}.requiredExceptionFields must include ${field}`);
}

if (args.has("--simulate-unreferenced-active-exception")) {
  registry.exceptions = [
    ...(Array.isArray(registry?.exceptions) ? registry.exceptions : []),
    {
      id: "simulated-unreferenced-active-exception",
      status: "active",
      scope: "simulated",
      platforms: ["macos"],
      owner: "ui-governance-self-test",
      reason: "Synthetic fixture for active exception inventory mapping enforcement.",
      createdAt: "2026-05-17",
      reviewAfter: "2026-08-15",
      expiresAt: "2026-09-15",
      allowedAction: "conceptual proposal only",
      privateApprovalReference: "private-codex-ui-approval:simulated",
    },
  ];
}

const exceptionIds = new Set();
const exceptionRecords = requireArray(registry, registryPath, "exceptions", { nonEmpty: false });
for (const [index, exception] of exceptionRecords.entries()) {
  const label = `${registryPath}.exceptions[${index}]`;
  requireFields(exception, label, requiredExceptionFields);
  if (exceptionIds.has(exception.id)) fail(`${label}.id duplicates ${exception.id}`);
  exceptionIds.add(exception.id);
  if (!statuses.has(exception.status)) fail(`${label}.status is invalid`);
  for (const platform of requireArray(exception, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  if (exception.status === "active" && exception.expiresAt < today) {
    fail(`${label} active exception expired on ${exception.expiresAt}`);
  }
  if (exception.reviewAfter < today && exception.status === "active") {
    fail(`${label} active exception reviewAfter expired on ${exception.reviewAfter}`);
  }
  const createdAt = requireIsoDate(exception.createdAt, `${label}.createdAt`);
  const reviewAfter = requireIsoDate(exception.reviewAfter, `${label}.reviewAfter`);
  const expiresAt = requireIsoDate(exception.expiresAt, `${label}.expiresAt`);
  if (createdAt && reviewAfter && createdAt > reviewAfter) {
    fail(`${label}.createdAt must not be after reviewAfter`);
  }
  if (reviewAfter && expiresAt && reviewAfter > expiresAt) {
    fail(`${label}.reviewAfter must not be after expiresAt`);
  }
  if (!String(exception.privateApprovalReference || "").startsWith("private-codex-ui-approval:")) {
    fail(`${label}.privateApprovalReference must use private-codex-ui-approval:`);
  }
}

const inventoryPath = "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const referencedExceptionIds = new Set();
for (const [index, entry] of requireArray(inventory, inventoryPath, "coverage").entries()) {
  if (entry?.classification !== "exception") continue;
  const label = `${inventoryPath}.coverage[${index}]`;
  for (const exceptionId of requireArray(entry, label, "exceptionIds")) {
    if (!exceptionIds.has(exceptionId)) fail(`${label}.exceptionIds references unknown exception ${exceptionId}`);
    referencedExceptionIds.add(exceptionId);
  }
}

for (const [index, exception] of exceptionRecords.entries()) {
  if (exception?.status !== "active") continue;
  if (!referencedExceptionIds.has(exception.id)) {
    fail(`${registryPath}.exceptions[${index}] active exception must be referenced by ${inventoryPath}`);
  }
}

scanForLocalPaths(registry, registryPath);

if (errors.length > 0) {
  console.error("UI exception check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI exception check passed (${exceptionIds.size} exceptions)`);
