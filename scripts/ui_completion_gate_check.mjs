#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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

function scanPublicSafety(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanPublicSafety(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanPublicSafety(child, `${label}.${key}`);
    return;
  }
  if (typeof value !== "string") return;
  if (/\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not publish a local private path`);
  }
}

function withoutPrivateCompletionEnv() {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith("CLAWIX_UI_PRIVATE_")) delete env[key];
  }
  return env;
}

function withTemporaryCompletionSources(sourceManifest, callback) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ui-completion-"));
  try {
    const goalFile = path.join(tempRoot, "goal.md");
    const sessionFile = path.join(tempRoot, "session.jsonl");
    const decisions = sourceManifest?.expectedDecisions || [];
    const decisionLines = decisions.map((decision) => `- \`${decision.id}\`: ${decision.choice}`).join("\n");
    fs.writeFileSync(
      goalFile,
      [
        sourceManifest.expectedConversationId,
        "Required Decision Verification Checklist",
        "Do not mark the associated goal complete",
        "update_goal(status:",
        decisionLines,
      ].join("\n"),
    );
    fs.writeFileSync(
      sessionFile,
      [
        JSON.stringify({ type: "session_meta", payload: { id: sourceManifest.expectedConversationId } }),
        ...Array.from({ length: sourceManifest.sourceSessionRequirements?.minimumUserMessages || 1 }, (_, index) =>
          JSON.stringify({
            type: "event_msg",
            payload: {
              type: "user_message",
              text: index === 0 ? decisionLines : `source verification user message ${index}`,
            },
          }),
        ),
        JSON.stringify({
          type: "response_item",
          payload: {
            type: "message",
            text: decisions.map((decision) => `${decision.id}: ${decision.choice}`).join("\n"),
          },
        }),
        ...decisions.map((decision) =>
          JSON.stringify({
            type: "response_item",
            payload: {
              type: "message",
              text: `${decision.id}: ${decision.choice}`,
            },
          }),
        ),
      ].join("\n"),
    );
    return callback({
      [sourceManifest.privateGoalFileEnv]: goalFile,
      [sourceManifest.privateSourceSessionFileEnv]: sessionFile,
    });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

function approvalRecords(approvalManifest) {
  const records = [];
  for (const [sourceIndex, source] of requireArray(approvalManifest, "docs/ui/approval-authority.manifest.json", "approvalSources").entries()) {
    const label = `docs/ui/approval-authority.manifest.json.approvalSources[${sourceIndex}]`;
    requireFields(source, label, ["id", "path", "arrayField", "privateApprovalField"]);
    if (!source?.path || !source?.arrayField || !source?.privateApprovalField) continue;
    const registry = readJson(source.path);
    const requiredStatuses = Array.isArray(source.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const record of requireArray(registry, source.path, source.arrayField, { nonEmpty: false })) {
      if (requiredStatuses && !requiredStatuses.has(record?.[source.statusField])) continue;
      records.push(record);
    }
  }
  return records;
}

function mechanicalEquivalenceRecords(mechanicalManifest) {
  return requireArray(mechanicalManifest, "docs/ui/mechanical-equivalence.manifest.json", "records", { nonEmpty: false });
}

function requireConditionalRootContract({ rootsByEnv, env, condition, manifestPath: sourceManifestPath }) {
  if (!env || !condition || !sourceManifestPath) {
    fail(`${manifestPath}.conditionalPrivateRoots entries must include env, condition, and manifestPath`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, sourceManifestPath))) {
    fail(`${manifestPath}.conditionalPrivateRoots entry for ${env} points to missing ${sourceManifestPath}`);
  }
  if (!rootsByEnv.has(env)) {
    fail(`${manifestPath}.conditionalPrivateRoots entry for ${env} must map to a private visual optional root alias`);
  }
}

