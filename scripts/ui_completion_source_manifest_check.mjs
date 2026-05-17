#!/usr/bin/env node
import fs from "node:fs";
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
  if (/rollout-2026-05-15T13-21-46/.test(value)) {
    fail(`${label} must use the public-safe source session alias, not the private filename`);
  }
}

const manifestPath = "docs/ui/completion-source.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "goalReferenceAlias",
  "sourceSessionAlias",
  "privateGoalFileEnv",
  "privateSourceSessionFileEnv",
  "verificationCommand",
  "expectedConversationId",
  "expectedDecisionCount",
  "sourceSessionRequirements",
  "expectedDecisionIds",
  "expectedDecisions",
  "externalPendingExitCode",
]);
scanPublicSafety(manifest, manifestPath);

if (manifest?.goalReferenceAlias !== "private-codex-goal:clawix-interface-governance-plan-2026-05-15.md") {
  fail(`${manifestPath}.goalReferenceAlias must match the private goal alias`);
}
if (manifest?.sourceSessionAlias !== "private-codex-session:019e2b5e-fe48-7231-8e13-49411999b001") {
  fail(`${manifestPath}.sourceSessionAlias must match the private source session alias`);
}
if (manifest?.privateGoalFileEnv !== "CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE") {
  fail(`${manifestPath}.privateGoalFileEnv must be CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE`);
}
if (manifest?.privateSourceSessionFileEnv !== "CLAWIX_UI_PRIVATE_COMPLETION_SOURCE_SESSION_FILE") {
  fail(`${manifestPath}.privateSourceSessionFileEnv must be CLAWIX_UI_PRIVATE_COMPLETION_SOURCE_SESSION_FILE`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_completion_source_verify.mjs --require-approved")) {
  fail(`${manifestPath}.verificationCommand must require the private completion source verifier`);
}
for (const envName of [manifest?.privateGoalFileEnv, manifest?.privateSourceSessionFileEnv]) {
  if (!String(manifest?.verificationCommand || "").includes(envName)) {
    fail(`${manifestPath}.verificationCommand must include ${envName}`);
  }
}
if (manifest?.externalPendingExitCode !== 2) fail(`${manifestPath}.externalPendingExitCode must be 2`);
if (manifest?.expectedDecisionCount !== 39) fail(`${manifestPath}.expectedDecisionCount must be 39`);
requireFields(manifest?.sourceSessionRequirements, `${manifestPath}.sourceSessionRequirements`, [
  "sessionMetaIdMatchesConversation",
  "decisionsBeforeFirstGoalEvent",
  "minimumUserMessages",
  "requiredRecordTypes",
]);
if (manifest?.sourceSessionRequirements?.sessionMetaIdMatchesConversation !== true) {
  fail(`${manifestPath}.sourceSessionRequirements.sessionMetaIdMatchesConversation must be true`);
}
if (manifest?.sourceSessionRequirements?.decisionsBeforeFirstGoalEvent !== true) {
  fail(`${manifestPath}.sourceSessionRequirements.decisionsBeforeFirstGoalEvent must be true`);
}
if (!Number.isInteger(manifest?.sourceSessionRequirements?.minimumUserMessages) || manifest.sourceSessionRequirements.minimumUserMessages < 1) {
  fail(`${manifestPath}.sourceSessionRequirements.minimumUserMessages must be a positive integer`);
}
const requiredRecordTypes = requireArray(manifest?.sourceSessionRequirements, `${manifestPath}.sourceSessionRequirements`, "requiredRecordTypes");
for (const recordType of ["session_meta", "event_msg:user_message", "response_item:message", "event_msg:thread_goal_updated"]) {
  if (!requiredRecordTypes.includes(recordType)) {
    fail(`${manifestPath}.sourceSessionRequirements.requiredRecordTypes must include ${recordType}`);
  }
}

const decisionVerification = readJson("docs/ui/decision-verification.json");
if (manifest?.expectedConversationId !== decisionVerification?.conversationId) {
  fail(`${manifestPath}.expectedConversationId must match docs/ui/decision-verification.json.conversationId`);
}
if (decisionVerification?.goalReference !== manifest?.goalReferenceAlias) {
  fail(`${manifestPath}.goalReferenceAlias must match docs/ui/decision-verification.json.goalReference`);
}
if (decisionVerification?.sourceSession !== manifest?.sourceSessionAlias) {
  fail(`${manifestPath}.sourceSessionAlias must match docs/ui/decision-verification.json.sourceSession`);
}
const decisions = requireArray(decisionVerification, "docs/ui/decision-verification.json", "decisions");
const expectedDecisionIds = requireArray(manifest, manifestPath, "expectedDecisionIds");
const expectedDecisions = requireArray(manifest, manifestPath, "expectedDecisions");
if (expectedDecisionIds.length !== manifest?.expectedDecisionCount) {
  fail(`${manifestPath}.expectedDecisionIds must contain expectedDecisionCount entries`);
}
if (expectedDecisions.length !== manifest?.expectedDecisionCount) {
  fail(`${manifestPath}.expectedDecisions must contain expectedDecisionCount entries`);
}
if (expectedDecisionIds.length !== decisions.length) {
  fail(`${manifestPath}.expectedDecisionIds must mirror docs/ui/decision-verification.json decisions`);
}
if (expectedDecisions.length !== decisions.length) {
  fail(`${manifestPath}.expectedDecisions must mirror docs/ui/decision-verification.json decisions`);
}
for (const [index, decision] of decisions.entries()) {
  if (expectedDecisionIds[index] !== decision?.id) {
    fail(`${manifestPath}.expectedDecisionIds[${index}] must be ${decision?.id}`);
  }
  const expectedDecision = expectedDecisions[index];
  if (expectedDecision?.id !== decision?.id) {
    fail(`${manifestPath}.expectedDecisions[${index}].id must be ${decision?.id}`);
  }
  if (expectedDecision?.choice !== decision?.choice) {
    fail(`${manifestPath}.expectedDecisions[${index}].choice must be ${decision?.choice}`);
  }
}

const completionAudit = read("docs/ui/completion-audit.md");
for (const snippet of [
  manifest?.goalReferenceAlias,
  manifest?.sourceSessionAlias,
  "private session, not published",
  "Do not call update_goal",
]) {
  if (!completionAudit.includes(snippet)) fail(`docs/ui/completion-audit.md must include ${snippet}`);
}

const privateVerifier = read("scripts/ui_private_completion_source_verify.mjs");
for (const snippet of [
  "docs/ui/completion-source.manifest.json",
  "EXTERNAL PENDING",
  "process.exit(2)",
  "expectedDecisionIds",
  "expectedDecisions",
  "expectedConversationId",
  "sourceSessionRequirements",
  "session_meta",
  "event_msg:user_message",
  "thread_goal_",
  "decisionsBeforeFirstGoalEvent",
  "decision.choice",
  "normalizeText",
  "parseJsonlRecords",
  "recordTypeKey",
  "sourceBeforeFirstGoalEvent",
]) {
  if (!privateVerifier.includes(snippet)) {
    fail(`scripts/ui_private_completion_source_verify.mjs must include ${snippet}`);
  }
}

if (errors.length > 0) {
  console.error("UI completion source manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI completion source manifest check passed (${expectedDecisionIds.length} decisions)`);
