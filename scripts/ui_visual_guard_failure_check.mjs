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

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function writeJson(file, value) {
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function copyFixtureFile(fixtureRoot, relativePath) {
  const destination = path.join(fixtureRoot, relativePath);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(path.join(rootDir, relativePath), destination);
}

function runFixtureNode(fixtureRoot, args, extraEnv = {}) {
  try {
    const stdout = execFileSync(process.execPath, args, {
      cwd: fixtureRoot,
      env: {
        ...env,
        ...extraEnv,
      },
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { exitCode: 0, output: stdout };
  } catch (error) {
    return {
      exitCode: error.status || 1,
      output: `${error.stdout || ""}${error.stderr || ""}`,
    };
  }
}

function buildApprovalFixture() {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ui-approval-fixture-"));
  for (const relativePath of [
    "scripts/ui_private_approval_verify.mjs",
    "scripts/ui_private_root_contract.mjs",
    "docs/ui/approval-authority.manifest.json",
    "docs/ui/private-visual-validation.manifest.json",
    "docs/ui/canon-promotions.registry.json",
    "docs/ui/protected-surfaces.registry.json",
    "docs/ui/visual-change-scopes.manifest.json",
    "docs/ui/visual-proposals.registry.json",
    "docs/ui/exceptions.registry.json",
  ]) {
    copyFixtureFile(fixtureRoot, relativePath);
  }

  const promotionsPath = path.join(fixtureRoot, "docs/ui/canon-promotions.registry.json");
  const promotions = readJson("docs/ui/canon-promotions.registry.json");
  promotions.promotions = [
    {
      id: "fixture-canon-approval",
      approvedBy: "user",
      approvedAt: "2026-05-17",
      privateApprovalReference: "private-codex-ui-approval:canon/fixture-canon-approval",
    },
  ];
  writeJson(promotionsPath, promotions);
  return fixtureRoot;
}

const env = { ...process.env };
delete env.CLAWIX_UI_VISUAL_AUTHORIZED;
delete env.CLAWIX_UI_VISUAL_MODEL;
delete env.CLAWIX_UI_VISUAL_SCOPE_ID;
delete env.CLAWIX_UI_PRIVATE_APPROVAL_ROOT;

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
  "web/src/simulated-visual-diff.tsx:1",
  "removed",
  "Legacy",
]) {
  if (!output.includes(snippet)) fail(`failure output is missing: ${snippet}`);
}

let authorizedNoScopeOutput = "";
let authorizedNoScopeExitCode = 0;
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
  authorizedNoScopeExitCode = error.status || 1;
  authorizedNoScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedNoScopeExitCode === 0) {
  fail("simulated visual diff must fail for claude-opus-4.7 when no approved visual scope is provided");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "required scope:",
  "CLAWIX_UI_VISUAL_SCOPE_ID=<unset>",
  "proposal route:",
  "web/src/simulated-visual-diff.tsx:1",
]) {
  if (!authorizedNoScopeOutput.includes(snippet)) fail(`authorized no-scope failure output is missing: ${snippet}`);
}

let authorizedScopedExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-approved-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-approved-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedScopedExitCode = error.status || 1;
}
if (authorizedScopedExitCode !== 0) {
  fail("simulated visual diff must pass for claude-opus-4.7 with an approved visual scope");
}

let authorizedUnknownScopeOutput = "";
let authorizedUnknownScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "unknown-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedUnknownScopeExitCode = error.status || 1;
  authorizedUnknownScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedUnknownScopeExitCode === 0) {
  fail("simulated visual diff must fail when the provided visual scope is not listed");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=unknown-scope",
  "scope unknown-scope is not listed",
]) {
  if (!authorizedUnknownScopeOutput.includes(snippet)) fail(`authorized unknown-scope failure output is missing: ${snippet}`);
}

let authorizedOverbudgetScopeOutput = "";
let authorizedOverbudgetScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-overbudget-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-overbudget-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedOverbudgetScopeExitCode = error.status || 1;
  authorizedOverbudgetScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedOverbudgetScopeExitCode === 0) {
  fail("simulated visual diff must fail when the approved visual scope budget is exceeded");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-overbudget-scope",
  "maxLines budget exceeded",
]) {
  if (!authorizedOverbudgetScopeOutput.includes(snippet)) fail(`authorized overbudget-scope failure output is missing: ${snippet}`);
}

