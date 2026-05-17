#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const simulateUnauthorizedVisualDiff = process.argv.includes("--simulate-unauthorized-visual-diff");
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

function requireFields(object, relativePath, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${relativePath} is missing ${field}`);
    }
  }
}

function requireArray(object, relativePath, field, { nonEmpty = true } = {}) {
  if (!object) return [];
  const value = object[field];
  if (!Array.isArray(value)) {
    fail(`${relativePath}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${relativePath}.${field} must not be empty`);
  }
  return value;
}

function git(args) {
  try {
    return execFileSync("git", ["-C", rootDir, ...args], { encoding: "utf8" });
  } catch {
    return "";
  }
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
requireFields(config, configPath, [
  "schemaVersion",
  "status",
  "platforms",
  "visualAuthorizationPolicy",
  "mutationClasses",
  "restrictedChangeKinds",
  "requiredInteractiveStates",
]);

const requiredPlatforms = ["macos", "ios", "android", "web"];
const platforms = new Set(requireArray(config, configPath, "platforms"));
for (const platform of requiredPlatforms) {
  if (!platforms.has(platform)) fail(`${configPath}.platforms must include ${platform}`);
}

const visualAuthorization = config?.visualAuthorizationPolicy || {};
requireFields(visualAuthorization, `${configPath}.visualAuthorizationPolicy`, [
  "mode",
  "privateAssignment",
  "publicSignalEnv",
  "publicSignalValue",
]);
if (visualAuthorization.mode !== "private-allowlist") {
  fail(`${configPath}.visualAuthorizationPolicy.mode must be private-allowlist`);
}
if (visualAuthorization.privateAssignment !== "outside-public-repo") {
  fail(`${configPath}.visualAuthorizationPolicy.privateAssignment must stay outside-public-repo`);
}

const visualModelAllowlistPath = "docs/ui/visual-model-allowlist.manifest.json";
const visualModelAllowlist = readJson(visualModelAllowlistPath);
requireFields(visualModelAllowlist, visualModelAllowlistPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateAssignment",
  "authorizationSignal",
  "modelSignal",
  "proposalPath",
  "allowedVisualModels",
]);
if (visualModelAllowlist?.privateAssignment !== "outside-public-repo") {
  fail(`${visualModelAllowlistPath}.privateAssignment must stay outside-public-repo`);
}
if (visualModelAllowlist?.authorizationSignal?.env !== visualAuthorization.publicSignalEnv) {
  fail(`${visualModelAllowlistPath}.authorizationSignal.env must match ${configPath}.visualAuthorizationPolicy.publicSignalEnv`);
}
if (visualModelAllowlist?.authorizationSignal?.value !== visualAuthorization.publicSignalValue) {
  fail(`${visualModelAllowlistPath}.authorizationSignal.value must match ${configPath}.visualAuthorizationPolicy.publicSignalValue`);
}
const activeVisualModelIds = new Set(
  requireArray(visualModelAllowlist, visualModelAllowlistPath, "allowedVisualModels")
    .filter((model) => model?.status === "active")
    .map((model) => model.id),
);
if (!activeVisualModelIds.has("claude-opus-4.7")) {
  fail(`${visualModelAllowlistPath}.allowedVisualModels must include active claude-opus-4.7`);
}

const requiredStates = [
  "idle",
  "hover-or-highlight",
  "focused",
  "pressed",
  "disabled",
  "selected",
  "busy",
  "error",
];
const configuredStates = new Set(requireArray(config, configPath, "requiredInteractiveStates"));
for (const state of requiredStates) {
  if (!configuredStates.has(state)) fail(`${configPath}.requiredInteractiveStates must include ${state}`);
}

const componentExtractionPath = "docs/ui/component-extraction.manifest.json";
const componentExtraction = readJson(componentExtractionPath);
requireFields(componentExtraction, componentExtractionPath, [
  "schemaVersion",
  "status",
  "policy",
  "minimumCallSites",
  "requiredRiskSignals",
  "allowedPolicies",
  "allowedApis",
]);
const allowedExtractionApis = new Set(
  requireArray(componentExtraction, componentExtractionPath, "allowedApis").map((api) => api?.id).filter(Boolean),
);
const extractionPolicyApis = new Map();
for (const policy of requireArray(componentExtraction, componentExtractionPath, "allowedPolicies")) {
  if (!policy?.id) continue;
  extractionPolicyApis.set(policy.id, new Set(Array.isArray(policy.allowedApis) ? policy.allowedApis : []));
}

const indexPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(indexPath);
requireFields(registry, indexPath, ["schemaVersion", "platforms", "notesPath", "patterns"]);
const registryPatterns = requireArray(registry, indexPath, "patterns");
const registryPlatforms = new Set(requireArray(registry, indexPath, "platforms"));
for (const platform of requiredPlatforms) {
  if (!registryPlatforms.has(platform)) fail(`${indexPath}.platforms must include ${platform}`);
}

const notesPath = registry?.notesPath || "";
const notesAbsolutePath = path.join(rootDir, notesPath);
const patternNotes = fs.existsSync(notesAbsolutePath) ? fs.readFileSync(notesAbsolutePath, "utf8") : "";
if (!patternNotes) fail(`${indexPath}.notesPath must point to a Markdown notes file`);

for (const patternId of registryPatterns) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  requireFields(pattern, patternPath, [
    "schemaVersion",
    "id",
    "status",
    "platforms",
    "mutationClass",
    "canonicalReferences",
    "states",
    "geometry",
    "copy",
    "componentExtraction",
    "validation",
  ]);
  if (!pattern) continue;
  if (pattern.id !== patternId) fail(`${patternPath}.id must be ${patternId}`);
  const states = new Set(requireArray(pattern, patternPath, "states"));
  for (const state of requiredStates) {
    if (!states.has(state)) fail(`${patternPath}.states must include ${state}`);
  }
  const patternPlatforms = requireArray(pattern, patternPath, "platforms");
  if (!patternPlatforms.some((platform) => requiredPlatforms.includes(platform))) {
    fail(`${patternPath}.platforms must include at least one governed platform`);
  }
  const extraction = pattern.componentExtraction || {};
  if (!extractionPolicyApis.has(extraction.policy)) {
    fail(`${patternPath}.componentExtraction.policy must be defined in ${componentExtractionPath}`);
  }
  if (!allowedExtractionApis.has(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api must encode a governed component API strategy`);
  }
  const allowedForPolicy = extractionPolicyApis.get(extraction.policy);
  if (allowedForPolicy && !allowedForPolicy.has(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api ${extraction.api} is not allowed for policy ${extraction.policy}`);
  }
  if (!patternNotes.includes(`## ${patternId}`)) {
    fail(`${notesPath} must include a Markdown note for ${patternId}`);
  }
}

const decisionPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionPath);
requireFields(decisionVerification, decisionPath, [
  "schemaVersion",
  "conversationId",
  "goalReference",
  "sourceSession",
  "completionRule",
  "decisions",
]);
const expectedDecisionIds = [
  "initial_scope",
  "enforcement_mode",
  "canonical_source",
  "debt_strategy",
  "canon_approval",
  "visual_baselines_location",
  "canon_unit",
  "agent_ui_workflow",
  "performance_budget_style",
  "alignment_validation",
  "state_coverage",
  "human_visual_review",
  "governance_location",
  "skills_shape",
  "external_references_policy",
  "gate_surface",
  "exception_policy",
  "copy_governance",
  "v1_pattern_set",
  "ci_visual_strategy",
  "perf_budget_source",
  "v1_delivery_goal",
  "registry_format",
  "skill_naming_style",
  "component_extraction_rule",
  "component_api_style",
  "size_contracts",
  "visual_mutation_permission",
  "approved_surface_protection",
  "ui_debt_fix_policy",
  "visual_model_gate",
  "mechanical_refactor_visual_safety",
  "visual_change_scope_limit",
  "ui_change_classification",
  "visual_guard_behavior",
  "visual_proposal_flow",
  "implementation_split",
  "approved_baseline_authority",
  "critical_cleanup_owner",
];
const decisions = requireArray(decisionVerification, decisionPath, "decisions");
if (decisions.length !== expectedDecisionIds.length) {
  fail(`${decisionPath}.decisions must contain ${expectedDecisionIds.length} decision records`);
}
for (const [index, expectedId] of expectedDecisionIds.entries()) {
  const decision = decisions[index];
  const label = `${decisionPath}.decisions[${index}]`;
  requireFields(decision, label, ["index", "id", "choice", "status", "publicEvidence", "remaining"]);
  if (!decision) continue;
  if (decision.index !== index + 1) fail(`${label}.index must be ${index + 1}`);
  if (decision.id !== expectedId) fail(`${label}.id must be ${expectedId}`);
  if (!["open", "verified-complete"].includes(decision.status)) fail(`${label}.status is invalid`);
  if (decision.status === "verified-complete" && decision.remaining?.length > 0) {
    fail(`${label} cannot be verified-complete while remaining work is listed`);
  }
}

