import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const jsonPath = valueAfter("--json");
const markdownPath = valueAfter("--markdown");

const ignoredDirectories = new Set([
  ".git",
  ".next",
  ".turbo",
  ".vitepress",
  ".vercel",
  ".yarn",
  "artifacts",
  "bin",
  "build",
  "coverage",
  "dist",
  "node_modules",
  "obj",
  "output",
  "playwright-report",
  "test-results",
]);
const ignoredFiles = new Set(["package-lock.json", "pnpm-lock.yaml", "yarn.lock"]);
const ignoredPaths = new Set(["scripts/code-hygiene-audit.mjs"]);
const ignoredPathPrefixes = [
  ".claude/worktrees/",
  ".codex/worktrees/",
  "macos/Helpers/Bridged/Sources/clawix-bridge/Resources/web-dist/",
];
const publicOrGeneratedAssetPrefixes = [
  "android/app/src/main/res/mipmap-",
  "ios/Sources/Clawix/Assets.xcassets/",
  "macos/Resources/AppIcons/",
];
const sourceExtensions = new Set([
  ".cjs",
  ".css",
  ".html",
  ".js",
  ".json",
  ".jsx",
  ".md",
  ".mdx",
  ".mjs",
  ".scss",
  ".sh",
  ".swift",
  ".ts",
  ".tsx",
  ".yaml",
  ".yml",
]);
const assetExtensions = new Set([".gif", ".icns", ".ico", ".jpg", ".jpeg", ".png", ".svg", ".wav", ".webp"]);
const todoPattern = /\b(TODO|FIXME|HACK|XXX)\b(?:\(([^)]+)\))?:?\s*(.*)/i;
const categoryPattern = /code-hygiene:([a-z0-9_-]+)/i;

if (args.has("--self-test")) {
  runSelfTest();
  console.log("code hygiene audit self-test passed");
  process.exit(0);
}

const files = walk(rootDir);
const todoFindings = scanTodos(files);
const duplicateAssetGroups = scanDuplicateAssets(files);
const sourceReferenceIndex = buildSourceReferenceIndex(files);
const unreferencedAssetCandidates = scanUnreferencedAssets(files, sourceReferenceIndex);
const report = {
  schemaVersion: 1,
  program: "code-hygiene",
  generatedAt: new Date().toISOString(),
  mode: "report-only",
  summary: {
    scannedFiles: files.length,
    todoFindings: todoFindings.length,
    duplicateAssetGroups: duplicateAssetGroups.length,
    duplicateAssetFiles: duplicateAssetGroups.reduce((total, group) => total + group.files.length, 0),
    unreferencedAssetCandidates: unreferencedAssetCandidates.length,
  },
  findings: {
    todos: todoFindings.slice(0, 500),
    duplicateAssets: duplicateAssetGroups.slice(0, 200),
    unreferencedAssets: unreferencedAssetCandidates.slice(0, 500),
  },
};

if (jsonPath) fs.writeFileSync(path.resolve(rootDir, jsonPath), `${JSON.stringify(report, null, 2)}\n`);
if (markdownPath) fs.writeFileSync(path.resolve(rootDir, markdownPath), renderMarkdown(report));
if (!jsonPath && !markdownPath) console.log(JSON.stringify(report, null, 2));

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

function walk(directory) {
  const results = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith(".") && entry.name !== ".claude" && entry.name !== ".codex") {
      if (entry.isDirectory()) continue;
    }
    if (ignoredDirectories.has(entry.name)) continue;
    const absolutePath = path.join(directory, entry.name);
    const relativePath = path.relative(rootDir, absolutePath);
    if (ignoredPathPrefixes.some((prefix) => `${relativePath}/`.startsWith(prefix))) continue;
    if (entry.isDirectory()) {
      results.push(...walk(absolutePath));
    } else if (!ignoredFiles.has(entry.name)) {
      if (ignoredPaths.has(relativePath)) continue;
      results.push(relativePath);
    }
  }
  return results;
}

