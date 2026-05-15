#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

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

function requireFields(object, relativePath, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${relativePath} is missing ${field}`);
    }
  }
}

function requireArray(object, relativePath, field, { nonEmpty = true } = {}) {
  if (!object) return [];
  const value = object[field];
  if (!Array.isArray(value)) {
    fail(`${relativePath}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${relativePath}.${field} must not be empty`);
  }
  return value;
}

function git(args) {
  try {
    return execFileSync("git", ["-C", rootDir, ...args], { encoding: "utf8" });
  } catch {
    return "";
  }
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
requireFields(config, configPath, [
  "schemaVersion",
  "status",
  "platforms",
  "visualAuthorizationPolicy",
  "mutationClasses",
  "restrictedChangeKinds",
  "requiredInteractiveStates",
]);

const requiredPlatforms = ["macos", "ios", "android", "web"];
const platforms = new Set(requireArray(config, configPath, "platforms"));
for (const platform of requiredPlatforms) {
  if (!platforms.has(platform)) fail(`${configPath}.platforms must include ${platform}`);
}

const visualAuthorization = config?.visualAuthorizationPolicy || {};
requireFields(visualAuthorization, `${configPath}.visualAuthorizationPolicy`, [
  "mode",
  "privateAssignment",
  "publicSignalEnv",
  "publicSignalValue",
]);
if (visualAuthorization.mode !== "private-allowlist") {
  fail(`${configPath}.visualAuthorizationPolicy.mode must be private-allowlist`);
}
if (visualAuthorization.privateAssignment !== "outside-public-repo") {
  fail(`${configPath}.visualAuthorizationPolicy.privateAssignment must stay outside-public-repo`);
}

const requiredStates = [
  "idle",
  "hover-or-highlight",
  "focused",
  "pressed",
  "disabled",
  "selected",
  "busy",
  "error",
];
const configuredStates = new Set(requireArray(config, configPath, "requiredInteractiveStates"));
for (const state of requiredStates) {
  if (!configuredStates.has(state)) fail(`${configPath}.requiredInteractiveStates must include ${state}`);
}

const indexPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(indexPath);
requireFields(registry, indexPath, ["schemaVersion", "platforms", "patterns"]);
const registryPatterns = requireArray(registry, indexPath, "patterns");
const registryPlatforms = new Set(requireArray(registry, indexPath, "platforms"));
for (const platform of requiredPlatforms) {
  if (!registryPlatforms.has(platform)) fail(`${indexPath}.platforms must include ${platform}`);
}

for (const patternId of registryPatterns) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  requireFields(pattern, patternPath, [
    "schemaVersion",
    "id",
    "status",
    "platforms",
    "mutationClass",
    "canonicalReferences",
    "states",
    "geometry",
    "copy",
    "componentExtraction",
    "validation",
  ]);
  if (!pattern) continue;
  if (pattern.id !== patternId) fail(`${patternPath}.id must be ${patternId}`);
  const states = new Set(requireArray(pattern, patternPath, "states"));
  for (const state of requiredStates) {
    if (!states.has(state)) fail(`${patternPath}.states must include ${state}`);
  }
  const patternPlatforms = requireArray(pattern, patternPath, "platforms");
  if (!patternPlatforms.some((platform) => requiredPlatforms.includes(platform))) {
    fail(`${patternPath}.platforms must include at least one governed platform`);
  }
  const extraction = pattern.componentExtraction || {};
  if (!["required", "required-when-repeated-with-state", "allowed", "forbidden"].includes(extraction.policy)) {
    fail(`${patternPath}.componentExtraction.policy is invalid`);
  }
  if (!["limited-slots", "wrapper-plus-modifier", "local-composition"].includes(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api must encode the agreed component API strategy`);
  }
}

const debtPath = "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
requireFields(debt, debtPath, ["schemaVersion", "status", "policy", "entries"]);
for (const [index, entry] of requireArray(debt, debtPath, "entries").entries()) {
  const label = `${debtPath}.entries[${index}]`;
  requireFields(entry, label, ["id", "scope", "platforms", "reason", "owner", "status", "reviewAfter", "allowedAction"]);
  if (entry.reviewAfter && entry.reviewAfter < today) {
    fail(`${label} expired on ${entry.reviewAfter}`);
  }
}

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
requireFields(protectedSurfaces, protectedPath, ["schemaVersion", "status", "policy", "surfaces"]);
for (const [index, surface] of requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, ["id", "scope", "approvedBy", "approvedAt", "contract", "privateBaselineReference"]);
}