const debtPath = "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
requireFields(debt, debtPath, ["schemaVersion", "status", "policy", "entries"]);
for (const [index, entry] of requireArray(debt, debtPath, "entries").entries()) {
  const label = `${debtPath}.entries[${index}]`;
  requireFields(entry, label, ["id", "scope", "platforms", "reason", "owner", "status", "reviewAfter", "allowedAction"]);
  if (entry.reviewAfter && entry.reviewAfter < today) {
    fail(`${label} expired on ${entry.reviewAfter}`);
  }
}

const debtAliasPath = "docs/ui/debt-baseline.manifest.json";
const debtAlias = readJson(debtAliasPath);
requireFields(debtAlias, debtAliasPath, ["schemaVersion", "status", "policy", "canonicalBaseline", "reportRegistry"]);
if (debtAlias?.canonicalBaseline !== debtPath) fail(`${debtAliasPath}.canonicalBaseline must be ${debtPath}`);

const debtReportPath = "docs/ui/debt-report.registry.json";
const debtReport = readJson(debtReportPath);
requireFields(debtReport, debtReportPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "reportStatusValues",
  "pendingItems",
]);

const exceptionsPath = "docs/ui/exceptions.registry.json";
const exceptions = readJson(exceptionsPath);
requireFields(exceptions, exceptionsPath, [
  "schemaVersion",
  "status",
  "policy",
  "exceptionStatuses",
  "requiredExceptionFields",
  "exceptions",
]);

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
requireFields(protectedSurfaces, protectedPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateBaselineAlias",
  "privateCopyAlias",
  "privateGeometryAlias",
  "requiredFreezeFields",
  "surfaces",
]);
for (const [index, surface] of requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, protectedSurfaces.requiredFreezeFields || []);
}

const promotionPath = "docs/ui/canon-promotions.registry.json";
const promotions = readJson(promotionPath);
requireFields(promotions, promotionPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateApprovalAlias",
  "privateBaselineAlias",
  "privateCopyAlias",
  "privateGeometryAlias",
  "promotionStatuses",
  "requiredPromotionFields",
  "promotions",
]);

const mechanicalEquivalencePath = "docs/ui/mechanical-equivalence.manifest.json";
const mechanicalEquivalence = readJson(mechanicalEquivalencePath);
requireFields(mechanicalEquivalence, mechanicalEquivalencePath, [
  "schemaVersion",
  "status",
  "policy",
  "privateEvidenceAlias",
  "requiredEvidenceFields",
  "allowedTokenDiffStatuses",
  "equivalenceStatuses",
  "records",
]);

const budgetsPath = "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
requireFields(budgets, budgetsPath, ["schemaVersion", "status", "policy", "flows"]);
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const seenFlows = new Set();
const seenFlowPlatforms = new Set();
const requiredPerformanceMetrics = new Set([
  "interactionLatencyMs",
  "p95FrameTimeMs",
  "hitchCount",
  "memoryDeltaMb",
]);
for (const [index, flow] of requireArray(budgets, budgetsPath, "flows").entries()) {
  const label = `${budgetsPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "measurementSource",
    "privateBaselineReference",
    "requiredMetrics",
    "budgetStatus",
  ]);
  seenFlows.add(flow.id);
  seenFlowPlatforms.add(`${flow.platform}:${flow.id}`);
  if (!requiredPlatforms.includes(flow.platform)) fail(`${label}.platform is not governed`);
  if (flow.measurementSource !== "private-baseline") fail(`${label}.measurementSource must be private-baseline`);
  if (!String(flow.privateBaselineReference || "").startsWith("private-codex-ui-baselines:")) {
    fail(`${label}.privateBaselineReference must use the private baseline alias`);
  }
  const metrics = new Set(requireArray(flow, label, "requiredMetrics"));
  for (const metric of requiredPerformanceMetrics) {
    if (!metrics.has(metric)) fail(`${label}.requiredMetrics must include ${metric}`);
  }
}
for (const flow of requiredFlows) {
  if (!seenFlows.has(flow)) fail(`${budgetsPath}.flows must include ${flow}`);
}
for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!seenFlowPlatforms.has(`${platform}:${flow}`)) {
      fail(`${budgetsPath}.flows must include ${platform}:${flow}`);
    }
  }
}

const privateBaselinesPath = "docs/ui/private-baselines.manifest.json";
const privateBaselines = readJson(privateBaselinesPath);
requireFields(privateBaselines, privateBaselinesPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateRootAlias",
  "privateArtifactPolicy",
  "requiredEvidenceFields",
  "flows",
]);
if (privateBaselines?.privateRootAlias !== "private-codex-ui-baselines") {
  fail(`${privateBaselinesPath}.privateRootAlias must be private-codex-ui-baselines`);
}
const baselineCoverage = new Set();
for (const [index, flow] of requireArray(privateBaselines, privateBaselinesPath, "flows").entries()) {
  const label = `${privateBaselinesPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "privateBaselineReference",
    "runnerId",
    "requiredEvidence",
    "tolerance",
  ]);
  baselineCoverage.add(`${flow.platform}:${flow.id}`);
}
for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!baselineCoverage.has(`${platform}:${flow}`)) {
      fail(`${privateBaselinesPath}.flows must include ${platform}:${flow}`);
    }
  }
}

