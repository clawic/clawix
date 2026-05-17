#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);

function hasFlag(name) {
  return args.includes(name);
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");

const checks = [
  {
    name: "complete private evidence plan",
    envs: [
      "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
      "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
      "CLAWIX_UI_PRIVATE_COPY_ROOT",
      "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
      "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
    ],
    script: "scripts/ui_private_evidence_verify.mjs",
    args: ["--require-approved", ...(includePending ? ["--include-pending"] : [])],
  },
  {
    name: "private debt audit",
    env: "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
    script: "scripts/ui_private_debt_audit_verify.mjs",
    args: ["--require-approved", ...(includePending ? ["--include-pending"] : [])],
  },
  {
    name: "private baseline",
    env: "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
    script: "scripts/ui_private_baseline_verify.mjs",
    args: ["--require-approved", ...(includePending ? ["--include-pending"] : [])],
  },
  {
    name: "private rendered geometry",
    env: "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
    script: "scripts/ui_private_geometry_verify.mjs",
    args: ["--require-approved"],
  },
  {
    name: "private copy",
    env: "CLAWIX_UI_PRIVATE_COPY_ROOT",
    script: "scripts/ui_private_copy_verify.mjs",
    args: ["--require-approved", ...(includePending ? ["--include-pending"] : [])],
  },
  {
    name: "private rendered drift",
    env: "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
    script: "scripts/ui_private_drift_verify.mjs",
    args: ["--require-approved", ...(includePending ? ["--include-pending"] : [])],
  },
  {
    name: "private performance budgets",
    env: "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
    script: "scripts/ui_private_performance_budget_verify.mjs",
    args: ["--require-approved", ...(includePending ? ["--include-pending"] : [])],
  },
];

if (!requireApproved) {
  console.error("UI private visual verification requires --require-approved.");
  process.exit(1);
}

const missingRoots = [
  ...new Set(checks.flatMap((check) => check.envs || [check.env]).filter((envName) => !process.env[envName])),
];
if (missingRoots.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingRoots.join(", ")} to verify private UI evidence.`);
  process.exit(2);
}

for (const check of checks) {
  const result = spawnSync(process.execPath, [path.join(rootDir, check.script), ...check.args], {
    cwd: rootDir,
    env: process.env,
    encoding: "utf8",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    console.error(`UI private visual verification failed at ${check.name}.`);
    process.exit(result.status || 1);
  }
}

console.log("UI private visual verification passed");