let authorizedWrongFileScopeOutput = "";
let authorizedWrongFileScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-wrong-file-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-wrong-file-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedWrongFileScopeExitCode = error.status || 1;
  authorizedWrongFileScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedWrongFileScopeExitCode === 0) {
  fail("simulated visual diff must fail when the approved visual scope does not include the touched file");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-wrong-file-scope",
  "does not include web/src/simulated-visual-diff.tsx",
]) {
  if (!authorizedWrongFileScopeOutput.includes(snippet)) fail(`authorized wrong-file-scope failure output is missing: ${snippet}`);
}

let authorizedWrongKindScopeOutput = "";
let authorizedWrongKindScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-layout-only-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-layout-only-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedWrongKindScopeExitCode = error.status || 1;
  authorizedWrongKindScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedWrongKindScopeExitCode === 0) {
  fail("simulated visual diff must fail when the approved visual scope does not allow the detected change kind");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-layout-only-scope",
  "does not allow microcopy",
]) {
  if (!authorizedWrongKindScopeOutput.includes(snippet)) fail(`authorized wrong-kind-scope failure output is missing: ${snippet}`);
}

let authorizedRevokedScopeOutput = "";
let authorizedRevokedScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-revoked-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-revoked-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedRevokedScopeExitCode = error.status || 1;
  authorizedRevokedScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedRevokedScopeExitCode === 0) {
  fail("simulated visual diff must fail when the provided visual scope is revoked");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-revoked-scope",
  "scope simulated-revoked-scope is revoked, not approved",
]) {
  if (!authorizedRevokedScopeOutput.includes(snippet)) fail(`authorized revoked-scope failure output is missing: ${snippet}`);
}

let authorizedExpiredScopeOutput = "";
let authorizedExpiredScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-expired-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-expired-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedExpiredScopeExitCode = error.status || 1;
  authorizedExpiredScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedExpiredScopeExitCode === 0) {
  fail("simulated visual diff must fail when the provided visual scope is expired");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-expired-scope",
  "scope simulated-expired-scope expired on 2000-01-01",
]) {
  if (!authorizedExpiredScopeOutput.includes(snippet)) fail(`authorized expired-scope failure output is missing: ${snippet}`);
}

let authorizedBudgetKindScopeOutput = "";
let authorizedBudgetKindScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_governance_guard.mjs", "--simulate-unauthorized-visual-diff", "--simulate-budget-kind-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-budget-kind-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  authorizedBudgetKindScopeExitCode = error.status || 1;
  authorizedBudgetKindScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}
if (authorizedBudgetKindScopeExitCode === 0) {
  fail("simulated visual diff must fail when the approved visual scope budget does not allow the detected change kind");
}
for (const snippet of [
  "authorized visual/copy/layout source edit missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-budget-kind-scope",
  "changeBudget does not allow microcopy",
]) {
  if (!authorizedBudgetKindScopeOutput.includes(snippet)) fail(`authorized budget-kind-scope failure output is missing: ${snippet}`);
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
for (const snippet of [
  "required permission:",
  "proposal route:",
  "non-authorized agents must leave a conceptual proposal",
]) {
  if (!wrongModelOutput.includes(snippet)) fail(`wrong model failure output is missing: ${snippet}`);
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
  "added",
  "geometry",
]) {
  if (!patternOutput.includes(snippet)) fail(`pattern mutation failure output is missing: ${snippet}`);
}