const privateVisualValidationPath = "docs/ui/private-visual-validation.manifest.json";
const privateVisualValidation = readJson(privateVisualValidationPath);
requireFields(privateVisualValidation, privateVisualValidationPath, [
  "schemaVersion",
  "status",
  "policy",
  "verificationCommand",
  "requiredRoots",
  "delegates",
  "externalPendingExitCode",
]);

const inspirationPath = "docs/ui/inspiration/references.registry.json";
const inspiration = readJson(inspirationPath);
requireFields(inspiration, inspirationPath, ["schemaVersion", "policy", "references"]);
for (const [index, reference] of requireArray(inspiration, inspirationPath, "references").entries()) {
  const label = `${inspirationPath}.references[${index}]`;
  requireFields(reference, label, ["id", "url", "use", "canonical"]);
  if (reference.canonical !== false) {
    fail(`${label}.canonical must be false until explicitly approved`);
  }
}

const changedBase = process.env.CLAWIX_UI_GUARD_DIFF_BASE;
const visualDetectorsPath = "docs/ui/visual-change-detectors.manifest.json";
const visualDetectors = readJson(visualDetectorsPath);
requireFields(visualDetectors, visualDetectorsPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceRoots",
  "requiredChangeKinds",
  "detectors",
]);
const sourcePaths = requireArray(visualDetectors, visualDetectorsPath, "sourceRoots");
const compiledVisualDetectors = [];
for (const [index, detector] of requireArray(visualDetectors, visualDetectorsPath, "detectors").entries()) {
  const label = `${visualDetectorsPath}.detectors[${index}]`;
  requireFields(detector, label, ["id", "changeKind", "pattern", "reason"]);
  try {
    compiledVisualDetectors.push({
      id: detector.id,
      changeKind: detector.changeKind,
      reason: detector.reason,
      regex: new RegExp(detector.pattern),
    });
  } catch (error) {
    fail(`${label}.pattern is not a valid regex: ${error.message}`);
  }
}
const diffArgs = changedBase
  ? ["diff", "--unified=0", changedBase, "--", ...sourcePaths]
  : ["diff", "--unified=0", "--", ...sourcePaths];
const stagedDiffArgs = ["diff", "--cached", "--unified=0", "--", ...sourcePaths];

const visualAuthorizationEnv = String(visualAuthorization.publicSignalEnv || "");
const visualAuthorizationValue = String(visualAuthorization.publicSignalValue || "");
const visualModelEnv = String(visualModelAllowlist?.modelSignal?.env || "");
const requestedVisualModel = visualModelEnv ? String(process.env[visualModelEnv] || "") : "";
const visualAuthorized =
  Boolean(visualAuthorizationEnv) &&
  process.env[visualAuthorizationEnv] === visualAuthorizationValue &&
  Boolean(visualModelEnv) &&
  activeVisualModelIds.has(requestedVisualModel);

function matchingVisualDetector(line) {
  return compiledVisualDetectors.find((detector) => detector.regex.test(line));
}

