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

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function requireSafePrivateReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

const registryPath = "docs/ui/visual-proposals.registry.json";
const registry = readJson(registryPath);
requireFields(registry, registryPath, [
  "schemaVersion",
  "status",
  "policy",
  "templatePath",
  "privateApprovalAlias",
  "approvalRequiredForStatuses",
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

const approvalAuthority = readJson("docs/ui/approval-authority.manifest.json");
if (registry?.privateApprovalAlias !== approvalAuthority?.privateApprovalAlias) {
  fail(`${registryPath}.privateApprovalAlias must match docs/ui/approval-authority.manifest.json.privateApprovalAlias`);
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const allowedMutationClasses = new Set(requireArray(config, configPath, "mutationClasses"));
const allowedChangeKinds = new Set(requireArray(config, configPath, "restrictedChangeKinds"));
const allowedPlatforms = new Set(requireArray(config, configPath, "platforms"));
const allowedStatuses = new Set(requireArray(registry, registryPath, "proposalStatuses"));
const approvalRequiredStatuses = new Set(requireArray(registry, registryPath, "approvalRequiredForStatuses"));
for (const status of ["conceptual-only", "user-approved-for-visual-lane", "rejected", "expired"]) {
  if (!allowedStatuses.has(status)) fail(`${registryPath}.proposalStatuses must include ${status}`);
}
if (!approvalRequiredStatuses.has("user-approved-for-visual-lane")) {
  fail(`${registryPath}.approvalRequiredForStatuses must include user-approved-for-visual-lane`);
}
for (const status of approvalRequiredStatuses) {
  if (!allowedStatuses.has(status)) fail(`${registryPath}.approvalRequiredForStatuses contains unknown status ${status}`);
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
  if (approvalRequiredStatuses.has(proposal.status)) {
    if (proposal.userApprovalStatus !== "approved") {
      fail(`${label}.userApprovalStatus must be approved for ${proposal.status}`);
    }
    requireSafePrivateReference(proposal.privateApprovalReference, registry.privateApprovalAlias, `${label}.privateApprovalReference`);
  }
  if (proposal.reviewAfter < today) fail(`${label}.reviewAfter expired on ${proposal.reviewAfter}`);
}

scanForLocalPaths(registry, registryPath);

if (errors.length > 0) {
  console.error("UI visual proposal check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual proposal check passed (${ids.size} proposals)`);
