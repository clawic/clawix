#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { privateRootAliasEntries } from "./ui_private_root_contract.mjs";

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

function loadPrivateEvidenceAliases() {
  try {
    return Object.fromEntries(privateRootAliasEntries(rootDir).map((entry) => [entry.alias, entry.env]));
  } catch (error) {
    fail(`private root aliases could not be loaded: ${error.message}`);
    return {};
  }
}

function runPrivateEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("private evidence plan must pass before decision blockers can be verified");
    if (result.stderr) {
      for (const line of result.stderr.trim().split("\n")) fail(`private evidence plan: ${line}`);
    }
    return { evidence: [] };
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { evidence: [] };
  }
}

function splitPrivateEvidenceReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.includes("..")) return null;
  if (suffix.includes("*") && suffix !== "*" && !suffix.endsWith("/*")) return null;
  return { alias, suffix };
}

function isPrivateEvidenceReference(reference) {
  if (typeof reference !== "string" || reference.length === 0) return false;
  if (reference.startsWith("~/") || reference.includes("/Users/") || reference.startsWith("file://")) return false;
  const parsed = splitPrivateEvidenceReference(reference);
  if (!parsed) return false;
  if (!Object.hasOwn(privateEvidenceAliases, parsed.alias)) return false;
  return true;
}

function matchesPrivateEvidenceReference(pattern, concreteReference) {
  const patternParts = splitPrivateEvidenceReference(pattern);
  const concreteParts = splitPrivateEvidenceReference(concreteReference);
  if (!patternParts || !concreteParts || patternParts.alias !== concreteParts.alias) return false;
  if (patternParts.suffix === "*") return true;
  if (patternParts.suffix.endsWith("/*")) {
    const prefix = patternParts.suffix.slice(0, -1);
    return concreteParts.suffix.startsWith(prefix);
  }
  return patternParts.suffix === concreteParts.suffix;
}

function commandMentionsVerifier(command, verifier) {
  return typeof command === "string" && command.includes(verifier);
}

const decisionPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionPath);
const privateVisualValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const privateEvidenceAliases = loadPrivateEvidenceAliases();
const privateEvidencePlan = runPrivateEvidencePlan();
const plannedPrivateReferences = (privateEvidencePlan.evidence || []).map((item) => item.privateReference).filter(Boolean);
const privateVisualDelegateCommands = requireArray(
  privateVisualValidation,
  "docs/ui/private-visual-validation.manifest.json",
  "delegates",
  { nonEmpty: true },
);
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

const requiredPrivateRoots = new Set(
  requireArray(privateVisualValidation, "docs/ui/private-visual-validation.manifest.json", "requiredRoots", { nonEmpty: true }),
);
for (const [alias, envName] of Object.entries(privateEvidenceAliases)) {
  if (!requiredPrivateRoots.has(envName)) {
    fail(`docs/ui/private-visual-validation.manifest.json.requiredRoots must include ${envName} for ${alias}`);
  }
}

const allowedStatuses = new Set(requireArray(decisionVerification, decisionPath, "statuses"));
for (const status of ["open", "verified-complete"]) {
  if (!allowedStatuses.has(status)) fail(`${decisionPath}.statuses must include ${status}`);
}

