#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

const env = { ...process.env };
delete env.CLAWIX_UI_VISUAL_AUTHORIZED;
delete env.CLAWIX_UI_VISUAL_MODEL;

let output = "";
let exitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff"], {
    cwd: rootDir,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  exitCode = error.status || 1;
  output = `${error.stdout || ""}${error.stderr || ""}`;
}

if (exitCode === 0) {
  fail("simulated unauthorized visual diff must fail");
}

for (const snippet of [
  "unauthorized visual/copy/layout source edit detected",
  "required permission:",
  "current model signal:",
  "proposal route:",
  "non-authorized agents must leave a conceptual proposal",
  "simulated unauthorized visual diff",
  "web/src/simulated-visual-diff.tsx:1",
  "className",
  "web/src/simulated-visual-diff.tsx:2",
  "cross-visible-option-list",
  "visible-model-alpha",
]) {
  if (!output.includes(snippet)) fail(`failure output is missing: ${snippet}`);
}

let authorizedExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedExitCode = error.status || 1;
}
if (authorizedExitCode !== 0) {
  fail("simulated visual diff must pass when explicitly authorized for claude-opus-4.7");
}

let wrongModelOutput = "";
let wrongModelExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "non-allowlisted-model",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  wrongModelExitCode = error.status || 1;
  wrongModelOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (wrongModelExitCode === 0) {
  fail("simulated visual diff must fail for a non-allowlisted visual model");
}
if (!wrongModelOutput.includes("CLAWIX_UI_VISUAL_MODEL=non-allowlisted-model")) {
  fail("wrong model failure output must include the rejected model signal");
}

let patternOutput = "";
let patternExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation"], {
    cwd: rootDir,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternExitCode = error.status || 1;
  patternOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternExitCode === 0) {
  fail("simulated unauthorized pattern mutation must fail");
}

for (const snippet of [
  "unauthorized pattern registry visual/copy contract mutation detected",
  "required permission:",
  "current model signal:",
  "proposal route:",
  "simulated unauthorized pattern mutation",
  "docs/ui/pattern-registry/patterns/sidebar-row.pattern.json:1",
  "geometry",
]) {
  if (!patternOutput.includes(snippet)) fail(`pattern mutation failure output is missing: ${snippet}`);
}

const driftRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ui-drift-failure-"));
let driftOutput = "";
let driftExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_private_drift_verify.mjs", "--root", driftRoot, "--require-approved"], {
    cwd: rootDir,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  driftExitCode = error.status || 1;
  driftOutput = `${error.stdout || ""}${error.stderr || ""}`;
} finally {
  fs.rmSync(driftRoot, { recursive: true, force: true });
}

if (driftExitCode === 0) {
  fail("private rendered drift verifier must fail when reports are pending approval");
}

for (const snippet of [
  "UI private drift verification failed:",
  "rendered drift evidence is not approved",
  "route:",
  "privateDriftReportReference:",
  "reason: pending private evidence",
  "required permission: approved private rendered drift evidence from a visual-authorized lane",
  "macos-root-chrome",
]) {
  if (!driftOutput.includes(snippet)) fail(`private drift failure output is missing: ${snippet}`);
}

if (errors.length > 0) {
  console.error("UI visual guard failure check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI visual guard failure check passed");
