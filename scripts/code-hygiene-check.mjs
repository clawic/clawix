import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function readText(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(readText(relativePath));
}

function fail(message) {
  errors.push(message);
}

const decisions = readJson("docs/code-hygiene-decisions.json");
const baseline = readJson("docs/code-hygiene-baseline.json");
const tools = readJson("docs/code-hygiene-tools.json");
const report = readJson("docs/code-hygiene-report.json");
const reportMarkdown = readText("docs/code-hygiene-report.md");
const ledger = readText("docs/code-hygiene-ledger.md");
const decisionChecklist = readText("docs/code-hygiene-decision-checklist.md");

if (decisions.schemaVersion !== 1) fail("code hygiene decisions schemaVersion must be 1");
if (decisions.program !== "code-hygiene") fail("code hygiene decisions program must be code-hygiene");
if (decisions.decisionCount !== 33) fail("code hygiene decisionCount must be 33");
if (!Array.isArray(decisions.decisions) || decisions.decisions.length !== decisions.decisionCount) {
  fail("code hygiene decisions length must match decisionCount");
}
for (const [index, decision] of (decisions.decisions ?? []).entries()) {
  if (!decision.id) fail(`code hygiene decision ${index} is missing id`);
  if (!decision.answer) fail(`code hygiene decision ${decision.id ?? index} is missing answer`);
}
if ("sourceSessionPath" in decisions) fail("code hygiene decisions must not publish private sourceSessionPath");

if (baseline.schemaVersion !== 1) fail("code hygiene baseline schemaVersion must be 1");
if (baseline.program !== "code-hygiene") fail("code hygiene baseline program must be code-hygiene");
if (baseline.defaultExpiryDays !== 90) fail("code hygiene baseline defaultExpiryDays must be 90");
if (!Array.isArray(baseline.categories) || baseline.categories.length === 0) {
  fail("code hygiene baseline must define categories");
}
for (const entry of baseline.entries ?? []) {
  if (!entry.reason) fail("code hygiene baseline entry is missing reason");
  if (!entry.ownerArea) fail("code hygiene baseline entry is missing ownerArea");
  if (!entry.reference) fail("code hygiene baseline entry is missing reference");
  if (!entry.expiresAt) fail("code hygiene baseline entry is missing expiresAt");
}

if (tools.schemaVersion !== 1) fail("code hygiene tools schemaVersion must be 1");
if (tools.tools?.knip?.version !== "6.14.0") fail("code hygiene Knip version must be 6.14.0");
if (!tools.tools?.periphery?.version) fail("code hygiene Periphery version must be documented");
const packageCandidates = ["package.json", "web/package.json"];
const hasKnipDependency = packageCandidates
  .filter((relativePath) => fs.existsSync(path.join(rootDir, relativePath)))
  .some((relativePath) => readJson(relativePath).devDependencies?.knip === "6.14.0");
if (!hasKnipDependency) fail("Knip must be pinned as a dev dependency");

if (report.schemaVersion !== 1) fail("code hygiene report schemaVersion must be 1");
if (report.program !== "code-hygiene") fail("code hygiene report program must be code-hygiene");
if (!report.generatedAt) fail("code hygiene report must include generatedAt");
if (!report.lastAuditSummary) fail("code hygiene report must include lastAuditSummary");
for (const field of ["scannedFiles", "todoFindings", "duplicateAssetGroups", "duplicateAssetFiles", "unreferencedAssetCandidates"]) {
  if (typeof report.lastAuditSummary?.[field] !== "number") {
    fail(`code hygiene report lastAuditSummary must include numeric ${field}`);
  }
}
if (!reportMarkdown.includes("docs/code-hygiene-report.json")) fail("code hygiene Markdown report must link the JSON pair");
if (!reportMarkdown.includes("unreferenced asset candidates")) fail("code hygiene Markdown report must mention unreferenced asset candidates");
if (!ledger.includes("private session, not published")) fail("code hygiene ledger must not publish private session paths");
if (!decisionChecklist.includes("rollout_model")) fail("code hygiene decision checklist must include rollout_model");
if (!decisionChecklist.includes("Cleanup campaign is pending")) fail("code hygiene decision checklist must record pending cleanup campaign");

for (const relativePath of [
  "docs/adr/0016-code-hygiene-program.md",
  "docs/code-hygiene-decisions.json",
  "docs/code-hygiene-baseline.json",
  "docs/code-hygiene-decision-checklist.md",
  "docs/code-hygiene-tools.json",
  "docs/code-hygiene-ledger.md",
  "docs/code-hygiene-report.json",
  "docs/code-hygiene-report.md",
  "scripts/code-hygiene-audit.mjs",
  "skills/code-hygiene-audit/SKILL.md",
  "skills/code-hygiene-cleanup/SKILL.md",
]) {
  const text = readText(relativePath);
  if (/\/Users\/trabajo\b/.test(text)) fail(`${relativePath} contains a private maintainer path`);
  if (/\b(is|for|as|id)\s+`\s*`/.test(text) || /\bfor\s+\./.test(text)) fail(`${relativePath} appears to contain an empty placeholder`);
}

if (errors.length > 0) {
  console.error("code hygiene check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(process.argv.includes("--self-test") ? "code hygiene check self-test passed" : "code hygiene check passed");
