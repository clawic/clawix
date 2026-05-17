#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const content = read(relativePath);
  if (!content) return null;
  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
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

function scanPublicSafety(content, label) {
  if (/\/Users\//.test(content) || /~\//.test(content) || /file:\/\//.test(content) || /^[A-Z]:\\/m.test(content)) {
    fail(`${label} must not publish local private paths`);
  }
  if (/BEGIN [A-Z ]*PRIVATE KEY/.test(content) || /\bAKIA[0-9A-Z]{16}\b/.test(content) || /\bsk-[A-Za-z0-9]{20,}\b/.test(content)) {
    fail(`${label} must not publish secret-like values`);
  }
  if (/rollout-2026-05-15T13-21-46/.test(content)) {
    fail(`${label} must use the public-safe source session alias, not the private filename`);
  }
}

function runPrivateEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("private evidence plan must pass before completion audit can be verified");
    if (result.stderr) {
      for (const line of result.stderr.trim().split("\n")) fail(`private evidence plan: ${line}`);
    }
    return { counts: {}, evidence: [] };
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { counts: {}, evidence: [] };
  }
}

function countPrivateApprovalRecords() {
  const approvalAuthorityPath = "docs/ui/approval-authority.manifest.json";
  const approvalAuthority = readJson(approvalAuthorityPath);
  let count = 0;
  for (const [sourceIndex, source] of requireArray(approvalAuthority, approvalAuthorityPath, "approvalSources").entries()) {
    const sourceLabel = `${approvalAuthorityPath}.approvalSources[${sourceIndex}]`;
    const registry = readJson(source?.path || "");
    const records = requireArray(registry, source?.path || sourceLabel, source?.arrayField || "items", { nonEmpty: false });
    const approvalRequiredStatuses = Array.isArray(source?.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const record of records) {
      if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) continue;
      count += 1;
    }
  }
  return count;
}

const auditPath = "docs/ui/completion-audit.md";
const decisionPath = "docs/ui/decision-verification.json";
const audit = read(auditPath);
const decisionVerification = readJson(decisionPath);
const privateVisualValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const completionSource = readJson("docs/ui/completion-source.manifest.json");
const privateEvidencePlan = runPrivateEvidencePlan();
const privateApprovalRecordCount = countPrivateApprovalRecords();
scanPublicSafety(audit, auditPath);

for (const required of [
  "private-codex-goal:clawix-interface-governance-plan-2026-05-15.md",
  "private-codex-session:019e2b5e-fe48-7231-8e13-49411999b001",
  "private session, not published",
  "Do not call update_goal",
]) {
  if (!audit.includes(required)) fail(`${auditPath} must include ${required}`);
}

const decisions = requireArray(decisionVerification, decisionPath, "decisions");
const openDecisions = decisions.filter((decision) => decision?.status === "open");
if (openDecisions.length > 0 && !audit.includes("Completion status: blocked by EXTERNAL PENDING private evidence.")) {
  fail(`${auditPath} must state completion is blocked while decisions remain open`);
}
if (openDecisions.length === 0 && audit.includes("Completion status: blocked")) {
  fail(`${auditPath} must not stay blocked when all decisions are verified-complete`);
}

const plannedEvidenceTotal = Array.isArray(privateEvidencePlan.evidence) ? privateEvidencePlan.evidence.length : 0;
if (!audit.includes(`Private evidence plan: ${plannedEvidenceTotal} records must be verified before completion.`)) {
  fail(`${auditPath} must state the derived private evidence total`);
}
if (!audit.includes(`Private approval evidence: ${privateApprovalRecordCount} record(s) must be verified before completion.`)) {
  fail(`${auditPath} must state the private approval evidence total`);
}
const sourceSessionRequirements = completionSource?.sourceSessionRequirements || {};
for (const recordType of sourceSessionRequirements.requiredRecordTypes || []) {
  if (!audit.includes(recordType)) fail(`${auditPath} must include source session record type ${recordType}`);
}
if (!audit.includes(`at least ${sourceSessionRequirements.minimumUserMessages} user message records`)) {
  fail(`${auditPath} must state the source session user message minimum`);
}
if (sourceSessionRequirements.decisionsBeforeFirstGoalEvent && !audit.includes("before the first `thread_goal_*` event")) {
  fail(`${auditPath} must state decisions are verified before the first thread_goal event`);
}
for (const [type, count] of Object.entries(privateEvidencePlan.counts || {})) {
  const row = `| \`${type}\` | ${count} |`;
  if (!audit.includes(row)) fail(`${auditPath} must include private evidence count row ${row}`);
}
const decisionBlockerEvidenceTypes = requireArray(
  privateVisualValidation,
  "docs/ui/private-visual-validation.manifest.json",
  "decisionBlockerEvidenceTypes",
);
for (const entry of decisionBlockerEvidenceTypes) {
  const evidenceTypes = requireArray(entry, `docs/ui/private-visual-validation.manifest.json.${entry?.decisionId || "unknown"}`, "evidenceTypes");
  const row = `| \`${entry.decisionId}\` | ${evidenceTypes.map((type) => `\`${type}\``).join(", ")} |`;
  if (!audit.includes(row)) fail(`${auditPath} must include open decision evidence row ${row}`);
}

const rowPattern = /^\| (\d+) \| `([^`]+)` \| ([^|]+) \| ([^|]+) \|$/gm;
const rows = [];
let match;
while ((match = rowPattern.exec(audit)) !== null) {
  rows.push({
    index: Number(match[1]),
    id: match[2],
    status: match[3].trim(),
    evidenceState: match[4].trim(),
  });
}

if (rows.length !== decisions.length) {
  fail(`${auditPath} must include one completion row per decision`);
}

const rowsById = new Map(rows.map((row) => [row.id, row]));
const approvalDecisionIds = new Set([
  "canon_approval",
  "human_visual_review",
  "approved_surface_protection",
  "visual_model_gate",
  "visual_change_scope_limit",
  "approved_baseline_authority",
]);
for (const decision of decisions) {
  const row = rowsById.get(decision.id);
  const label = `${auditPath}.${decision.id}`;
  if (!row) {
    fail(`${label} is missing`);
    continue;
  }
  if (row.index !== decision.index) fail(`${label} must use index ${decision.index}`);
  if (row.status !== decision.status) fail(`${label} status must match ${decisionPath}`);
  if (decision.status === "open" && !row.evidenceState.includes("EXTERNAL PENDING")) {
    fail(`${label} must identify private evidence as EXTERNAL PENDING`);
  }
  if (decision.status === "verified-complete" && approvalDecisionIds.has(decision.id)) {
    if (row.evidenceState !== "Public approval evidence and private approval verifier wired.") {
      fail(`${label} must state private approval verifier is wired`);
    }
    continue;
  }
  if (decision.status === "verified-complete" && row.evidenceState !== "Public evidence verified.") {
    fail(`${label} must state public evidence is verified`);
  }
}

if (errors.length > 0) {
  console.error("UI completion audit check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI completion audit check passed (${rows.length} decisions, ${openDecisions.length} open)`);
