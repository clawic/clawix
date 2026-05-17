#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  try {
    return JSON.parse(read(relativePath));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return {};
  }
}

function requireSnippet(relativePath, snippet) {
  const content = read(relativePath);
  if (!content.includes(snippet)) fail(`${relativePath} is missing ${JSON.stringify(snippet)}`);
}

const decisionsPath = "docs/v1-surface-closure-decisions.json";
const acceptancePath = "docs/v1-surface-closure-acceptance.json";
const auditPath = "docs/v1-surface-closure-completion-audit.md";
const decisions = readJson(decisionsPath);
const acceptance = readJson(acceptancePath);
const audit = read(auditPath);

const expectedIds = [
  "bridge_contract_v1",
  "bridge_version_field",
  "bridge_source_of_truth",
  "active_target_scope",
  "framework_store_ownership",
  "surface_parity_gate",
  "session_deep_link",
  "oauth_deep_link",
  "pairing_qr_contract",
  "registry_shape",
  "bridge_v1_frame_scope",
  "send_frame_name",
  "chat_session_vocabulary",
  "host_display_name",
  "client_kind_values",
  "client_identity_fields",
  "storage_bucket_policy",
  "apps_design_storage",
  "audio_dictation_storage",
  "agent_skill_storage_format",
  "project_identity_storage",
  "secrets_boundary",
  "local_models_storage",
  "agent_tools_policy",
  "quickask_prompts_storage",
  "provider_config_owner",
  "external_integrations_policy",
  "mcp_config_policy",
  "experimental_surface_policy",
  "domain_verticals_policy",
  "vertical_completion_depth",
  "migration_policy_no_users",
  "repo_scope",
  "missing_domain_contracts",
  "execution_batching",
  "experimental_correction",
  "external_pending_policy",
];
const expectedSourceQuestionIds = [
  "bridge_contract_v1",
  "bridge_version_field",
  "bridge_source_of_truth",
  "bridge_target_scope",
  "framework_store_ownership",
  "surface_parity_gate",
  "deep_link_shape",
  "oauth_deeplink_shape",
  "pairing_qr_contract",
  "surface_registry_shape",
  "bridge_v1_frame_scope",
  "bridge_send_frame_name",
  "bridge_chat_vocabulary",
  "mac_name_field",
  "client_kind_values",
  "client_identity_fields",
  "apps_design_storage",
  "storage_bucket_policy",
  "apps_design_contract_status",
  "audio_dictation_storage",
  "agent_skill_storage_format",
  "project_identity_storage",
  "secrets_storage_boundary",
  "local_models_storage",
  "host_action_policy_storage",
  "quickask_prompts_storage",
  "provider_config_owner",
  "external_integrations_policy",
  "mcp_config_policy",
  "experimental_surface_policy",
  "domain_verticals_policy",
  "vertical_completion_depth",
  "agent_tools_policy",
  "migration_policy_no_users",
  "repo_scope",
  "missing_domain_contracts",
  "execution_batching",
];
const expectedAcceptanceCategoryIds = [
  "bridge-swift",
  "bridge-android",
  "bridge-windows",
  "deep-links",
  "pairing",
  "storage-boundary",
  "provider-routing",
  "mcp-registry",
  "integrations-qa",
  "domain-resource-fixtures",
  "docs-alignment",
  "source-size",
  "public-hygiene",
  "external-pending-policy",
];

if (decisions.schemaVersion !== 1) fail(`${decisionsPath}.schemaVersion must be 1`);
if (decisions.program !== "v1-surface-closure") fail(`${decisionsPath}.program must be v1-surface-closure`);
if (decisions.sourceSessionRef !== "private-session-not-published") fail(`${decisionsPath} must not publish the private source session path`);
if (decisions.decisionCount !== expectedIds.length) fail(`${decisionsPath}.decisionCount must be ${expectedIds.length}`);
if (!Array.isArray(decisions.decisions)) fail(`${decisionsPath}.decisions must be an array`);
if (decisions.sourceExtraction?.requestUserInputPrompts !== 39) fail(`${decisionsPath}.sourceExtraction.requestUserInputPrompts must be 39`);
if (decisions.sourceExtraction?.bindingAnswers !== expectedSourceQuestionIds.length) fail(`${decisionsPath}.sourceExtraction.bindingAnswers must be ${expectedSourceQuestionIds.length}`);
const excludedPromptIds = (decisions.sourceExtraction?.excludedPrompts ?? []).map((prompt) => prompt.id);
for (const excludedId of ["bridge_manifest_source", "bridge_version_field"]) {
  if (!excludedPromptIds.includes(excludedId)) fail(`${decisionsPath}.sourceExtraction.excludedPrompts is missing ${excludedId}`);
}
const sourceQuestionIds = decisions.sourceExtraction?.bindingSourceQuestionIds ?? [];
for (const sourceId of expectedSourceQuestionIds) {
  if (!sourceQuestionIds.includes(sourceId)) fail(`${decisionsPath}.sourceExtraction.bindingSourceQuestionIds is missing ${sourceId}`);
}
if (sourceQuestionIds.length !== expectedSourceQuestionIds.length) {
  fail(`${decisionsPath}.sourceExtraction.bindingSourceQuestionIds must contain exactly ${expectedSourceQuestionIds.length} ids`);
}