let patternAuthorizedNoScopeOutput = "";
let patternAuthorizedNoScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation"], {
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
  patternAuthorizedNoScopeExitCode = error.status || 1;
  patternAuthorizedNoScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedNoScopeExitCode === 0) {
  fail("simulated pattern mutation must fail for claude-opus-4.7 when no approved visual scope is provided");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "required scope:",
  "CLAWIX_UI_VISUAL_SCOPE_ID=<unset>",
  "proposal route:",
  "simulated unauthorized pattern mutation",
  "docs/ui/pattern-registry/patterns/sidebar-row.pattern.json:1",
]) {
  if (!patternAuthorizedNoScopeOutput.includes(snippet)) fail(`pattern authorized no-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedScopedExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-approved-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-approved-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedScopedExitCode = error.status || 1;
}
if (patternAuthorizedScopedExitCode !== 0) {
  fail("simulated pattern mutation must pass for claude-opus-4.7 with an approved visual scope");
}

let patternAuthorizedUnknownScopeOutput = "";
let patternAuthorizedUnknownScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "unknown-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedUnknownScopeExitCode = error.status || 1;
  patternAuthorizedUnknownScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedUnknownScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the provided visual scope is not listed");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=unknown-scope",
  "scope unknown-scope is not listed",
]) {
  if (!patternAuthorizedUnknownScopeOutput.includes(snippet)) fail(`pattern authorized unknown-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedOverbudgetScopeOutput = "";
let patternAuthorizedOverbudgetScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-overbudget-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-overbudget-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedOverbudgetScopeExitCode = error.status || 1;
  patternAuthorizedOverbudgetScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedOverbudgetScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the approved visual scope budget is exceeded");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-overbudget-scope",
  "maxLines budget exceeded",
]) {
  if (!patternAuthorizedOverbudgetScopeOutput.includes(snippet)) fail(`pattern authorized overbudget-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedWrongFileScopeOutput = "";
let patternAuthorizedWrongFileScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-wrong-file-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-wrong-file-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedWrongFileScopeExitCode = error.status || 1;
  patternAuthorizedWrongFileScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedWrongFileScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the approved visual scope does not include the touched file");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-wrong-file-scope",
  "does not include docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
]) {
  if (!patternAuthorizedWrongFileScopeOutput.includes(snippet)) fail(`pattern authorized wrong-file-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedWrongKindScopeOutput = "";
let patternAuthorizedWrongKindScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-layout-only-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-layout-only-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedWrongKindScopeExitCode = error.status || 1;
  patternAuthorizedWrongKindScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedWrongKindScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the approved visual scope does not allow the detected change kind");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-layout-only-scope",
  "does not allow microcopy",
]) {
  if (!patternAuthorizedWrongKindScopeOutput.includes(snippet)) fail(`pattern authorized wrong-kind-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedRevokedScopeOutput = "";
let patternAuthorizedRevokedScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-revoked-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-revoked-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedRevokedScopeExitCode = error.status || 1;
  patternAuthorizedRevokedScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedRevokedScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the provided visual scope is revoked");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-revoked-scope",
  "scope simulated-revoked-scope is revoked, not approved",
]) {
  if (!patternAuthorizedRevokedScopeOutput.includes(snippet)) fail(`pattern authorized revoked-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedExpiredScopeOutput = "";
let patternAuthorizedExpiredScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-expired-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-expired-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedExpiredScopeExitCode = error.status || 1;
  patternAuthorizedExpiredScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedExpiredScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the provided visual scope is expired");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-expired-scope",
  "scope simulated-expired-scope expired on 2000-01-01",
]) {
  if (!patternAuthorizedExpiredScopeOutput.includes(snippet)) fail(`pattern authorized expired-scope failure output is missing: ${snippet}`);
}

let patternAuthorizedBudgetKindScopeOutput = "";
let patternAuthorizedBudgetKindScopeExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation", "--simulate-budget-kind-visual-scope"], {
    cwd: rootDir,
    env: {
      ...env,
      CLAWIX_UI_VISUAL_AUTHORIZED: "1",
      CLAWIX_UI_VISUAL_MODEL: "claude-opus-4.7",
      CLAWIX_UI_VISUAL_SCOPE_ID: "simulated-budget-kind-scope",
    },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternAuthorizedBudgetKindScopeExitCode = error.status || 1;
  patternAuthorizedBudgetKindScopeOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternAuthorizedBudgetKindScopeExitCode === 0) {
  fail("simulated pattern mutation must fail when the approved visual scope budget does not allow the detected change kind");
}
for (const snippet of [
  "authorized pattern registry visual/copy contract mutation missing approved scope",
  "current scope signal: CLAWIX_UI_VISUAL_SCOPE_ID=simulated-budget-kind-scope",
  "changeBudget does not allow microcopy",
]) {
  if (!patternAuthorizedBudgetKindScopeOutput.includes(snippet)) fail(`pattern authorized budget-kind-scope failure output is missing: ${snippet}`);
}

let patternWrongModelOutput = "";
let patternWrongModelExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-mutation"], {
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
  patternWrongModelExitCode = error.status || 1;
  patternWrongModelOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternWrongModelExitCode === 0) {
  fail("simulated pattern mutation must fail for a non-allowlisted visual model");
}
for (const snippet of [
  "unauthorized pattern registry visual/copy contract mutation detected",
  "required permission:",
  "current model signal:",
  "CLAWIX_UI_VISUAL_MODEL=non-allowlisted-model",
  "proposal route:",
  "simulated unauthorized pattern mutation",
]) {
  if (!patternWrongModelOutput.includes(snippet)) fail(`pattern wrong model failure output is missing: ${snippet}`);
}

let patternRemovalOutput = "";
let patternRemovalExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-removal"], {
    cwd: rootDir,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternRemovalExitCode = error.status || 1;
  patternRemovalOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternRemovalExitCode === 0) {
  fail("simulated unauthorized pattern removal must fail");
}

