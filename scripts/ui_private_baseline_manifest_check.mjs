#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/ui/private-baselines.manifest.json";
const errors = [];

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const requiredEvidence = [
  "captureCommand",
  "geometryHash",
  "screenshotHash",
  "baselineArtifactHash",
  "approvedByUserAt",
  "approvedScope",
];

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

function requireArray(object, label, field) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function hasAbsolutePath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || /^[A-Z]:\\/.test(value) || value.startsWith("file://"));
}

function scanForAbsolutePaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanForAbsolutePaths(item, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForAbsolutePaths(child, `${label}.${key}`);
    return;
  }
  if (hasAbsolutePath(value)) fail(`${label} must not contain a local absolute path`);
}

const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateRootAlias",
  "evidenceFilename",
  "verificationCommand",
  "privateArtifactPolicy",
  "requiredEvidenceFields",
  "flows",
]);

if (manifest?.privateRootAlias !== "private-codex-ui-baselines") {
  fail(`${manifestPath}.privateRootAlias must use the public-safe private alias`);
}
if (manifest?.evidenceFilename !== "evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be evidence.json`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_baseline_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_baseline_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private baseline evidence`);
}

const evidenceFields = new Set(requireArray(manifest, manifestPath, "requiredEvidenceFields"));
for (const field of requiredEvidence) {
  if (!evidenceFields.has(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}

const coverage = new Set();
for (const [index, flow] of requireArray(manifest, manifestPath, "flows").entries()) {
  const label = `${manifestPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "privateBaselineReference",
    "runnerId",
    "requiredEvidence",
    "tolerance",
  ]);
  if (!requiredFlows.includes(flow.id)) fail(`${label}.id is not a required critical flow`);
  if (!requiredPlatforms.includes(flow.platform)) fail(`${label}.platform is not governed`);
  coverage.add(`${flow.platform}:${flow.id}`);
  if (!String(flow.privateBaselineReference || "").startsWith(`${manifest.privateRootAlias}:`)) {
    fail(`${label}.privateBaselineReference must use ${manifest.privateRootAlias}:`);
  }
  const flowEvidence = new Set(requireArray(flow, label, "requiredEvidence"));
  for (const field of requiredEvidence) {
    if (!flowEvidence.has(field)) fail(`${label}.requiredEvidence must include ${field}`);
  }
  if (flow.baselineStatus !== "pending-user-approved-capture" && flow.baselineStatus !== "approved") {
    fail(`${label}.baselineStatus must be pending-user-approved-capture or approved`);
  }
  if (flow.baselineStatus === "approved" && String(flow.privateBaselineReference).includes("pending")) {
    fail(`${label}.privateBaselineReference cannot be pending when approved`);
  }
}

for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!coverage.has(`${platform}:${flow}`)) {
      fail(`${manifestPath}.flows must include ${platform}:${flow}`);
    }
  }
}

scanForAbsolutePaths(manifest, manifestPath);

const forbiddenPrivateAssets = [];
for (const file of fs.readdirSync(path.join(rootDir, "docs/ui"), { recursive: true, withFileTypes: true })) {
  if (!file.isFile()) continue;
  const name = file.name.toLowerCase();
  if (/\.(png|jpg|jpeg|gif|webp|mov|mp4|trace)$/.test(name)) {
    forbiddenPrivateAssets.push(file.name);
  }
}
if (forbiddenPrivateAssets.length > 0) {
  fail(`docs/ui must not contain private baseline media: ${forbiddenPrivateAssets.join(", ")}`);
}

if (errors.length > 0) {
  console.error("UI private baseline manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private baseline manifest check passed");
