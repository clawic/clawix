#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
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

const governedPattern = /^docs\/ui\/pattern-registry\/patterns\/[^/]+\.pattern\.json$/;
const governedFields = [
  { id: "geometry", changeKind: "visual-ui", pattern: /"geometry"\s*:|"cornerRadius"|"padding"|"spacing"|"height"|"width"|"fontSize"|"animationDuration"|"source"\s*:/ },
  { id: "copy", changeKind: "copy-ui", pattern: /"copy"\s*:|"labelMaxWords"|"tooltipMaxWords"|"visibleNamesAreCanon"|"placeholder|Label|Text|Words"/ },
  { id: "state", changeKind: "visual-ui", pattern: /"states"\s*:|"hover-or-highlight"|"focused"|"pressed"|"selected"|"busy"|"error"/ },
  { id: "references", changeKind: "visual-ui", pattern: /"canonicalReferences"\s*:|"STYLE\.md#/ },
];

function findPatternMutationHits(diffText, sourceLabel) {
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
      if (governedPattern.test(currentPath)) {
        for (const field of governedFields) {
          if (field.pattern.test(line)) {
            hits.push({
              path: currentPath,
              line: nextNewLine || "?",
              source: sourceLabel,
              detector: field.id,
              changeKind: field.changeKind,
              text: line.slice(1, 241),
            });
          }
        }
      }
      nextNewLine += 1;
      continue;
    }
    if (line.startsWith(" ") || line === "\\ No newline at end of file") nextNewLine += 1;
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

const sourceRoots = ["docs/ui/pattern-registry/patterns"];
const changedBase = process.env.CLAWIX_UI_GUARD_DIFF_BASE;
const visualHits = args.includes("--simulate-unauthorized-pattern-mutation")
  ? findPatternMutationHits(simulatedPatternMutation, "simulated unauthorized pattern mutation")
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
          `  ${hit.path}:${hit.line} [${hit.source}/${hit.detector}/${hit.changeKind}] text=${hit.text}`,
      ),
    ].join("\n"),
  );
}

if (errors.length > 0) {
  console.error("UI pattern mutation guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI pattern mutation guard passed");