function visualDiffHits(diffText, sourceLabel) {
  const hits = [];
  let currentPath = "<unknown>";
  let nextNewLine = 0;

  for (const line of diffText.split("\n")) {
    if (line.startsWith("+++ b/")) {
      currentPath = line.slice("+++ b/".length);
      continue;
    }

    if (line.startsWith("@@ ")) {
      const match = /\+(\d+)(?:,\d+)?/.exec(line);
      nextNewLine = match ? Number(match[1]) : 0;
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      const detector = matchingVisualDetector(line);
      if (detector) {
        hits.push({
          path: currentPath,
          line: nextNewLine || "?",
          source: sourceLabel,
          detector: detector.id,
          changeKind: detector.changeKind,
          reason: detector.reason,
          text: line.slice(1, 241),
        });
      }
      nextNewLine += 1;
      continue;
    }

    if (line.startsWith(" ") || line === "\\ No newline at end of file") {
      nextNewLine += 1;
    }
  }

  return hits;
}

const simulatedVisualDiff = [
  "diff --git a/web/src/simulated-visual-diff.tsx b/web/src/simulated-visual-diff.tsx",
  "+++ b/web/src/simulated-visual-diff.tsx",
  "@@ -0,0 +1 @@",
  '+<button className="gap-2 text-red-500" aria-label="Rename">Rename</button>',
].join("\n");
const visualHits = simulateUnauthorizedVisualDiff
  ? visualDiffHits(simulatedVisualDiff, "simulated unauthorized visual diff")
  : [
      ...visualDiffHits(git(diffArgs), changedBase ? `diff against ${changedBase}` : "working tree"),
      ...(changedBase ? [] : visualDiffHits(git(stagedDiffArgs), "staged")),
    ];
if (visualHits.length > 0 && !visualAuthorized) {
  fail(
    [
      "unauthorized visual/copy/layout source edit detected",
      `required permission: ${visualAuthorizationEnv}=${visualAuthorizationValue} and ${visualModelEnv}=<active visual model from ${visualModelAllowlistPath}>`,
      `current model signal: ${visualModelEnv || "<unset>"}=${requestedVisualModel || "<unset>"}`,
      `proposal route: ${visualModelAllowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
      "non-authorized agents must leave a conceptual proposal instead of editing visible presentation",
      ...visualHits
        .slice(0, 20)
        .map(
          (hit) =>
            `  ${hit.path}:${hit.line} [${hit.source}/${hit.detector}/${hit.changeKind}] reason=${hit.reason} text=${hit.text}`,
        ),
    ].join("\n"),
  );
}

const requiredDocs = [
  "docs/adr/0010-interface-governance.md",
  "docs/ui/README.md",
  "docs/ui/decision-verification.json",
  "docs/ui/pattern-registry/README.md",
  "docs/ui/pattern-registry/patterns/NOTES.md",
  "docs/ui/interface-governance.config.json",
  "docs/ui/implementation-evidence.manifest.json",
  "docs/ui/state-coverage.manifest.json",
  "docs/ui/surface-references.manifest.json",
  "docs/ui/surface-baseline-coverage.manifest.json",
  "docs/ui/rendered-drift.manifest.json",
  "docs/ui/gate-surface.manifest.json",
  "docs/ui/visual-model-allowlist.manifest.json",
  "docs/ui/component-extraction.manifest.json",
  "docs/ui/mechanical-equivalence.manifest.json",
  "docs/ui/visible-surfaces.inventory.json",
  "docs/ui/rendered-geometry.manifest.json",
  "docs/ui/copy.inventory.json",
  "docs/ui/visual-change-scopes.manifest.json",
  "docs/ui/visual-change-detectors.manifest.json",
  "docs/ui/visual-proposals.registry.json",
  "docs/ui/debt.baseline.json",
  "docs/ui/debt-baseline.manifest.json",
  "docs/ui/debt-report.registry.json",
  "docs/ui/critical-cleanup.queue.json",
  "docs/ui/exceptions.registry.json",
  "docs/ui/protected-surfaces.registry.json",
  "docs/ui/canon-promotions.registry.json",
  "docs/ui/performance-budgets.registry.json",
  "docs/ui/private-baselines.manifest.json",
  "docs/ui/private-visual-validation.manifest.json",
  "docs/ui/visual-change-proposal.template.md",
  "docs/ui/inspiration/references.registry.json",
];
for (const relativePath of requiredDocs) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) {
    fail(`missing required UI governance file ${relativePath}`);
  }
}

if (errors.length > 0) {
  console.error("UI governance guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI governance guard passed");
