#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

function fail(message) {
  errors.push(message);
}

function hasFlag(name) {
  return args.includes(name);
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function normalizeText(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

function assertPrivateFile(file, envName) {
  const resolved = path.resolve(file);
  const relativeToRepo = path.relative(rootDir, resolved);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    fail(`${envName} must point outside the public repository`);
  }
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    fail(`${envName} does not point to an existing file`);
    return null;
  }
  return resolved;
}

function countJsonlRecords(file) {
  return fs.readFileSync(file, "utf8").split("\n").filter((line) => line.trim() !== "").length;
}

function parseJsonlRecords(file, label) {
  const records = [];
  const lines = fs.readFileSync(file, "utf8").split("\n");
  for (const [index, line] of lines.entries()) {
    if (line.trim() === "") continue;
    try {
      records.push(JSON.parse(line));
    } catch (error) {
      fail(`${label} line ${index + 1} is not valid JSON: ${error.message}`);
    }
  }
  return records;
}

function recordTypeKey(record) {
  return record?.payload?.type ? `${record.type}:${record.payload.type}` : String(record?.type || "");
}

function recordText(record) {
  return JSON.stringify(record || "");
}

function sourceBeforeFirstGoalEvent(records) {
  const firstGoalEventIndex = records.findIndex((record) => recordTypeKey(record).startsWith("event_msg:thread_goal_"));
  const sourceRecords = firstGoalEventIndex >= 0 ? records.slice(0, firstGoalEventIndex) : records;
  return sourceRecords.map(recordText).join("\n");
}

if (!hasFlag("--require-approved")) {
  console.error("UI private completion source verification requires --require-approved.");
  process.exit(1);
}

const manifest = readJson("docs/ui/completion-source.manifest.json");
const goalEnv = manifest.privateGoalFileEnv;
const sessionEnv = manifest.privateSourceSessionFileEnv;
const missingEnv = [goalEnv, sessionEnv].filter((envName) => !process.env[envName]);
if (missingEnv.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingEnv.join(", ")} to verify private completion sources.`);
  process.exit(2);
}

const goalFile = assertPrivateFile(process.env[goalEnv], goalEnv);
const sessionFile = assertPrivateFile(process.env[sessionEnv], sessionEnv);
const goalSource = goalFile ? fs.readFileSync(goalFile, "utf8") : "";
const sessionSource = sessionFile ? fs.readFileSync(sessionFile, "utf8") : "";
const sessionRecords = sessionFile ? parseJsonlRecords(sessionFile, sessionEnv) : [];
const normalizedGoalSource = normalizeText(goalSource);
const normalizedSessionSource = normalizeText(sessionSource);
const normalizedPreGoalSessionSource = normalizeText(sourceBeforeFirstGoalEvent(sessionRecords));
const decisionVerification = readJson("docs/ui/decision-verification.json");
const decisionsById = new Map((decisionVerification.decisions || []).map((decision) => [decision.id, decision]));
const expectedDecisions = manifest.expectedDecisions || (manifest.expectedDecisionIds || []).map((id) => ({ id }));
const sourceSessionRequirements = manifest.sourceSessionRequirements || {};

for (const snippet of [
  manifest.expectedConversationId,
  "Required Decision Verification Checklist",
  "Do not mark the associated goal complete",
  "update_goal(status:",
]) {
  if (!goalSource.includes(snippet)) fail(`${goalEnv} must include ${snippet}`);
}
if (!sessionSource.includes(manifest.expectedConversationId)) {
  fail(`${sessionEnv} must include the expected conversation id`);
}
if (sessionFile && countJsonlRecords(sessionFile) < manifest.expectedDecisionCount) {
  fail(`${sessionEnv} must contain enough JSONL records to cover the source conversation`);
}
if (sourceSessionRequirements.sessionMetaIdMatchesConversation) {
  const sessionMeta = sessionRecords.find((record) => record?.type === "session_meta");
  if (!sessionMeta) {
    fail(`${sessionEnv} must contain a session_meta record`);
  } else if (sessionMeta.payload?.id !== manifest.expectedConversationId) {
    fail(`${sessionEnv} session_meta id must match the expected conversation id`);
  }
}
const userMessageCount = sessionRecords.filter((record) => recordTypeKey(record) === "event_msg:user_message").length;
if (userMessageCount < Number(sourceSessionRequirements.minimumUserMessages || 0)) {
  fail(`${sessionEnv} must contain at least ${sourceSessionRequirements.minimumUserMessages} user message records`);
}
for (const recordType of sourceSessionRequirements.requiredRecordTypes || []) {
  if (!sessionRecords.some((record) => recordTypeKey(record) === recordType)) {
    fail(`${sessionEnv} must contain record type ${recordType}`);
  }
}

for (const expectedDecision of expectedDecisions) {
  const decisionId = expectedDecision.id;
  const decision = decisionsById.get(decisionId);
  if (!goalSource.includes(`\`${decisionId}\``)) {
    fail(`${goalEnv} must include decision ${decisionId}`);
  }
  if (!sessionSource.includes(decisionId)) {
    fail(`${sessionEnv} must include decision ${decisionId}`);
  }
  if (expectedDecision.choice && decision?.choice !== expectedDecision.choice) {
    fail(`docs/ui/decision-verification.json choice for ${decisionId} must be ${expectedDecision.choice}`);
  }
  if (!decision?.choice) {
    fail(`docs/ui/decision-verification.json must include a choice for ${decisionId}`);
    continue;
  }
  const normalizedChoice = normalizeText(decision.choice);
  if (!normalizedGoalSource.includes(normalizedChoice)) {
    fail(`${goalEnv} must include choice ${decision.choice} for decision ${decisionId}`);
  }
  if (!normalizedSessionSource.includes(normalizedChoice)) {
    fail(`${sessionEnv} must include choice ${decision.choice} for decision ${decisionId}`);
  }
  if (sourceSessionRequirements.decisionsBeforeFirstGoalEvent) {
    if (!normalizedPreGoalSessionSource.includes(decisionId)) {
      fail(`${sessionEnv} must include decision ${decisionId} before the first thread goal event`);
    }
    if (!normalizedPreGoalSessionSource.includes(normalizedChoice)) {
      fail(`${sessionEnv} must include choice ${decision.choice} before the first thread goal event`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI private completion source verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private completion source verification passed (${expectedDecisions.length} decisions)`);