const manifestPath = "docs/ui/completion-gate.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "decisionVerificationPath",
  "completionAuditPath",
  "completionSourceManifestPath",
  "privateVisualValidationManifestPath",
  "approvalAuthorityManifestPath",
  "publicCheckScript",
  "privateVerifierScript",
  "privateApprovalVerifierScript",
  "finalVerificationCommand",
  "conditionalPrivateRoots",
  "requiredPublicChecks",
  "publicPrerequisiteScripts",
  "goalUpdateRule",
  "externalPendingExitCode",
]);
scanPublicSafety(manifest, manifestPath);

if (manifest?.publicCheckScript !== "scripts/ui_completion_gate_check.mjs") {
  fail(`${manifestPath}.publicCheckScript must be scripts/ui_completion_gate_check.mjs`);
}
if (manifest?.privateVerifierScript !== "scripts/ui_private_completion_verify.mjs") {
  fail(`${manifestPath}.privateVerifierScript must be scripts/ui_private_completion_verify.mjs`);
}
if (manifest?.privateApprovalVerifierScript !== "scripts/ui_private_approval_verify.mjs") {
  fail(`${manifestPath}.privateApprovalVerifierScript must be scripts/ui_private_approval_verify.mjs`);
}
if (!String(manifest?.finalVerificationCommand || "").includes("scripts/ui_private_completion_verify.mjs --require-approved")) {
  fail(`${manifestPath}.finalVerificationCommand must require the private completion verifier`);
}
if (!String(manifest?.goalUpdateRule || "").includes("update_goal")) {
  fail(`${manifestPath}.goalUpdateRule must mention update_goal`);
}
if (manifest?.externalPendingExitCode !== 2) fail(`${manifestPath}.externalPendingExitCode must be 2`);

for (const relativePath of [
  manifest?.decisionVerificationPath,
  manifest?.completionAuditPath,
  manifest?.completionSourceManifestPath,
  manifest?.privateVisualValidationManifestPath,
  manifest?.approvalAuthorityManifestPath,
  manifest?.publicCheckScript,
  manifest?.privateVerifierScript,
  manifest?.privateApprovalVerifierScript,
]) {
  if (!relativePath || relativePath.includes("..") || path.isAbsolute(relativePath)) {
    fail(`${manifestPath} contains an unsafe relative path ${relativePath}`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, relativePath))) fail(`missing ${relativePath}`);
}