if (acceptance.schemaVersion !== 1) fail(`${acceptancePath}.schemaVersion must be 1`);
if (acceptance.program !== "v1-surface-closure") fail(`${acceptancePath}.program must be v1-surface-closure`);
const acceptanceCategories = acceptance.requiredCategories ?? [];
if (!Array.isArray(acceptanceCategories)) fail(`${acceptancePath}.requiredCategories must be an array`);
const actualAcceptanceIds = acceptanceCategories.map((category) => category.id);
for (const expectedId of expectedAcceptanceCategoryIds) {
  if (!actualAcceptanceIds.includes(expectedId)) fail(`${acceptancePath} is missing acceptance category ${expectedId}`);
  if (!audit.includes(`\`${expectedId}\``)) fail(`${auditPath} is missing acceptance category ${expectedId}`);
}
if (actualAcceptanceIds.length !== expectedAcceptanceCategoryIds.length) {
  fail(`${acceptancePath} must contain exactly ${expectedAcceptanceCategoryIds.length} acceptance categories`);
}
for (const category of acceptanceCategories) {
  const label = `${acceptancePath}.requiredCategories.${category?.id ?? "<missing-id>"}`;
  if (!expectedAcceptanceCategoryIds.includes(category.id)) fail(`${label} is unexpected`);
  if (!["verified", "external-pending"].includes(category.status)) fail(`${label}.status must be verified or external-pending`);
  if (!Array.isArray(category.decisionIds) || category.decisionIds.length === 0) fail(`${label}.decisionIds must be a non-empty array`);
  if (!Array.isArray(category.evidence) || category.evidence.length === 0) fail(`${label}.evidence must be a non-empty array`);
  if (!Array.isArray(category.validationCommands) || category.validationCommands.length === 0) {
    fail(`${label}.validationCommands must be a non-empty array`);
  }
  for (const decisionId of category.decisionIds ?? []) {
    if (!expectedIds.includes(decisionId)) fail(`${label}.decisionIds contains unknown decision ${decisionId}`);
  }
  if (category.status === "external-pending" && (!Array.isArray(category.externalPending) || category.externalPending.length === 0)) {
    fail(`${label}.externalPending must explain the external dependency`);
  }
}
const acceptanceText = read(acceptancePath);
if (/\/Users\//.test(acceptanceText) || /rollout-\d{4}-\d{2}-\d{2}T/.test(acceptanceText)) {
  fail(`${acceptancePath} must not include private local session paths`);
}

const actualIds = (decisions.decisions ?? []).map((decision) => decision.id);
for (const expectedId of expectedIds) {
  if (!actualIds.includes(expectedId)) fail(`${decisionsPath} is missing decision ${expectedId}`);
  if (!audit.includes(`\`${expectedId}\``)) fail(`${auditPath} is missing decision ${expectedId}`);
}
if (actualIds.length !== expectedIds.length) fail(`${decisionsPath} must contain exactly ${expectedIds.length} decisions`);
for (const id of actualIds) {
  if (!expectedIds.includes(id)) fail(`${decisionsPath} contains unexpected decision ${id}`);
}

if (!audit.includes("39 `request_user_input` prompts")) fail(`${auditPath} must record the source prompt count`);
if (!audit.includes("37 binding answers")) fail(`${auditPath} must record the binding answer count`);
if (!audit.includes("2 excluded prompts")) fail(`${auditPath} must record excluded source prompts`);
if (!audit.includes("Acceptance validation matrix")) fail(`${auditPath} must mention the acceptance validation matrix`);
for (const sourceSnippet of ["`bridge_manifest_source`", "`apps_design_storage`", "`apps_design_contract_status`"]) {
  if (!audit.includes(sourceSnippet)) fail(`${auditPath} must mention source extraction snippet ${sourceSnippet}`);
}
if (!audit.includes("private session, not published")) fail(`${auditPath} must not publish the private source session path`);
if (/\/Users\//.test(audit) || /rollout-\d{4}-\d{2}-\d{2}T/.test(audit)) {
  fail(`${auditPath} must not include private local session paths`);
}

const rows = audit.split("\n").filter((line) => /^\| \d+ \|/.test(line));
if (rows.length !== expectedIds.length) fail(`${auditPath} must have one row per decision`);
for (const row of rows) {
  if (!/\| (verified|external-pending) \|/.test(row)) fail(`${auditPath} row has invalid status: ${row}`);
}

for (const snippet of [
  "Bridge v1",
  "clawix://session/<sessionId>",
  "clawix://auth/callback/<provider>",
  "JSON payload with `v`, `host`, `port`, `token`, `shortCode`, `hostDisplayName`",
  "Browser tool",
  "Screen tools",
  "Mac Utilities",
  "Git workflow",
  "Remote Mesh",
  "OpenCode/runtime adapters",
  "Simulators",
  "Calendar",
  "Contacts",
  "Life verticals",
]) {
  requireSnippet("docs/interface-matrix.md", snippet);
}

for (const snippet of [
  "\\\"schemaVersion\\\":5",
  "\\\"schemaVersion\\\":8",
  "sendPrompt",
  "macName",
  "clawix://chat",
  "clawix://oauth-callback",
]) {
  requireSnippet("scripts/interface_surface_guard.mjs", snippet);
}

if (errors.length > 0) {
  console.error("V1 surface closure audit check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`V1 surface closure audit check passed (${expectedIds.length} decisions)`);
