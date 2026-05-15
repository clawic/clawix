import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const json = process.argv.includes("--json");

const requiredDocs = [
  "docs/adr/0009-agentic-naming-and-code-structure.md",
  "docs/agentic-naming-guide.md",
  "docs/vocabulary.registry.json",
  "docs/vocabulary.md",
  "docs/naming-style-guide.md",
  "docs/adr/0004-source-file-boundaries.md",
  "scripts/source-size-check.mjs",
];

const criticalVocabularySurfaces = [
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift",
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md",
  "android/app/src/main/java/com/example/clawix/android/core/BridgeProtocol.kt",
  "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameEncoding.kt",
  "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameDecoding.kt",
  "windows/Clawix.Core/BridgeBody.cs",
  "windows/Clawix.Core/BridgeFrame.cs",
  "windows/Clawix.Core/BridgeFrameEncoder.cs",
  "windows/Clawix.Core/BridgeFrameDecoder.cs",
  "web/src/bridge/frames.ts",
  "web/src/bridge/client.ts",
  "docs/interface-surface-clawix.registry.json",
  "docs/interface-matrix.md",
];

const sourceExtensions = new Set([".swift", ".ts", ".tsx", ".js", ".mjs", ".cs", ".kt"]);
const broadTerms = ["Thing", "Stuff", "Helper", "Helpers", "Util", "Utils", "Common", "Data", "Info", "Manager"];
const allowedBroadSymbolContexts = [
  "DatabaseManager",
  "IoTManager",
  "MarketplaceManager",
  "ClawJSServiceManager",
  "FileManager",
  "SecretsManager",
  "ConnectivityManager",
  "InputMethodManager",
  "PackageManager",
  "WindowManager",
];
const rootConventionalMarkdown = new Set([
  "AGENTS.md",
  "CHANGELOG.md",
  "CLAUDE.md",
  "CODE_OF_CONDUCT.md",
  "CONTRIBUTING.md",
  "README.md",
  "RELEASING.md",
  "SECURITY.md",
  "TEMPLATE.md",
]);
const conventionalDataFiles = new Set([
  "codebase-manifest.json",
  "package.json",
  "source-size-baseline.json",
  "tsconfig.json",
]);
const ignoredDirectoryNames = new Set([
  ".git",
  ".build",
  ".claude",
  ".next",
  ".next-e2e",
  ".tmp",
  "artifacts",
  "build",
  "coverage",
  "dist",
  "node_modules",
  "playwright-report",
  "test-results",
]);
const ignoredPathParts = [
  "/cli/lib/vendor/",
  "/output/playwright/",
  "/Resources/web-dist/",
];

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function exists(relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join("/");
}

function shouldIgnorePath(relativePath, entryName) {
  if (ignoredDirectoryNames.has(entryName)) return true;
  const wrapped = `/${relativePath}/`;
  return ignoredPathParts.some((part) => wrapped.includes(part));
}

function walk(directory, out = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolutePath = path.join(directory, entry.name);
    const relativePath = toPosix(path.relative(rootDir, absolutePath));
    if (shouldIgnorePath(relativePath, entry.name)) continue;
    if (entry.isDirectory()) walk(absolutePath, out);
    else if (entry.isFile()) out.push(relativePath);
  }
  return out;
}

function loadVocabulary() {
  const registry = JSON.parse(read("docs/vocabulary.registry.json"));
  const criticalForbidden = [];
  for (const term of registry.terms ?? []) {
    for (const synonym of term.forbiddenSynonyms ?? []) {
      if (synonym.severity === "critical") criticalForbidden.push(synonym.term);
    }
  }
  return criticalForbidden;
}

function splitIdentifier(identifier) {
  return identifier
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[_-]+/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

function findBroadTerm(identifier) {
  if (allowedBroadSymbolContexts.includes(identifier)) return null;
  const tokens = splitIdentifier(identifier);
  return broadTerms.find((term) => tokens.includes(term)) ?? null;
}

function collectBroadSymbolWarnings(relativePath, text) {
  const warnings = [];
  const declarationPatterns = [
    /\b(?:class|struct|enum|protocol|interface|typealias|type|function|func)\s+([A-Za-z_][A-Za-z0-9_]*)/g,
    /\bexport\s+(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)/g,
  ];
  const seen = new Set();
  for (const pattern of declarationPatterns) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const identifier = match[1];
      if (seen.has(identifier)) continue;
      seen.add(identifier);
      const term = findBroadTerm(identifier);
      if (term) warnings.push({ path: relativePath, kind: "broad-symbol", term, symbol: identifier });
    }
  }
  return warnings;
}

const failures = [];
const warnings = [];

for (const relativePath of requiredDocs) {
  if (!exists(relativePath)) failures.push(`missing naming source ${relativePath}`);
}

let criticalForbidden = [];
if (exists("docs/vocabulary.registry.json")) {
  criticalForbidden = loadVocabulary();
}

for (const relativePath of criticalVocabularySurfaces) {
  if (!exists(relativePath)) continue;
  const text = read(relativePath);
  for (const term of criticalForbidden) {
    if (text.includes(term)) {
      failures.push(`${relativePath} contains critical forbidden vocabulary ${JSON.stringify(term)}`);
    }
  }
}

for (const relativePath of ["AGENTS.md", "CLAUDE.md", "windows/CLAUDE.md"]) {
  if (!exists(relativePath)) continue;
  const text = read(relativePath);
  for (const term of ["clawix-bridged", "CLAWIX_BRIDGED"]) {
    if (text.includes(term)) failures.push(`${relativePath} contains retired bridge name ${JSON.stringify(term)}`);
  }
}

for (const relativePath of walk(rootDir)) {
  const ext = path.extname(relativePath);
  const name = path.basename(relativePath);
  if (relativePath.startsWith("docs/") && ext === ".md") {
    if (!rootConventionalMarkdown.has(name) && /[A-Z_]/.test(name)) {
      warnings.push({ path: relativePath, kind: "markdown-name", message: "Markdown docs should use kebab-case unless conventional" });
    }
  }
  if ((ext === ".json" || ext === ".yaml" || ext === ".yml") && relativePath.startsWith("docs/")) {
    if (!conventionalDataFiles.has(name) && !/\.(registry|manifest|fixture|schema|baseline)\.(json|ya?ml)$/.test(name)) {
      warnings.push({ path: relativePath, kind: "data-file-role", message: "Owned docs data files should carry a role suffix" });
    }
  }
  if (sourceExtensions.has(ext)) {
    warnings.push(...collectBroadSymbolWarnings(relativePath, read(relativePath)));
  }
}

const result = { failures, warnings };
if (json) {
  console.log(JSON.stringify(result, null, 2));
} else {
  if (failures.length) {
    console.error("naming shape check failed:");
    for (const failure of failures) console.error(`- ${failure}`);
  }
  console.log(`naming shape check ${failures.length ? "failed" : "passed"} (${warnings.length} warnings)`);
}

if (failures.length) process.exit(1);