const sourceManifest = readJson(manifest?.completionSourceManifestPath || "docs/ui/completion-source.manifest.json");
const visualManifest = readJson(manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json");
const approvalManifest = readJson(manifest?.approvalAuthorityManifestPath || "docs/ui/approval-authority.manifest.json");
const mechanicalManifest = readJson("docs/ui/mechanical-equivalence.manifest.json");
for (const envName of [
  sourceManifest?.privateGoalFileEnv,
  sourceManifest?.privateSourceSessionFileEnv,
  ...(Array.isArray(visualManifest?.requiredRoots) ? visualManifest.requiredRoots : []),
]) {
  if (!String(manifest?.finalVerificationCommand || "").includes(envName)) {
    fail(`${manifestPath}.finalVerificationCommand must include ${envName}`);
  }
}
const optionalRootAliases = requireArray(visualManifest, manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json", "optionalRootAliases");
const optionalRootsByEnv = new Map(optionalRootAliases.map((entry) => [entry?.env, entry]));
const conditionalRootContracts = requireArray(manifest, manifestPath, "conditionalPrivateRoots");
for (const contract of conditionalRootContracts) {
  requireConditionalRootContract({ rootsByEnv: optionalRootsByEnv, ...contract });
}
const conditionalRootsByCondition = new Map(conditionalRootContracts.map((entry) => [entry?.condition, entry]));
for (const [condition, expected] of [
  ["required-when-approval-records-exist", { env: "CLAWIX_UI_PRIVATE_APPROVAL_ROOT", manifestPath: manifest?.approvalAuthorityManifestPath }],
  ["required-when-mechanical-equivalence-records-exist", { env: "CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT", manifestPath: "docs/ui/mechanical-equivalence.manifest.json" }],
]) {
  const contract = conditionalRootsByCondition.get(condition);
  if (!contract) {
    fail(`${manifestPath}.conditionalPrivateRoots must include ${condition}`);
    continue;
  }
  for (const [field, value] of Object.entries(expected)) {
    if (contract[field] !== value) fail(`${manifestPath}.conditionalPrivateRoots ${condition} must set ${field}=${value}`);
  }
}
const activeApprovalRecords = approvalRecords(approvalManifest);
if (activeApprovalRecords.length > 0) {
  if (!String(manifest?.finalVerificationCommand || "").includes("CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
    fail(`${manifestPath}.finalVerificationCommand must include CLAWIX_UI_PRIVATE_APPROVAL_ROOT while approval records exist`);
  }
  if (!requireArray(visualManifest, manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json", "delegates").includes("node scripts/ui_private_approval_verify.mjs --require-approved")) {
    fail(`${manifest?.privateVisualValidationManifestPath}.delegates must include scripts/ui_private_approval_verify.mjs while approval records exist`);
  }
  if (!optionalRootAliases.some((entry) => entry?.alias === approvalManifest?.privateApprovalAlias && entry?.env === "CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
    fail(`${manifest?.privateVisualValidationManifestPath}.optionalRootAliases must expose CLAWIX_UI_PRIVATE_APPROVAL_ROOT for private approvals`);
  }
  const approvalResult = spawnSync(process.execPath, [path.join(rootDir, manifest.privateApprovalVerifierScript), "--require-approved"], {
    cwd: rootDir,
    env: withoutPrivateCompletionEnv(),
    encoding: "utf8",
  });
  const approvalOutput = `${approvalResult.stdout || ""}${approvalResult.stderr || ""}`;
  if (approvalResult.status !== manifest.externalPendingExitCode) {
    fail(`${manifest.privateApprovalVerifierScript} must exit ${manifest.externalPendingExitCode} while private approval evidence is missing`);
  }
  if (!approvalOutput.includes("CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
    fail(`${manifest.privateApprovalVerifierScript} must report CLAWIX_UI_PRIVATE_APPROVAL_ROOT when approval records exist`);
  }
}
const activeMechanicalRecords = mechanicalEquivalenceRecords(mechanicalManifest);
if (activeMechanicalRecords.length > 0 && !String(manifest?.finalVerificationCommand || "").includes("CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT")) {
  fail(`${manifestPath}.finalVerificationCommand must include CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT while mechanical equivalence records exist`);
}

const config = readJson("docs/ui/interface-governance.config.json");
const publicChecks = new Set(requireArray(config, "docs/ui/interface-governance.config.json", "publicChecks"));
if (!publicChecks.has("completion-final-gate-check")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include completion-final-gate-check");
}
for (const check of requireArray(manifest, manifestPath, "requiredPublicChecks")) {
  if (!publicChecks.has(check)) fail(`${manifestPath}.requiredPublicChecks includes undeclared check ${check}`);
}
if (!Array.isArray(manifest.publicPrerequisiteScripts) || !manifest.publicPrerequisiteScripts.includes("scripts/ui_release_gate_check.mjs")) {
  fail(`${manifestPath}.publicPrerequisiteScripts must include scripts/ui_release_gate_check.mjs`);
}
for (const [index, script] of (manifest.publicPrerequisiteScripts || []).entries()) {
  if (typeof script !== "string" || !script.startsWith("scripts/ui_") || !script.endsWith(".mjs")) {
    fail(`${manifestPath}.publicPrerequisiteScripts[${index}] must be a public UI script`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, script))) {
    fail(`${manifestPath}.publicPrerequisiteScripts[${index}] points to missing ${script}`);
  }
}

const privateVerifier = read(manifest?.privateVerifierScript || "scripts/ui_private_completion_verify.mjs");
for (const snippet of [
  "docs/ui/completion-gate.manifest.json",
  "scripts/ui_private_completion_source_verify.mjs",
  "scripts/ui_private_visual_verify.mjs",
  "publicPrerequisiteScripts",
  "--skip-public-prerequisites",
  "EXTERNAL PENDING",
  "process.exit(2)",
  "open decisions",
  "--simulate-no-open-decisions",
]) {
  if (!privateVerifier.includes(snippet)) {
    fail(`${manifest.privateVerifierScript} must include ${snippet}`);
  }
}

const decisionVerification = readJson(manifest?.decisionVerificationPath || "docs/ui/decision-verification.json");
const openDecisions = requireArray(decisionVerification, manifest?.decisionVerificationPath || "docs/ui/decision-verification.json", "decisions")
  .filter((decision) => decision?.status === "open");
if (openDecisions.length > 0) {
  const result = spawnSync(process.execPath, [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--skip-public-prerequisites"], {
    cwd: rootDir,
    env: withoutPrivateCompletionEnv(),
    encoding: "utf8",
  });
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  if (result.status !== manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must exit ${manifest.externalPendingExitCode} while decisions remain open`);
  }
  if (!output.includes("open decisions block update_goal")) {
    fail(`${manifest.privateVerifierScript} must report open decisions before asking for private roots`);
  }
  for (const decision of openDecisions) {
    if (!output.includes(decision.id)) {
      fail(`${manifest.privateVerifierScript} open-decision output must include ${decision.id}`);
    }
  }
}

const simulatedClosedResult = spawnSync(
  process.execPath,
  [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-no-open-decisions", "--skip-public-prerequisites"],
  {
    cwd: rootDir,
    env: withoutPrivateCompletionEnv(),
    encoding: "utf8",
  },
);
const simulatedClosedOutput = `${simulatedClosedResult.stdout || ""}${simulatedClosedResult.stderr || ""}`;
if (simulatedClosedResult.status !== manifest.externalPendingExitCode) {
  fail(`${manifest.privateVerifierScript} must exit ${manifest.externalPendingExitCode} when closed decisions still lack private sources`);
}
if (!simulatedClosedOutput.includes("CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE")) {
  fail(`${manifest.privateVerifierScript} must delegate to private completion source verification after decisions close`);
}
if (simulatedClosedOutput.includes("open decisions block update_goal")) {
  fail(`${manifest.privateVerifierScript} must not report open decisions during closed-decision simulation`);
}
withTemporaryCompletionSources(sourceManifest, (temporaryEnv) => {
  const result = spawnSync(
    process.execPath,
    [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-no-open-decisions", "--skip-public-prerequisites"],
    {
      cwd: rootDir,
      env: { ...withoutPrivateCompletionEnv(), ...temporaryEnv },
      encoding: "utf8",
    },
  );
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  if (result.status !== manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must exit ${manifest.externalPendingExitCode} after source verification when visual roots are missing`);
  }
  if (!output.includes("CLAWIX_UI_PRIVATE_BASELINE_ROOT")) {
    fail(`${manifest.privateVerifierScript} must advance to private visual root verification after private source verification passes`);
  }
  if (output.includes("CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE")) {
    fail(`${manifest.privateVerifierScript} must not keep blocking on private completion sources after source verification passes`);
  }
});

const gateSurface = readJson("docs/ui/gate-surface.manifest.json");
if (!requireArray(gateSurface, "docs/ui/gate-surface.manifest.json", "requiredPublicCheckScripts").includes(manifest?.publicCheckScript)) {
  fail("docs/ui/gate-surface.manifest.json.requiredPublicCheckScripts must include the completion gate check");
}
const gateCoverage = gateSurface?.publicCheckCoverage || {};
if (!Array.isArray(gateCoverage["completion-final-gate-check"]) || !gateCoverage["completion-final-gate-check"].includes(manifest?.publicCheckScript)) {
  fail("docs/ui/gate-surface.manifest.json.publicCheckCoverage must cover completion-final-gate-check");
}

if (errors.length > 0) {
  console.error("UI completion gate check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI completion gate check passed");