const expectedDecisions = [
  ["initial_scope", "Cross-platform desde dia 1"],
  ["enforcement_mode", "Bloqueo estricto ya"],
  ["canonical_source", "Registry + referencias"],
  ["debt_strategy", "Baseline de deuda"],
  ["canon_approval", "OK humano explicito"],
  ["visual_baselines_location", "Privado + manifests publicos"],
  ["canon_unit", "Patrones UI"],
  ["agent_ui_workflow", "Consulta + contrato"],
  ["performance_budget_style", "Por flujo critico"],
  ["alignment_validation", "Geometrica + visual"],
  ["state_coverage", "Todos los interactivos"],
  ["human_visual_review", "Promover canon"],
  ["governance_location", "Repo Clawix publico"],
  ["skills_shape", "Skills especializadas"],
  ["external_references_policy", "Biblioteca de inspiracion"],
  ["gate_surface", "Dev + test + CI"],
  ["exception_policy", "Excepcion con caducidad"],
  ["copy_governance", "Si, como canon UI"],
  ["v1_pattern_set", "Todo visible actual"],
  ["ci_visual_strategy", "Lints + geometry + manifests"],
  ["perf_budget_source", "Baseline aprobada"],
  ["v1_delivery_goal", "Sistema + limpieza critica"],
  ["registry_format", "JSON/YAML + Markdown"],
  ["skill_naming_style", "Por intencion"],
  ["component_extraction_rule", "Repeticion + estado"],
  ["component_api_style", "Slots limitados"],
  ["size_contracts", "Contrato geometrico"],
  ["visual_mutation_permission", "Reportar y bloquearse"],
  ["approved_surface_protection", "Freeze con contrato"],
  ["ui_debt_fix_policy", "No tocar, listar"],
  ["visual_model_gate", "Allowlist explicita"],
  ["mechanical_refactor_visual_safety", "Equivalencia probada"],
  ["visual_change_scope_limit", "Change budget"],
  ["ui_change_classification", "CSS + copy + jerarquia"],
  ["visual_guard_behavior", "Fail claro"],
  ["visual_proposal_flow", "Patch conceptual"],
  ["implementation_split", "Gobernanza primero"],
  ["approved_baseline_authority", "Solo tu"],
  ["critical_cleanup_owner", "Opus allowlist"],
];

const decisions = requireArray(decisionVerification, decisionPath, "decisions");
if (decisions.length !== expectedDecisions.length) fail(`${decisionPath}.decisions must contain ${expectedDecisions.length} records`);
const ids = new Set();
for (const [index, decision] of decisions.entries()) {
  const label = `${decisionPath}.decisions[${index}]`;
  requireFields(decision, label, ["index", "id", "choice", "status", "publicEvidence", "remaining"]);
  if (!decision) continue;
  const [expectedId, expectedChoice] = expectedDecisions[index] || [];
  if (decision.index !== index + 1) fail(`${label}.index must be ${index + 1}`);
  if (decision.id !== expectedId) fail(`${label}.id must be ${expectedId}`);
  if (decision.choice !== expectedChoice) fail(`${label}.choice must be ${expectedChoice}`);
  if (ids.has(decision.id)) fail(`${label}.id duplicates ${decision.id}`);
  ids.add(decision.id);
  if (!allowedStatuses.has(decision.status)) fail(`${label}.status is not allowed`);
  if (decision.status === "verified-complete" && decision.remaining.length > 0) {
    fail(`${label} cannot be verified-complete while remaining work is listed`);
  }
  if (decision.status === "open" && decision.remaining.length === 0) {
    fail(`${label} must be verified-complete when no remaining work is listed`);
  }
  if (decision.status === "open") {
    for (const [evidenceIndex, evidence] of requireArray(decision, label, "privateEvidence").entries()) {
      if (!isPrivateEvidenceReference(evidence)) {
        fail(`${label}.privateEvidence[${evidenceIndex}] must be a public-safe private evidence alias reference`);
        continue;
      }
      const matchesPlan = plannedPrivateReferences.some((reference) => matchesPrivateEvidenceReference(evidence, reference));
      if (!matchesPlan) {
        fail(`${label}.privateEvidence[${evidenceIndex}] is not covered by the derived private evidence plan`);
      }
    }
    for (const [verifierIndex, verifier] of requireArray(decision, label, "blockingVerifiers").entries()) {
      const verifierLabel = `${label}.blockingVerifiers[${verifierIndex}]`;
      if (!isPublicEvidenceReference(verifier)) {
        fail(`${verifierLabel} must be a public-safe repo-relative reference`);
        continue;
      }
      if (!verifier.startsWith("scripts/ui_private_")) {
        fail(`${verifierLabel} must point to a private UI verifier`);
      }
      if (!fs.existsSync(path.join(rootDir, verifier))) {
        fail(`${verifierLabel} points to missing verifier ${verifier}`);
      }
      const isAggregateRunner = verifier === "scripts/ui_private_visual_verify.mjs";
      const isDelegate = privateVisualDelegateCommands.some((command) => commandMentionsVerifier(command, verifier));
      const isVerificationCommand = commandMentionsVerifier(privateVisualValidation?.verificationCommand, verifier);
      if (!isAggregateRunner && !isDelegate && !isVerificationCommand) {
        fail(`${verifierLabel} must be delegated by docs/ui/private-visual-validation.manifest.json`);
      }
    }
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
