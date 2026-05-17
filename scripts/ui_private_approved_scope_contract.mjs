import fs from "node:fs";
import path from "node:path";

function readJson(rootDir, relativePath, fail) {
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

function splitReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) return null;
  if (reference.includes("/Users/") || reference.startsWith("file://")) return null;
  return { alias, suffix };
}

function isIsoTimestamp(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) && !Number.isNaN(Date.parse(value));
}

export function loadApprovedScopeContract(rootDir, fail) {
  const validation = readJson(rootDir, "docs/ui/private-visual-validation.manifest.json", fail);
  const approval = readJson(rootDir, "docs/ui/approval-authority.manifest.json", fail);
  return {
    requiredFields: Array.isArray(validation?.requiredApprovedScopeFields)
      ? validation.requiredApprovedScopeFields
      : ["scopeId", "approvedBy", "approvedAt", "privateApprovalReference"],
    privateApprovalAlias: approval?.privateApprovalAlias || "private-codex-ui-approval",
  };
}

export function assertApprovedScopeMetadata(value, label, contract, fail) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object with approved user scope metadata`);
    return;
  }
  for (const field of contract.requiredFields || []) {
    if (value[field] === undefined || value[field] === null || value[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
  if (value.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  if (!isIsoTimestamp(value.approvedAt)) fail(`${label}.approvedAt must be an ISO date or timestamp`);
  const approvalReference = splitReference(value.privateApprovalReference);
  if (!approvalReference || approvalReference.alias !== contract.privateApprovalAlias) {
    fail(`${label}.privateApprovalReference must use ${contract.privateApprovalAlias}:`);
  }
  if (typeof value.scopeId !== "string" || value.scopeId === "") {
    fail(`${label}.scopeId must be a non-empty string`);
  }
}