for (const snippet of [
  "unauthorized pattern registry visual/copy contract mutation detected",
  "required permission:",
  "current model signal:",
  "proposal route:",
  "simulated unauthorized pattern removal",
  "docs/ui/pattern-registry/patterns/sidebar-row.pattern.json:12",
  "removed",
  "geometry",
]) {
  if (!patternRemovalOutput.includes(snippet)) fail(`pattern removal failure output is missing: ${snippet}`);
}

let patternDeletionOutput = "";
let patternDeletionExitCode = 0;
try {
  execFileSync("node", ["scripts/ui_pattern_mutation_guard.mjs", "--simulate-unauthorized-pattern-deletion"], {
    cwd: rootDir,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (error) {
  patternDeletionExitCode = error.status || 1;
  patternDeletionOutput = `${error.stdout || ""}${error.stderr || ""}`;
}

if (patternDeletionExitCode === 0) {
  fail("simulated unauthorized pattern deletion must fail");
}

for (const snippet of [
  "unauthorized pattern registry visual/copy contract mutation detected",
  "required permission:",
  "current model signal:",
  "proposal route:",
  "simulated unauthorized pattern deletion",
  "docs/ui/pattern-registry/patterns/sidebar-row.pattern.json:12",
  "removed",
  "geometry",
]) {
  if (!patternDeletionOutput.includes(snippet)) fail(`pattern deletion failure output is missing: ${snippet}`);
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

const approvalFixtureRoot = buildApprovalFixture();
const approvalPrivateRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ui-approval-private-"));
try {
  const missingApprovalRootResult = runFixtureNode(approvalFixtureRoot, ["scripts/ui_private_approval_verify.mjs", "--require-approved"]);
  if (missingApprovalRootResult.exitCode !== 2) {
    fail("private approval verifier must report EXTERNAL PENDING when approval records exist and the private root is missing");
  }
  for (const snippet of [
    "EXTERNAL PENDING:",
    "CLAWIX_UI_PRIVATE_APPROVAL_ROOT",
    "private approval evidence",
  ]) {
    if (!missingApprovalRootResult.output.includes(snippet)) fail(`private approval missing-root output is missing: ${snippet}`);
  }

  const approvalEvidenceDir = path.join(approvalPrivateRoot, "canon", "fixture-canon-approval");
  fs.mkdirSync(approvalEvidenceDir, { recursive: true });
  writeJson(path.join(approvalEvidenceDir, "approval-evidence.json"), {
    sourceId: "canon-promotions",
    privateApprovalReference: "private-codex-ui-approval:canon/fixture-canon-approval",
    approvedBy: "user",
    approvedAt: "2026-05-17",
    approvalHash: "not-a-valid-hash",
  });
  const invalidApprovalResult = runFixtureNode(
    approvalFixtureRoot,
    ["scripts/ui_private_approval_verify.mjs", "--require-approved"],
    { CLAWIX_UI_PRIVATE_APPROVAL_ROOT: approvalPrivateRoot },
  );
  if (invalidApprovalResult.exitCode === 0) {
    fail("private approval verifier must fail when approval evidence is invalid");
  }
  for (const snippet of [
    "UI private approval verification failed:",
    "approvalHash must be a 64-character hex hash",
    "docs/ui/canon-promotions.registry.json.promotions[0]",
  ]) {
    if (!invalidApprovalResult.output.includes(snippet)) fail(`private approval invalid-evidence output is missing: ${snippet}`);
  }

  writeJson(path.join(approvalEvidenceDir, "approval-evidence.json"), {
    sourceId: "canon-promotions",
    privateApprovalReference: "private-codex-ui-approval:canon/fixture-canon-approval",
    approvedBy: "user",
    approvedAt: "2026-05-17",
    approvalHash: "a".repeat(64),
  });
  const validApprovalResult = runFixtureNode(
    approvalFixtureRoot,
    ["scripts/ui_private_approval_verify.mjs", "--require-approved"],
    { CLAWIX_UI_PRIVATE_APPROVAL_ROOT: approvalPrivateRoot },
  );
  if (validApprovalResult.exitCode !== 0) {
    fail("private approval verifier must pass when approval evidence matches the public approval record");
  }
  if (!validApprovalResult.output.includes("UI private approval verification passed (1 approval records)")) {
    fail("private approval valid-evidence output must report one verified approval record");
  }
} finally {
  fs.rmSync(approvalFixtureRoot, { recursive: true, force: true });
  fs.rmSync(approvalPrivateRoot, { recursive: true, force: true });
}

if (errors.length > 0) {
  console.error("UI visual guard failure check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI visual guard failure check passed");
