#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const today = new Date().toISOString().slice(0, 10);
const simulateApprovedVisualScope = args.includes("--simulate-approved-visual-scope");
const simulateOverbudgetVisualScope = args.includes("--simulate-overbudget-visual-scope");
const simulateWrongFileVisualScope = args.includes("--simulate-wrong-file-visual-scope");
const simulateLayoutOnlyVisualScope = args.includes("--simulate-layout-only-visual-scope");
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

function git(args) {
  try {
    return execFileSync("git", ["-C", rootDir, ...args], { encoding: "utf8" });
  } catch {
    return "";
  }
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const allowlistPath = "docs/ui/visual-model-allowlist.manifest.json";
const allowlist = readJson(allowlistPath);
requireFields(config, configPath, ["visualAuthorizationPolicy"]);
requireFields(allowlist, allowlistPath, [
  "authorizationSignal",
  "modelSignal",
  "proposalPath",
  "allowedVisualModels",
]);

const visualAuthorization = config?.visualAuthorizationPolicy || {};
const authorizationEnv = String(visualAuthorization.publicSignalEnv || allowlist?.authorizationSignal?.env || "");
const authorizationValue = String(visualAuthorization.publicSignalValue || allowlist?.authorizationSignal?.value || "");
const modelEnv = String(allowlist?.modelSignal?.env || "");
const requestedModel = modelEnv ? String(process.env[modelEnv] || "") : "";
const activeModels = new Set(
  requireArray(allowlist, allowlistPath, "allowedVisualModels")
    .filter((model) => model?.status === "active")
    .map((model) => model.id),
);
const visualAuthorized =
  Boolean(authorizationEnv) &&
  process.env[authorizationEnv] === authorizationValue &&
  Boolean(modelEnv) &&
  activeModels.has(requestedModel);
const visualScopesPath = "docs/ui/visual-change-scopes.manifest.json";
const visualScopes = readJson(visualScopesPath);
const visualScopeEnv = String(visualScopes?.scopeSignal?.env || "CLAWIX_UI_VISUAL_SCOPE_ID");
const requestedVisualScopeId = visualScopeEnv ? String(process.env[visualScopeEnv] || "") : "";
if (simulateApprovedVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-approved-scope",
      status: "approved",
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3 },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateOverbudgetVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-overbudget-scope",
      status: "approved",
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 1 },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateWrongFileVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-wrong-file-scope",
      status: "approved",
      files: ["docs/ui/pattern-registry/patterns/other.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3 },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateLayoutOnlyVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-layout-only-scope",
      status: "approved",
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout"],
      changeBudget: { maxFiles: 1, maxLines: 3 },
      expiresAt: "2099-12-31",
    },
  ];
}

const governedPattern = /^docs\/ui\/pattern-registry\/patterns\/[^/]+\.pattern\.json$/;
const governedFields = [
  { id: "geometry", changeKind: "visual-ui", scopeChangeKind: "layout", pattern: /"geometry"\s*:|"cornerRadius"|"padding"|"spacing"|"height"|"width"|"fontSize"|"animationDuration"|"source"\s*:/ },
  { id: "copy", changeKind: "copy-ui", scopeChangeKind: "microcopy", pattern: /"copy"\s*:|"labelMaxWords"|"tooltipMaxWords"|"visibleNamesAreCanon"|"placeholder|Label|Text|Words"/ },
  { id: "state", changeKind: "visual-ui", scopeChangeKind: "hierarchy", pattern: /"states"\s*:|"hover-or-highlight"|"focused"|"pressed"|"selected"|"busy"|"error"/ },
  { id: "references", changeKind: "visual-ui", scopeChangeKind: "layout", pattern: /"canonicalReferences"\s*:|"STYLE\.md#/ },
];

function fileMatchesScope(file, scopeFiles = []) {
  return scopeFiles.some((scopeFile) => {
    if (scopeFile === file) return true;
    if (scopeFile.endsWith("/**")) return file.startsWith(scopeFile.slice(0, -3));
    return false;
  });
}

function approvedScopeForHits(hits) {
  if (!requestedVisualScopeId) return { ok: false, reason: `${visualScopeEnv}=<approved visual scope id> is required` };
  const scope = (visualScopes?.activeScopes || []).find((candidate) => candidate?.id === requestedVisualScopeId);
  if (!scope) return { ok: false, reason: `scope ${requestedVisualScopeId} is not listed in ${visualScopesPath}.activeScopes` };
  if (scope.status !== "approved") return { ok: false, reason: `scope ${requestedVisualScopeId} is ${scope.status}, not approved` };
  if (scope.expiresAt && scope.expiresAt < today) return { ok: false, reason: `scope ${requestedVisualScopeId} expired on ${scope.expiresAt}` };

  const files = new Set(hits.map((hit) => hit.path));
  const scopeChangeKinds = new Set(Array.isArray(scope.changeKinds) ? scope.changeKinds : []);
  const changeBudget = scope.changeBudget || {};
  for (const file of files) {
    if (!fileMatchesScope(file, scope.files || [])) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include ${file}` };
  }
  for (const hit of hits) {
    if (!scopeChangeKinds.has(hit.scopeChangeKind)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} does not allow ${hit.scopeChangeKind}` };
    }
  }
  if (Number.isInteger(changeBudget.maxFiles) && files.size > changeBudget.maxFiles) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} maxFiles budget exceeded` };
  }
  if (Number.isInteger(changeBudget.maxLines) && hits.length > changeBudget.maxLines) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} maxLines budget exceeded` };
  }
  return { ok: true, scope };
}

