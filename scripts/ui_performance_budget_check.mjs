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

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const requiredMetrics = ["interactionLatencyMs", "p95FrameTimeMs", "hitchCount", "memoryDeltaMb"];
const allowedBaselineStatuses = new Set(["pending-user-approved-baseline", "approved"]);
const allowedBudgetStatuses = new Set(["pending-approved-measurement", "enforced"]);

const budgetsPath = "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
requireFields(budgets, budgetsPath, [
  "schemaVersion",
  "status",
  "policy",
  "budgetStyle",
  "requiredMetrics",
  "requiredEvidenceFields",
  "evidenceFilename",
  "verificationCommand",
  "flows",
]);
if (budgets?.evidenceFilename !== "performance-evidence.json") {
  fail(`${budgetsPath}.evidenceFilename must be performance-evidence.json`);
}
if (!String(budgets?.verificationCommand || "").includes("scripts/ui_private_performance_budget_verify.mjs --require-approved")) {
  fail(`${budgetsPath}.verificationCommand must run scripts/ui_private_performance_budget_verify.mjs --require-approved`);
}
const budgetStyle = budgets?.budgetStyle || {};
requireFields(budgetStyle, `${budgetsPath}.budgetStyle`, [
  "unit",
  "platformScope",
  "requiredFlows",
  "measurementSource",
  "approvalRequiredBeforeEnforcement",
]);
if (budgetStyle.unit !== "critical-flow") fail(`${budgetsPath}.budgetStyle.unit must be critical-flow`);
if (budgetStyle.platformScope !== "per-governed-platform") {
  fail(`${budgetsPath}.budgetStyle.platformScope must be per-governed-platform`);
}
if (budgetStyle.measurementSource !== "private-baseline") {
  fail(`${budgetsPath}.budgetStyle.measurementSource must be private-baseline`);
}
if (budgetStyle.approvalRequiredBeforeEnforcement !== true) {
  fail(`${budgetsPath}.budgetStyle.approvalRequiredBeforeEnforcement must be true`);
}
const styleFlows = new Set(requireArray(budgetStyle, `${budgetsPath}.budgetStyle`, "requiredFlows"));
for (const flow of requiredFlows) {
  if (!styleFlows.has(flow)) fail(`${budgetsPath}.budgetStyle.requiredFlows must include ${flow}`);
}
const topLevelMetrics = new Set(requireArray(budgets, budgetsPath, "requiredMetrics"));
for (const metric of requiredMetrics) {
  if (!topLevelMetrics.has(metric)) fail(`${budgetsPath}.requiredMetrics must include ${metric}`);
}
const evidenceFields = new Set(requireArray(budgets, budgetsPath, "requiredEvidenceFields"));
for (const field of ["flowId", "platform", "privateBaselineReference", "metrics", "measurementSamples", "measurementHash", "measuredAt", "approvedByUserAt"]) {
  if (!evidenceFields.has(field)) fail(`${budgetsPath}.requiredEvidenceFields must include ${field}`);
}

const privateBaselinesPath = "docs/ui/private-baselines.manifest.json";
const privateBaselines = readJson(privateBaselinesPath);
const baselineByFlow = new Map();
for (const flow of requireArray(privateBaselines, privateBaselinesPath, "flows")) {
  baselineByFlow.set(`${flow.platform}:${flow.id}`, flow);
}

const seen = new Set();
for (const [index, flow] of requireArray(budgets, budgetsPath, "flows").entries()) {
  const label = `${budgetsPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "measurementSource",
    "privateBaselineReference",
    "requiredMetrics",
    "budgetStatus",
  ]);
  const key = `${flow.platform}:${flow.id}`;
  if (seen.has(key)) fail(`${label} duplicates ${key}`);
  seen.add(key);
  if (!requiredPlatforms.includes(flow.platform)) fail(`${label}.platform is not governed`);
  if (!requiredFlows.includes(flow.id)) fail(`${label}.id is not a required critical flow`);
  if (!allowedBaselineStatuses.has(flow.baselineStatus)) fail(`${label}.baselineStatus is invalid`);
  if (!allowedBudgetStatuses.has(flow.budgetStatus)) fail(`${label}.budgetStatus is invalid`);
  if (flow.measurementSource !== "private-baseline") fail(`${label}.measurementSource must be private-baseline`);
  const metrics = new Set(requireArray(flow, label, "requiredMetrics"));
  for (const metric of requiredMetrics) {
    if (!metrics.has(metric)) fail(`${label}.requiredMetrics must include ${metric}`);
  }
  const baseline = baselineByFlow.get(key);
  if (!baseline) {
    fail(`${label} must have matching ${privateBaselinesPath}.flows entry`);
    continue;
  }
  if (baseline.privateBaselineReference !== flow.privateBaselineReference) {
    fail(`${label}.privateBaselineReference must match ${privateBaselinesPath}`);
  }
  if (flow.baselineStatus === "approved" && baseline.baselineStatus !== "approved") {
    fail(`${label}.baselineStatus cannot be approved before private baseline is approved`);
  }
  if (flow.budgetStatus === "enforced" && flow.baselineStatus !== "approved") {
    fail(`${label}.budgetStatus cannot be enforced before baselineStatus is approved`);
  }
}

for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!seen.has(`${platform}:${flow}`)) fail(`${budgetsPath}.flows must include ${platform}:${flow}`);
  }
}

if (errors.length > 0) {
  console.error("UI performance budget check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI performance budget check passed (${seen.size} flow budgets)`);