const budgetsPath = "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
requireFields(budgets, budgetsPath, ["schemaVersion", "status", "policy", "flows"]);
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const seenFlows = new Set();
for (const [index, flow] of requireArray(budgets, budgetsPath, "flows").entries()) {
  const label = `${budgetsPath}.flows[${index}]`;
  requireFields(flow, label, ["id", "platform", "baselineStatus"]);
  seenFlows.add(flow.id);
}
for (const flow of requiredFlows) {
  if (!seenFlows.has(flow)) fail(`${budgetsPath}.flows must include ${flow}`);
}

const inspirationPath = "docs/ui/inspiration/references.registry.json";
const inspiration = readJson(inspirationPath);
requireFields(inspiration, inspirationPath, ["schemaVersion", "policy", "references"]);
for (const [index, reference] of requireArray(inspiration, inspirationPath, "references").entries()) {
  const label = `${inspirationPath}.references[${index}]`;
  requireFields(reference, label, ["id", "url", "use", "canonical"]);
  if (reference.canonical !== false) {
    fail(`${label}.canonical must be false until explicitly approved`);
  }
}

const changedBase = process.env.CLAWIX_UI_GUARD_DIFF_BASE;
const sourcePaths = [
  "macos/Sources",
  "ios/Sources",
  "android/app/src/main",
  "web/src",
];
const diffArgs = changedBase
  ? ["diff", "--unified=0", changedBase, "--", ...sourcePaths]
  : ["diff", "--unified=0", "--", ...sourcePaths];
const stagedDiffArgs = ["diff", "--cached", "--unified=0", "--", ...sourcePaths];
const combinedDiff = `${git(diffArgs)}\n${changedBase ? "" : git(stagedDiffArgs)}`;

const visualPattern = /\b(Color|Palette|MenuStyle|Typography|AppLayout|Image\(systemName:|LucideIcon|RoundedRectangle|Capsule|Circle|HStack|VStack|ZStack|Spacer|Text\("|font\(|foregroundColor|foregroundStyle|background|padding|frame|cornerRadius|opacity|tracking|textCase|animation|transition|lineLimit|help\("|accessibilityLabel\()/;
const visualAuthorizationEnv = String(visualAuthorization.publicSignalEnv || "");
const visualAuthorizationValue = String(visualAuthorization.publicSignalValue || "");
const visualAuthorized = Boolean(visualAuthorizationEnv) && process.env[visualAuthorizationEnv] === visualAuthorizationValue;
const visualLines = [];
for (const line of combinedDiff.split("\n")) {
  if (!line.startsWith("+") || line.startsWith("+++")) continue;
  if (visualPattern.test(line)) {
    visualLines.push(line.slice(0, 240));
  }
}
if (visualLines.length > 0 && !visualAuthorized) {
  fail(
    [
      "unauthorized visual/copy/layout source edit detected",
      `set ${visualAuthorizationEnv}=${visualAuthorizationValue} only when the task has explicit visual authorization from the private policy`,
      "non-authorized agents must leave a conceptual proposal instead of editing visible presentation",
      ...visualLines.slice(0, 20).map((line) => `  ${line}`),
    ].join("\n"),
  );
}

const requiredDocs = [
  "docs/adr/0010-interface-governance.md",
  "docs/ui/README.md",
  "docs/ui/pattern-registry/README.md",
  "docs/ui/interface-governance.config.json",
  "docs/ui/debt.baseline.json",
  "docs/ui/protected-surfaces.registry.json",
  "docs/ui/performance-budgets.registry.json",
  "docs/ui/inspiration/references.registry.json",
];
for (const relativePath of requiredDocs) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) {
    fail(`missing required UI governance file ${relativePath}`);
  }
}

if (errors.length > 0) {
  console.error("UI governance guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI governance guard passed");