function scanTodos(files) {
  const findings = [];
  for (const relativePath of files) {
    const extension = path.extname(relativePath);
    if (!sourceExtensions.has(extension)) continue;
    const text = safeReadText(relativePath);
    if (text === null) continue;
    const lines = text.split(/\r?\n/);
    for (const [index, line] of lines.entries()) {
      const match = line.match(todoPattern);
      if (!match) continue;
      if (!isActionableTodoLine(line, match)) continue;
      const explicitCategory = match[2] || line.match(categoryPattern)?.[1] || null;
      findings.push({
        path: relativePath,
        line: index + 1,
        kind: match[1].toUpperCase(),
        category: explicitCategory || "uncategorized",
        text: line.trim().slice(0, 240),
      });
    }
  }
  return findings;
}

function isActionableTodoLine(line, match) {
  const before = line.slice(0, match.index ?? 0);
  const trimmed = line.trimStart();
  const marker = match[1].toUpperCase();
  if (marker === "XXX" && /^XXX(?:-|$)/i.test(line.slice(match.index ?? 0))) return false;
  if (/^(\/\/|\/\*|\*|#|<!--|\{\/\*|\{#)/.test(trimmed)) return true;
  if (/^[-*]\s+\[\s\]\s+/i.test(trimmed)) return true;
  return /(\/\/|\/\*|<!--)\s*$/.test(before);
}

function scanDuplicateAssets(files) {
  const hashes = new Map();
  for (const relativePath of files) {
    if (!assetExtensions.has(path.extname(relativePath).toLowerCase())) continue;
    const absolutePath = path.join(rootDir, relativePath);
    const stat = fs.statSync(absolutePath);
    if (stat.size === 0 || stat.size > 5 * 1024 * 1024) continue;
    const hash = crypto.createHash("sha256").update(fs.readFileSync(absolutePath)).digest("hex");
    const group = hashes.get(hash) ?? { hash, size: stat.size, files: [] };
    group.files.push(relativePath);
    hashes.set(hash, group);
  }
  return [...hashes.values()].filter((group) => group.files.length > 1);
}

function buildSourceReferenceIndex(files) {
  const chunks = [];
  for (const relativePath of files) {
    const extension = path.extname(relativePath);
    if (!sourceExtensions.has(extension) || assetExtensions.has(extension.toLowerCase())) continue;
    const text = safeReadText(relativePath);
    if (text === null) continue;
    chunks.push(relativePath.toLowerCase(), text.toLowerCase());
  }
  return chunks.join("\n");
}

function scanUnreferencedAssets(files, referenceIndex) {
  const candidates = [];
  for (const relativePath of files) {
    const extension = path.extname(relativePath).toLowerCase();
    if (!assetExtensions.has(extension)) continue;
    if (publicOrGeneratedAssetPrefixes.some((prefix) => relativePath.startsWith(prefix))) continue;
    const normalizedPath = relativePath.toLowerCase();
    const fileName = path.basename(relativePath).toLowerCase();
    const stem = fileName.slice(0, -extension.length);
    const referenced = referenceIndex.includes(normalizedPath)
      || referenceIndex.includes(fileName)
      || (stem.length >= 8 && referenceIndex.includes(stem));
    if (!referenced) {
      candidates.push({
        path: relativePath,
        reason: "asset path, filename, and stable stem were not found in source references",
      });
    }
  }
  return candidates;
}

function safeReadText(relativePath) {
  try {
    return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
  } catch {
    return null;
  }
}

function renderMarkdown(reportData) {
  const lines = [
    "# Code Hygiene Audit",
    "",
    "Mode: report-only.",
    "",
    `- Scanned files: ${reportData.summary.scannedFiles}`,
    `- TODO/FIXME/HACK/XXX findings: ${reportData.summary.todoFindings}`,
    `- Duplicate asset groups: ${reportData.summary.duplicateAssetGroups}`,
    `- Duplicate asset files: ${reportData.summary.duplicateAssetFiles}`,
    `- Unreferenced asset candidates: ${reportData.summary.unreferencedAssetCandidates}`,
    "",
    "This audit is advisory until the cleanup campaign classifies or removes findings.",
    "",
  ];
  if (reportData.findings.todos.length > 0) {
    lines.push("## TODO Samples", "");
    for (const finding of reportData.findings.todos.slice(0, 25)) {
      lines.push(`- ${finding.path}:${finding.line} ${finding.kind} [${finding.category}]`);
    }
    lines.push("");
  }
  if (reportData.findings.duplicateAssets.length > 0) {
    lines.push("## Duplicate Asset Groups", "");
    for (const group of reportData.findings.duplicateAssets.slice(0, 25)) {
      lines.push(`- ${group.files.length} files, ${group.size} bytes: ${group.files.join(", ")}`);
    }
    lines.push("");
  }
  if (reportData.findings.unreferencedAssets.length > 0) {
    lines.push("## Unreferenced Asset Candidates", "");
    for (const finding of reportData.findings.unreferencedAssets.slice(0, 25)) {
      lines.push(`- ${finding.path}`);
    }
    lines.push("");
  }
  return `${lines.join("\n")}\n`;
}

function runSelfTest() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "code-hygiene-audit-"));
  try {
    fs.writeFileSync(path.join(tmp, "a.ts"), "// TODO(code-hygiene:test): classify this\n");
    fs.writeFileSync(path.join(tmp, "one.svg"), "<svg />\n");
    fs.writeFileSync(path.join(tmp, "two.svg"), "<svg />\n");
    fs.writeFileSync(path.join(tmp, "referenced.png"), "png\n");
    fs.writeFileSync(path.join(tmp, "unused.png"), "unused\n");
    fs.appendFileSync(path.join(tmp, "a.ts"), "const icon = 'referenced.png';\n");
    const oldRoot = process.cwd();
    process.chdir(tmp);
    const localFiles = ["a.ts", "one.svg", "two.svg", "referenced.png", "unused.png"];
    const todos = scanTodosWithRoot(tmp, localFiles);
    const duplicates = scanDuplicateAssetsWithRoot(tmp, localFiles);
    const sourceIndex = fs.readFileSync(path.join(tmp, "a.ts"), "utf8").toLowerCase();
    const unreferenced = scanUnreferencedAssetsWithRoot(tmp, localFiles, sourceIndex);
    process.chdir(oldRoot);
    if (todos.length !== 1 || todos[0].category !== "code-hygiene:test") {
      throw new Error("self-test failed to classify TODO comments");
    }
    if (duplicates.length !== 1 || duplicates[0].files.length !== 2) {
      throw new Error("self-test failed to detect duplicate assets");
    }
    if (!unreferenced.some((finding) => finding.path === "unused.png")) {
      throw new Error("self-test failed to detect unreferenced assets");
    }
    if (unreferenced.some((finding) => finding.path === "referenced.png")) {
      throw new Error("self-test reported a referenced asset");
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function scanUnreferencedAssetsWithRoot(testRoot, files, referenceIndex) {
  return files.flatMap((relativePath) => {
    const extension = path.extname(relativePath).toLowerCase();
    if (!assetExtensions.has(extension)) return [];
    const absolutePath = path.join(testRoot, relativePath);
    if (!fs.existsSync(absolutePath)) return [];
    const fileName = path.basename(relativePath).toLowerCase();
    const stem = fileName.slice(0, -extension.length);
    const referenced = referenceIndex.includes(relativePath.toLowerCase())
      || referenceIndex.includes(fileName)
      || (stem.length >= 8 && referenceIndex.includes(stem));
    return referenced ? [] : [{ path: relativePath }];
  });
}

function scanTodosWithRoot(testRoot, files) {
  return files.flatMap((relativePath) => {
    if (!sourceExtensions.has(path.extname(relativePath))) return [];
    const lines = fs.readFileSync(path.join(testRoot, relativePath), "utf8").split(/\r?\n/);
    return lines.flatMap((line, index) => {
      const match = line.match(todoPattern);
      if (!match) return [];
      return [{
        path: relativePath,
        line: index + 1,
        kind: match[1].toUpperCase(),
        category: match[2] || line.match(categoryPattern)?.[1] || "uncategorized",
        text: line.trim(),
      }];
    });
  });
}

function scanDuplicateAssetsWithRoot(testRoot, files) {
  const hashes = new Map();
  for (const relativePath of files) {
    if (!assetExtensions.has(path.extname(relativePath))) continue;
    const absolutePath = path.join(testRoot, relativePath);
    const hash = crypto.createHash("sha256").update(fs.readFileSync(absolutePath)).digest("hex");
    const group = hashes.get(hash) ?? { hash, size: fs.statSync(absolutePath).size, files: [] };
    group.files.push(relativePath);
    hashes.set(hash, group);
  }
  return [...hashes.values()].filter((group) => group.files.length > 1);
}
