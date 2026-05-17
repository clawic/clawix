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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
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

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const queuePath = "docs/ui/critical-cleanup.queue.json";
const queue = readJson(queuePath);
requireFields(queue, queuePath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceDebtReport",
  "visualModelAllowlist",
  "requiredVisualModel",
  "v1Delivery",
  "queueStatuses",
  "requiredItemFields",
  "items",
]);

const debtReportPath = queue?.sourceDebtReport || "docs/ui/debt-report.registry.json";
const debtReport = readJson(debtReportPath);
const debtItems = new Map();
for (const item of requireArray(debtReport, debtReportPath, "pendingItems")) {
  debtItems.set(item.debtId, item);
}

const allowlistPath = queue?.visualModelAllowlist || "docs/ui/visual-model-allowlist.manifest.json";
const allowlist = readJson(allowlistPath);
const activeModels = new Set(
  requireArray(allowlist, allowlistPath, "allowedVisualModels")
    .filter((model) => model?.status === "active")
    .map((model) => model.id),
);
if (!activeModels.has(queue?.requiredVisualModel)) {
  fail(`${queuePath}.requiredVisualModel must be active in ${allowlistPath}`);
}

const v1Delivery = queue?.v1Delivery || {};
requireFields(v1Delivery, `${queuePath}.v1Delivery`, [
  "goal",
  "cleanupDeliveryState",
  "completionCondition",
  "nonVisualAgentAction",
  "blockedUntil",
]);
if (v1Delivery.goal !== "governance-system-plus-critical-cleanup") {
  fail(`${queuePath}.v1Delivery.goal must be governance-system-plus-critical-cleanup`);
}
if (v1Delivery.cleanupDeliveryState !== "tracked-pending-for-allowlisted-model") {
  fail(`${queuePath}.v1Delivery.cleanupDeliveryState must be tracked-pending-for-allowlisted-model`);
}
if (v1Delivery.completionCondition !== "completed-by-allowlisted-visual-model-or-tracked-pending-with-private-approval-required") {
  fail(`${queuePath}.v1Delivery.completionCondition must require completion or tracked pending approval`);
}
if (v1Delivery.nonVisualAgentAction !== "track-only") {
  fail(`${queuePath}.v1Delivery.nonVisualAgentAction must be track-only`);
}
const blockedUntil = new Set(requireArray(v1Delivery, `${queuePath}.v1Delivery`, "blockedUntil"));
for (const blocker of ["approved-visual-scope", "private-baseline", "copy-snapshot", "rendered-geometry"]) {
  if (!blockedUntil.has(blocker)) fail(`${queuePath}.v1Delivery.blockedUntil must include ${blocker}`);
}

const statuses = new Set(requireArray(queue, queuePath, "queueStatuses"));
for (const status of ["queued-visual-authorized-lane", "blocked-without-approval", "in-progress", "completed"]) {
  if (!statuses.has(status)) fail(`${queuePath}.queueStatuses must include ${status}`);
}

const requiredItemFields = requireArray(queue, queuePath, "requiredItemFields");
for (const field of [
  "id",
  "debtId",
  "status",
  "scope",
  "platforms",
  "requiredVisualModel",
  "requiredAuthorization",
  "privateApprovalRequired",
  "allowedCurrentAction",
]) {
  if (!requiredItemFields.includes(field)) fail(`${queuePath}.requiredItemFields must include ${field}`);
}

const queuedDebtIds = new Set();
for (const [index, item] of requireArray(queue, queuePath, "items").entries()) {
  const label = `${queuePath}.items[${index}]`;
  requireFields(item, label, requiredItemFields);
  if (!statuses.has(item.status)) fail(`${label}.status is invalid`);
  if (item.requiredVisualModel !== queue.requiredVisualModel) fail(`${label}.requiredVisualModel must match ${queuePath}`);
  if (item.requiredAuthorization !== "visual-authorized-lane") fail(`${label}.requiredAuthorization must be visual-authorized-lane`);
  if (item.privateApprovalRequired !== true) fail(`${label}.privateApprovalRequired must be true`);
  if (!String(item.allowedCurrentAction || "").includes("Queue only")) {
    fail(`${label}.allowedCurrentAction must keep cleanup non-executable for non-visual agents`);
  }
  for (const platform of requireArray(item, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  const debtItem = debtItems.get(item.debtId);
  if (!debtItem) {
    fail(`${label}.debtId must reference ${debtReportPath}`);
    continue;
  }
  if (item.scope !== debtItem.scope) fail(`${label}.scope must match ${debtReportPath}`);
  if (JSON.stringify(item.platforms) !== JSON.stringify(debtItem.platforms)) {
    fail(`${label}.platforms must match ${debtReportPath}`);
  }
  queuedDebtIds.add(item.debtId);
}

for (const debtId of debtItems.keys()) {
  if (!queuedDebtIds.has(debtId)) fail(`${queuePath}.items must include debtId ${debtId}`);
}

scanForLocalPaths(queue, queuePath);

if (errors.length > 0) {
  console.error("UI critical cleanup queue check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI critical cleanup queue check passed (${queuedDebtIds.size} queued items)`);
