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

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
  }
}

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const manifestPath = "docs/ui/canon-promotions.registry.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateApprovalAlias",
  "privateBaselineAlias",
  "privateCopyAlias",
  "privateGeometryAlias",
  "promotionStatuses",
  "requiredPromotionFields",
  "promotions",
]);

for (const [field, expected] of [
  ["privateApprovalAlias", "private-codex-ui-approval"],
  ["privateBaselineAlias", "private-codex-ui-baselines"],
  ["privateCopyAlias", "private-codex-ui-copy-snapshots"],
  ["privateGeometryAlias", "private-codex-ui-rendered-geometry"],
]) {
  if (manifest?.[field] !== expected) fail(`${manifestPath}.${field} must be ${expected}`);
}

const statuses = new Set(requireArray(manifest, manifestPath, "promotionStatuses"));
for (const status of ["approved", "revoked", "superseded"]) {
  if (!statuses.has(status)) fail(`${manifestPath}.promotionStatuses must include ${status}`);
}

const requiredPromotionFields = requireArray(manifest, manifestPath, "requiredPromotionFields");
const requiredPromotionFieldSet = new Set(requiredPromotionFields);
for (const field of [
  "id",
  "status",
  "surfaceId",
  "platform",
  "patterns",
  "approvedBy",
  "approvedAt",
  "privateApprovalReference",
  "privateBaselineReference",
  "copySnapshotReference",
  "geometryEvidenceReference",
  "protectedSurfaceId",
]) {
  if (!requiredPromotionFieldSet.has(field)) fail(`${manifestPath}.requiredPromotionFields must include ${field}`);
}

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const protectedSurfaceIds = new Set(
  requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).map((surface) => surface.id),
);

const promotions = requireArray(manifest, manifestPath, "promotions", { nonEmpty: false });
for (const [index, promotion] of promotions.entries()) {
  const label = `${manifestPath}.promotions[${index}]`;
  requireFields(promotion, label, requiredPromotionFields);
  if (!statuses.has(promotion.status)) fail(`${label}.status is invalid`);
  if (!requiredPlatforms.has(promotion.platform)) fail(`${label}.platform is not governed`);
  if (promotion.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  requireArray(promotion, label, "patterns");
  requireAlias(promotion.privateApprovalReference, manifest.privateApprovalAlias, `${label}.privateApprovalReference`);
  requireAlias(promotion.privateBaselineReference, manifest.privateBaselineAlias, `${label}.privateBaselineReference`);
  requireAlias(promotion.copySnapshotReference, manifest.privateCopyAlias, `${label}.copySnapshotReference`);
  requireAlias(promotion.geometryEvidenceReference, manifest.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  if (promotion.status === "approved" && !protectedSurfaceIds.has(promotion.protectedSurfaceId)) {
    fail(`${label}.protectedSurfaceId must reference an approved protected surface`);
  }
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI canon promotion check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI canon promotion check passed (${promotions.length} promotion records)`);
