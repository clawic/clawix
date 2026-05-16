#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const errors = [];

function fail(message) {
  errors.push(message);
}

function readText(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const text = readText(relativePath);
  if (!text) return null;
  try {
    return JSON.parse(text);
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

const registryPath = "docs/ui/visual-proposals.registry.json";
const registry = readJson(registryPath);
requireFields(registry, registryPath, [
  "schemaVersion",
  "status",
  "policy",
  "templatePath",
  "proposalStatuses",
  "requiredProposalFields",
  "proposals",
]);
if (registry?.status !== "active") fail(`${registryPath}.status must be active`);
if (registry?.templatePath !== "docs/ui/visual-change-proposal.template.md") {
  fail(`${registryPath}.templatePath must point to docs/ui/visual-change-proposal.template.md`);
}

const template = readText(registry?.templatePath || "docs/ui/visual-change-proposal.template.md");
for (const snippet of ["Status: conceptual-only", "A proposal does not approve implementation", "User approval needed before implementation"]) {
  if (!template.includes(snippet)) fail(`${registry?.templatePath} is missing required snippet: ${snippet}`);
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const allowedMutationClasses = new Set(requireArray(config, configPath, "mutationClasses"));
const allowedChangeKinds = new Set(requireArray(config, configPath, "restrictedChangeKinds"));
const allowedPlatforms = new Set(requireArray(config, configPath, "platforms"));
const allowedStatuses = new Set(requireArray(registry, registryPath, "proposalStatuses"));
for (const status of ["conceptual-only", "user-approved-for-visual-lane", "rejected", "expired"]) {
  if (!allowedStatuses.has(status)) fail(`${registryPath}.proposalStatuses must include ${status}`);
}

const requiredFields = requireArray(registry, registryPath, "requiredProposalFields");
for (const field of ["id", "status", "requestedBy", "mutationClass", "changeKinds", "surfaces", "platforms", "proposalReference", "userApprovalStatus", "implementationStatus", "reviewAfter"]) {
  if (!requiredFields.includes(field)) fail(`${registryPath}.requiredProposalFields must include ${field}`);
}

const ids = new Set();
for (const [index, proposal] of requireArray(registry, registryPath, "proposals", { nonEmpty: false }).entries()) {
  const label = `${registryPath}.proposals[${index}]`;
  requireFields(proposal, label, requiredFields);
  if (ids.has(proposal.id)) fail(`${label}.id duplicates ${proposal.id}`);
  ids.add(proposal.id);
  if (!allowedStatuses.has(proposal.status)) fail(`${label}.status is not allowed`);
  if (!allowedMutationClasses.has(proposal.mutationClass)) fail(`${label}.mutationClass is not allowed`);
  for (const kind of requireArray(proposal, label, "changeKinds")) {
    if (!allowedChangeKinds.has(kind)) fail(`${label}.changeKinds contains ${kind}`);
  }
  for (const platform of requireArray(proposal, label, "platforms")) {
    if (!allowedPlatforms.has(platform)) fail(`${label}.platforms contains ${platform}`);
  }
  if (proposal.status === "conceptual-only" && proposal.implementationStatus !== "not-approved") {
    fail(`${label}.implementationStatus must be not-approved while conceptual-only`);
  }
  if (proposal.status !== "user-approved-for-visual-lane" && proposal.userApprovalStatus === "approved") {
    fail(`${label}.userApprovalStatus cannot be approved unless status is user-approved-for-visual-lane`);
  }
  if (proposal.reviewAfter < today) fail(`${label}.reviewAfter expired on ${proposal.reviewAfter}`);
}

if (errors.length > 0) {
  console.error("UI visual proposal check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual proposal check passed (${ids.size} proposals)`);
