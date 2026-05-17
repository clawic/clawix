#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function requireSnippet(relativePath, snippet) {
  const content = read(relativePath);
  if (!content.includes(snippet)) {
    fail(`${relativePath} must mention ${snippet}`);
  }
}

const requiredDocs = [
  "docs/adr/0010-interface-governance.md",
  "STYLE.md",
  "STANDARDS.md",
  "PERF.md",
  "docs/ui/README.md",
];

for (const doc of requiredDocs) read(doc);

for (const snippet of [
  "docs/ui/",
  "visual-ui",
  "copy-ui",
  "visual-model-allowlist.manifest.json",
]) {
  requireSnippet("docs/adr/0010-interface-governance.md", snippet);
  requireSnippet("STYLE.md", snippet);
}

for (const snippet of [
  "pattern registry",
  "geometry",
  "copy",
  "visual mutation permissions",
]) {
  requireSnippet("STANDARDS.md", snippet);
}

for (const snippet of [
  "docs/ui/performance-budgets.registry.json",
  "docs/ui/private-baselines.manifest.json",
  "ui_performance_budget_check.mjs",
  "ui_private_performance_budget_verify.mjs",
]) {
  requireSnippet("PERF.md", snippet);
}

for (const snippet of [
  "docs/ui/debt-baseline.*",
  "private-visual-validation.manifest.json",
  "visual-change-proposal.template.md",
  "ui_private_visual_verify.mjs --require-approved",
]) {
  requireSnippet("docs/ui/README.md", snippet);
}

if (errors.length > 0) {
  console.error("UI canon docs check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI canon docs check passed (${requiredDocs.length} docs)`);
