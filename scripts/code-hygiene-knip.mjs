import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const jsonPath = valueAfter("--json");
const markdownPath = valueAfter("--markdown");
const isSelfTest = args.includes("--self-test");
const knipVersion = "6.14.0";
const knipCwd = fs.existsSync(path.join(rootDir, "web", "package.json"))
  ? path.join(rootDir, "web")
  : rootDir;
const configPath = fs.existsSync(path.join(knipCwd, "knip.json"))
  ? path.join(knipCwd, "knip.json")
  : path.join(rootDir, "knip.json");

if (isSelfTest) {
  const summary = summarizeKnip({
    issues: [
      {
        file: "package.json",
        dependencies: [{ name: "left-pad" }],
        devDependencies: [],
        files: [],
        exports: [],
        types: [],
        enumMembers: [],
        duplicates: [],
        unlisted: [],
        unresolved: [],
        binaries: [],
        catalog: [],
        namespaceMembers: [],
        optionalPeerDependencies: []
      },
      {
        file: "src/a.ts",
        dependencies: [],
        devDependencies: [],
        files: [{ name: "src/a.ts" }],
        exports: [{ name: "unusedExport" }],
        types: [],
        enumMembers: [{ name: "FutureMode" }],
        duplicates: [],
        unlisted: [],
        unresolved: [],
        binaries: [],
        catalog: [],
        namespaceMembers: [],
        optionalPeerDependencies: []
      }
    ]
  });
  if (summary.totalIssues !== 4 || summary.issueTypes.dependencies !== 1 || summary.issueTypes.enumMembers !== 1) {
    throw new Error("Knip summary self-test failed");
  }
  console.log("code hygiene Knip self-test passed");
  process.exit(0);
}

const result = spawnSync(
  "npm",
  [
    "--silent",
    "exec",
    `--package=knip@${knipVersion}`,
    "--",
    "knip",
    "--config",
    configPath,
    "--reporter",
    "json",
    "--no-exit-code"
  ],
  { cwd: knipCwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }
);

if (result.error) throw result.error;
if (result.status !== 0) {
  process.stderr.write(result.stderr);
  process.stderr.write(result.stdout);
  process.exit(result.status ?? 1);
}

const output = result.stdout.trim();
const knipJson = output ? JSON.parse(output) : { issues: [] };
const summary = summarizeKnip(knipJson);
const report = {
  schemaVersion: 1,
  program: "code-hygiene",
  tool: "knip",
  toolVersion: knipVersion,
  generatedAt: new Date().toISOString(),
  mode: "report-only",
  config: path.relative(rootDir, configPath),
  cwd: path.relative(rootDir, knipCwd) || ".",
  summary
};

if (jsonPath) fs.writeFileSync(path.resolve(rootDir, jsonPath), `${JSON.stringify(report, null, 2)}\n`);
if (markdownPath) fs.writeFileSync(path.resolve(rootDir, markdownPath), renderMarkdown(report));
if (!jsonPath && !markdownPath) console.log(JSON.stringify(report, null, 2));

function valueAfter(flag) {
  const index = args.indexOf(flag);
  return index === -1 ? null : args[index + 1] ?? null;
}

function summarizeKnip(knipJson) {
  const issueTypes = {};
  const files = new Set();
  let totalIssues = 0;
  for (const issue of knipJson.issues ?? []) {
    if (issue.file) files.add(issue.file);
    for (const [key, value] of Object.entries(issue)) {
      if (key === "file" || !Array.isArray(value)) continue;
      const count = value.length;
      if (count === 0) continue;
      issueTypes[key] = (issueTypes[key] ?? 0) + count;
      totalIssues += count;
    }
  }
  return {
    filesWithIssues: files.size,
    totalIssues,
    issueTypes,
    topFiles: topIssueFiles(knipJson.issues ?? [])
  };
}

function topIssueFiles(issues) {
  return issues
    .map((issue) => {
      const issueCounts = {};
      let total = 0;
      for (const [key, value] of Object.entries(issue)) {
        if (key === "file" || !Array.isArray(value) || value.length === 0) continue;
        issueCounts[key] = value.length;
        total += value.length;
      }
      return {
        file: issue.file,
        totalIssues: total,
        issueCounts
      };
    })
    .filter((entry) => entry.file && entry.totalIssues > 0)
    .sort((left, right) => right.totalIssues - left.totalIssues || left.file.localeCompare(right.file))
    .slice(0, 20);
}

function renderMarkdown(report) {
  const lines = [
    "# Code Hygiene Knip Report",
    "",
    "Mode: report-only.",
    "",
    `- Tool version: ${report.toolVersion}`,
    `- Config: ${report.config}`,
    `- Working directory: ${report.cwd}`,
    `- Files with issues: ${report.summary.filesWithIssues}`,
    `- Total issues: ${report.summary.totalIssues}`,
    "",
    "## Issue Types",
    ""
  ];
  for (const [type, count] of Object.entries(report.summary.issueTypes).sort()) {
    lines.push(`- ${type}: ${count}`);
  }
  lines.push("", "## Top Files", "");
  for (const entry of report.summary.topFiles ?? []) {
    const counts = Object.entries(entry.issueCounts).map(([type, count]) => `${type}:${count}`).join(", ");
    lines.push(`- ${entry.file}: ${entry.totalIssues} (${counts})`);
  }
  lines.push("", "This report does not authorize automatic deletion; cleanup still requires category review.");
  return `${lines.join("\n")}\n`;
}
