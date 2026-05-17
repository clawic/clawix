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

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const detectorPath = "docs/ui/visual-change-detectors.manifest.json";
const manifest = readJson(detectorPath);
requireFields(manifest, detectorPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceRoots",
  "requiredChangeKinds",
  "classificationBuckets",
  "detectors",
]);

const sourceRoots = new Set(requireArray(manifest, detectorPath, "sourceRoots"));
for (const root of ["macos/Sources", "ios/Sources", "apps/macos/Sources", "apps/ios/Sources", "android/app/src/main", "web/src"]) {
  if (!sourceRoots.has(root)) fail(`${detectorPath}.sourceRoots must include ${root}`);
}

const requiredKinds = new Set(requireArray(manifest, detectorPath, "requiredChangeKinds"));
for (const kind of [
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
]) {
  if (!requiredKinds.has(kind)) fail(`${detectorPath}.requiredChangeKinds must include ${kind}`);
}

const requiredBuckets = new Map([
  ["presentation", ["color", "spacing", "size", "icon", "layout", "animation", "typography"]],
  ["copy", ["microcopy", "visible-name"]],
  ["hierarchy", ["ordering", "hierarchy"]],
]);
const bucketsById = new Map();
for (const [index, bucket] of requireArray(manifest, detectorPath, "classificationBuckets").entries()) {
  const label = `${detectorPath}.classificationBuckets[${index}]`;
  requireFields(bucket, label, ["id", "changeKinds"]);
  if (bucket?.id) bucketsById.set(bucket.id, bucket);
  for (const kind of requireArray(bucket, label, "changeKinds")) {
    if (!requiredKinds.has(kind)) fail(`${label}.changeKinds contains unregistered ${kind}`);
  }
}
for (const [bucketId, kinds] of requiredBuckets.entries()) {
  const bucket = bucketsById.get(bucketId);
  if (!bucket) {
    fail(`${detectorPath}.classificationBuckets must include ${bucketId}`);
    continue;
  }
  const bucketKinds = new Set(bucket.changeKinds || []);
  for (const kind of kinds) {
    if (!bucketKinds.has(kind)) fail(`${detectorPath}.classificationBuckets.${bucketId} must include ${kind}`);
  }
}

const seenKinds = new Set();
const seenPlatforms = new Set();
for (const [index, detector] of requireArray(manifest, detectorPath, "detectors").entries()) {
  const label = `${detectorPath}.detectors[${index}]`;
  requireFields(detector, label, ["id", "platforms", "changeKind", "pattern", "reason"]);
  if (!requiredKinds.has(detector.changeKind)) fail(`${label}.changeKind is not registered`);
  seenKinds.add(detector.changeKind);
  for (const platform of requireArray(detector, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
    seenPlatforms.add(platform);
  }
  try {
    new RegExp(detector.pattern);
  } catch (error) {
    fail(`${label}.pattern is not a valid regex: ${error.message}`);
  }
}

for (const kind of requiredKinds) {
  if (!seenKinds.has(kind)) fail(`${detectorPath}.detectors must cover ${kind}`);
}
for (const platform of requiredPlatforms) {
  if (!seenPlatforms.has(platform)) fail(`${detectorPath}.detectors must cover ${platform}`);
}

if (errors.length > 0) {
  console.error("UI visual detector check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual detector check passed (${seenKinds.size} change kinds, ${seenPlatforms.size} platforms)`);
