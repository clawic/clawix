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
const broadSymbolPattern = /\b(Thing|Stuff|Helper|Helpers|Util|Utils|Common|Data|Info|Manager)\b/g;
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

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function exists(relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join("/");
}

function walk(directory, out = []) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if ([".git", ".build", "build", "node_modules", "dist", "coverage"].includes(entry.name)) continue;
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(absolutePath, out);
    else if (entry.isFile()) out.push(toPosix(path.relative(rootDir, absolutePath)));
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
  if (relativePath.startsWith("docs/") && ext === ".md") {
    const name = path.basename(relativePath);
    const conventional = ["README.md", "AGENTS.md", "CLAUDE.md", "CONTRIBUTING.md", "CHANGELOG.md", "SECURITY.md"].includes(name);
    if (!conventional && /[A-Z_]/.test(name)) {
      warnings.push({ path: relativePath, kind: "markdown-name", message: "Markdown docs should use kebab-case unless conventional" });
    }
  }
  if ((ext === ".json" || ext === ".yaml" || ext === ".yml") && relativePath.startsWith("docs/")) {
    const name = path.basename(relativePath);
    const conventional = ["package.json", "tsconfig.json"].includes(name);
    if (!conventional && !/\.(registry|manifest|fixture|schema|baseline)\.(json|ya?ml)$/.test(name)) {
      warnings.push({ path: relativePath, kind: "data-file-role", message: "Owned docs data files should carry a role suffix" });
    }
  }
  if (sourceExtensions.has(ext)) {
    const text = read(relativePath);
    let match;
    while ((match = broadSymbolPattern.exec(text)) !== null) {
      const start = Math.max(0, match.index - 32);
      const end = Math.min(text.length, match.index + match[0].length + 32);
      const context = text.slice(start, end);
      if (!allowedBroadSymbolContexts.some((allowed) => context.includes(allowed))) {
        warnings.push({ path: relativePath, kind: "broad-symbol", term: match[0] });
        break;
      }
    }
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
