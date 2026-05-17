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

const manifestPath = "docs/ui/pattern-performance.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "patternRegistryPath",
  "performanceBudgetRegistryPath",
  "privateBaselineAlias",
  "requiredFlowMappings",
]);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.privateBaselineAlias !== "private-codex-ui-baselines") {
  fail(`${manifestPath}.privateBaselineAlias must be private-codex-ui-baselines`);
}

const registryPath = manifest?.patternRegistryPath || "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = new Set(requireArray(registry, registryPath, "patterns"));

const budgetsPath = manifest?.performanceBudgetRegistryPath || "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
const budgetFlows = new Set(requireArray(budgets, budgetsPath, "flows").map((flow) => flow.id));
const budgetPlatforms = new Map();
for (const flow of requireArray(budgets, budgetsPath, "flows")) {
  if (!flow?.id || !flow?.platform) continue;
  const platforms = budgetPlatforms.get(flow.id) || new Set();
  platforms.add(flow.platform);
  budgetPlatforms.set(flow.id, platforms);
}

const mappedFlows = new Set();
for (const [index, mapping] of requireArray(manifest, manifestPath, "requiredFlowMappings").entries()) {
  const label = `${manifestPath}.requiredFlowMappings[${index}]`;
  requireFields(mapping, label, ["flowId", "patterns"]);
  if (!budgetFlows.has(mapping?.flowId)) fail(`${label}.flowId must exist in ${budgetsPath}`);
  mappedFlows.add(mapping?.flowId);
  for (const patternId of requireArray(mapping, label, "patterns")) {
    if (!patternIds.has(patternId)) {
      fail(`${label}.patterns references unknown pattern ${patternId}`);
      continue;
    }
    const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
    const pattern = readJson(patternPath);
    const performance = pattern?.performance || {};
    requireFields(performance, `${patternPath}.performance`, [
      "criticalFlows",
      "budgetRegistry",
      "privateBaselineAlias",
    ]);
    if (performance.budgetRegistry !== budgetsPath) {
      fail(`${patternPath}.performance.budgetRegistry must be ${budgetsPath}`);
    }
    if (performance.privateBaselineAlias !== manifest.privateBaselineAlias) {
      fail(`${patternPath}.performance.privateBaselineAlias must match ${manifestPath}`);
    }
    const criticalFlows = new Set(requireArray(performance, `${patternPath}.performance`, "criticalFlows", { nonEmpty: false }));
    if (!criticalFlows.has(mapping.flowId)) {
      fail(`${patternPath}.performance.criticalFlows must include ${mapping.flowId}`);
    }
  }
}

for (const flow of budgetFlows) {
  if (!mappedFlows.has(flow)) fail(`${manifestPath}.requiredFlowMappings must map critical flow ${flow}`);
}
for (const [flow, platforms] of budgetPlatforms.entries()) {
  for (const platform of ["macos", "ios", "android", "web"]) {
    if (!platforms.has(platform)) fail(`${budgetsPath}.flows must include ${platform}:${flow}`);
  }
}

for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  const performance = pattern?.performance || {};
  requireFields(performance, `${patternPath}.performance`, [
    "criticalFlows",
    "budgetRegistry",
    "privateBaselineAlias",
  ]);
  if (performance.budgetRegistry !== budgetsPath) {
    fail(`${patternPath}.performance.budgetRegistry must be ${budgetsPath}`);
  }
  if (performance.privateBaselineAlias !== manifest?.privateBaselineAlias) {
    fail(`${patternPath}.performance.privateBaselineAlias must be ${manifestPath}.privateBaselineAlias`);
  }
  for (const flowId of requireArray(performance, `${patternPath}.performance`, "criticalFlows", { nonEmpty: false })) {
    if (!budgetFlows.has(flowId)) fail(`${patternPath}.performance.criticalFlows references unknown flow ${flowId}`);
  }
}

if (errors.length > 0) {
  console.error("UI pattern performance check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI pattern performance check passed (${mappedFlows.size} critical flows, ${patternIds.size} patterns)`);
