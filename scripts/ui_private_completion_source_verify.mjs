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

for (const decisionId of manifest.expectedDecisionIds || []) {
  if (!goalSource.includes(`\`${decisionId}\``)) {
    fail(`${goalEnv} must include decision ${decisionId}`);
  }
  if (!sessionSource.includes(decisionId)) {
    fail(`${sessionEnv} must include decision ${decisionId}`);
  }
}

if (errors.length > 0) {
  console.error("UI private completion source verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private completion source verification passed (${manifest.expectedDecisionIds.length} decisions)`);
