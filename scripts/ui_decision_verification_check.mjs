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

function isPublicEvidenceReference(reference) {
  if (typeof reference !== "string" || reference.length === 0) return false;
  if (path.isAbsolute(reference)) return false;
  if (reference.startsWith("~/") || reference.includes("/Users/")) return false;
  if (reference.startsWith("private-") || reference.includes(":")) return false;
  return true;
}

const decisionPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionPath);
requireFields(decisionVerification, decisionPath, [
  "schemaVersion",
  "conversationId",
  "goalReference",
  "sourceSession",
  "completionRule",
  "statuses",
  "decisions",
]);

if (decisionVerification?.conversationId !== "019e2b5e-fe48-7231-8e13-49411999b001") {
  fail(`${decisionPath}.conversationId must stay pinned to the source conversation`);
}
if (!String(decisionVerification?.goalReference || "").startsWith("private-codex-goal:")) {
  fail(`${decisionPath}.goalReference must be a public-safe private goal alias`);
}
if (!String(decisionVerification?.sourceSession || "").startsWith("private-codex-session:")) {
  fail(`${decisionPath}.sourceSession must be a public-safe private session alias`);
}
if (!String(decisionVerification?.completionRule || "").includes("re-read")) {
  fail(`${decisionPath}.completionRule must require re-reading the private source before completion`);
}

const allowedStatuses = new Set(requireArray(decisionVerification, decisionPath, "statuses"));
for (const status of ["open", "verified-complete"]) {
  if (!allowedStatuses.has(status)) fail(`${decisionPath}.statuses must include ${status}`);
}

const decisions = requireArray(decisionVerification, decisionPath, "decisions");
if (decisions.length !== 39) fail(`${decisionPath}.decisions must contain 39 records`);
const ids = new Set();
for (const [index, decision] of decisions.entries()) {
  const label = `${decisionPath}.decisions[${index}]`;
  requireFields(decision, label, ["index", "id", "choice", "status", "publicEvidence", "remaining"]);
  if (!decision) continue;
  if (decision.index !== index + 1) fail(`${label}.index must be ${index + 1}`);
  if (ids.has(decision.id)) fail(`${label}.id duplicates ${decision.id}`);
  ids.add(decision.id);
  if (!allowedStatuses.has(decision.status)) fail(`${label}.status is not allowed`);
  if (decision.status === "verified-complete" && decision.remaining.length > 0) {
    fail(`${label} cannot be verified-complete while remaining work is listed`);
  }
  for (const [evidenceIndex, evidence] of requireArray(decision, label, "publicEvidence").entries()) {
    const evidenceLabel = `${label}.publicEvidence[${evidenceIndex}]`;
    if (!isPublicEvidenceReference(evidence)) {
      fail(`${evidenceLabel} must be a public-safe repo-relative reference`);
      continue;
    }
    const target = evidence.split("#", 1)[0];
    if (!fs.existsSync(path.join(rootDir, target))) {
      fail(`${evidenceLabel} points to missing target ${target}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI decision verification check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI decision verification check passed (${decisions.length} decisions)`);
