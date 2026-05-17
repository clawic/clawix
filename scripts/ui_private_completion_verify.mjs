#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);

function hasFlag(name) {
  return args.includes(name);
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function runScript(script, scriptArgs = ["--require-approved"]) {
  const result = spawnSync(process.execPath, [path.join(rootDir, script), ...scriptArgs], {
    cwd: rootDir,
    env: process.env,
    encoding: "utf8",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    console.error(`UI private completion verification failed at ${script}.`);
    process.exit(result.status || 1);
  }
}

if (!hasFlag("--require-approved")) {
  console.error("UI private completion verification requires --require-approved.");
  process.exit(1);
}

const manifest = readJson("docs/ui/completion-gate.manifest.json");
const decisionVerification = readJson(manifest.decisionVerificationPath || "docs/ui/decision-verification.json");
const openDecisions = (decisionVerification.decisions || []).filter((decision) => decision.status === "open");
if (openDecisions.length > 0) {
  console.error(`EXTERNAL PENDING: ${openDecisions.length} open decisions block update_goal: ${openDecisions.map((decision) => decision.id).join(", ")}.`);
  process.exit(2);
}

runScript("scripts/ui_private_completion_source_verify.mjs");
runScript("scripts/ui_private_visual_verify.mjs");

console.log("UI private completion verification passed; update_goal may now be called");