function findPatternMutationHits(diffText, sourceLabel) {
  const hits = [];
  let oldPath = "<unknown>";
  let newPath = "<unknown>";
  let nextOldLine = 0;
  let nextNewLine = 0;

  for (const line of diffText.split("\n")) {
    if (line.startsWith("--- a/")) {
      oldPath = line.slice("--- a/".length);
      continue;
    }
    if (line.startsWith("+++ b/")) {
      newPath = line.slice("+++ b/".length);
      continue;
    }
    if (line === "+++ /dev/null") {
      newPath = "/dev/null";
      continue;
    }
    if (line.startsWith("@@ ")) {
      const match = /-(\d+)(?:,\d+)? \+(\d+)(?:,\d+)?/.exec(line);
      nextOldLine = match ? Number(match[1]) : 0;
      nextNewLine = match ? Number(match[2]) : 0;
      continue;
    }
    if ((line.startsWith("+") && !line.startsWith("+++")) || (line.startsWith("-") && !line.startsWith("---"))) {
      const isRemoval = line.startsWith("-");
      const sourceLine = isRemoval ? nextOldLine : nextNewLine;
      const currentPath = isRemoval ? oldPath : newPath;
      if (governedPattern.test(currentPath)) {
        for (const field of governedFields) {
          if (field.pattern.test(line)) {
            hits.push({
              path: currentPath,
              line: sourceLine || "?",
              source: sourceLabel,
              detector: field.id,
              changeKind: field.changeKind,
              scopeChangeKind: field.scopeChangeKind,
              operation: isRemoval ? "removed" : "added",
              text: line.slice(1, 241),
            });
          }
        }
      }
      if (isRemoval) {
        nextOldLine += 1;
      } else {
        nextNewLine += 1;
      }
      continue;
    }
    if (line.startsWith(" ")) {
      nextOldLine += 1;
      nextNewLine += 1;
    }
  }

  return hits;
}

const simulatedPatternMutation = [
  "diff --git a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "+++ b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "@@ -0,0 +1,3 @@",
  '+  "geometry": { "rowHeight": 36, "cornerRadius": 10 },',
  '+  "copy": { "labelMaxWords": 5 },',
  '+  "states": ["idle", "focused"]',
].join("\n");

const simulatedPatternRemoval = [
  "diff --git a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "--- a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "+++ b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "@@ -12,3 +12,0 @@",
  '-  "geometry": { "rowHeight": 36, "cornerRadius": 10 },',
  '-  "copy": { "labelMaxWords": 5 },',
  '-  "states": ["idle", "focused"]',
].join("\n");

const simulatedPatternDeletion = [
  "diff --git a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "deleted file mode 100644",
  "--- a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "+++ /dev/null",
  "@@ -12,3 +0,0 @@",
  '-  "geometry": { "rowHeight": 36, "cornerRadius": 10 },',
  '-  "copy": { "labelMaxWords": 5 },',
  '-  "states": ["idle", "focused"]',
].join("\n");

const sourceRoots = ["docs/ui/pattern-registry/patterns"];
const changedBase = process.env.CLAWIX_UI_GUARD_DIFF_BASE;
const visualHits = args.includes("--simulate-unauthorized-pattern-mutation")
  ? findPatternMutationHits(simulatedPatternMutation, "simulated unauthorized pattern mutation")
  : args.includes("--simulate-unauthorized-pattern-removal")
    ? findPatternMutationHits(simulatedPatternRemoval, "simulated unauthorized pattern removal")
    : args.includes("--simulate-unauthorized-pattern-deletion")
      ? findPatternMutationHits(simulatedPatternDeletion, "simulated unauthorized pattern deletion")
  : [
      ...findPatternMutationHits(
        git(changedBase ? ["diff", "--unified=0", changedBase, "--", ...sourceRoots] : ["diff", "--unified=0", "--", ...sourceRoots]),
        changedBase ? `diff against ${changedBase}` : "working tree",
      ),
      ...(changedBase ? [] : findPatternMutationHits(git(["diff", "--cached", "--unified=0", "--", ...sourceRoots]), "staged")),
    ];

if (visualHits.length > 0 && !visualAuthorized) {
  fail(
    [
      "unauthorized pattern registry visual/copy contract mutation detected",
      `required permission: ${authorizationEnv}=${authorizationValue} and ${modelEnv}=<active visual model from ${allowlistPath}>`,
      `current model signal: ${modelEnv || "<unset>"}=${requestedModel || "<unset>"}`,
      `proposal route: ${allowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
      "non-authorized agents may update governance wiring, but visual/copy contract mutations require an allowlisted visual lane",
      ...visualHits.map(
        (hit) =>
          `  ${hit.path}:${hit.line} [${hit.source}/${hit.detector}/${hit.changeKind}/${hit.operation}] text=${hit.text}`,
      ),
    ].join("\n"),
  );
}
if (visualHits.length > 0 && visualAuthorized) {
  const scopeResult = approvedScopeForHits(visualHits);
  if (!scopeResult.ok) {
    fail(
      [
        "authorized pattern registry visual/copy contract mutation missing approved scope",
        `required scope: ${visualScopeEnv}=<approved scope from ${visualScopesPath}>`,
        `current scope signal: ${visualScopeEnv}=${requestedVisualScopeId || "<unset>"}`,
        `reason: ${scopeResult.reason}`,
        `proposal route: ${allowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
        ...visualHits.map(
          (hit) =>
            `  ${hit.path}:${hit.line} [${hit.source}/${hit.detector}/${hit.changeKind}/${hit.operation}] text=${hit.text}`,
        ),
      ].join("\n"),
    );
  }
}

if (errors.length > 0) {
  console.error("UI pattern mutation guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI pattern mutation guard passed");
