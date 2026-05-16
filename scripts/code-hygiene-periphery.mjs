import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const peripheryVersion = "3.7.4";
const outputJson = path.join(rootDir, "docs", "code-hygiene-periphery-report.json");
const outputMarkdown = path.join(rootDir, "docs", "code-hygiene-periphery-report.md");
const scanArgs = [
  "scan",
  "--format",
  "json",
  "--retain-public",
  "--retain-swift-ui-previews",
  "--retain-objc-accessible",
  "--retain-codable-properties",
];

if (process.argv.includes("--self-test")) {
  const summary = summarizePeriphery([
    { kind: "unused", location: "Sources/App/File.swift:1:1" },
    { kind: "redundant public accessibility", location: "Sources/App/Public.swift:2:1" },
  ]);
  if (summary.totalFindings !== 2 || summary.issueTypes.unused !== 1) {
    throw new Error("Periphery summary self-test failed");
  }
  console.log("code hygiene Periphery self-test passed");
  process.exit(0);
}

fs.mkdirSync(path.dirname(outputJson), { recursive: true });

const packagePaths = findSwiftPackages(rootDir);
const binary = findPeripheryBinary();
const report = {
  schemaVersion: 1,
  program: "code-hygiene",
  tool: "periphery",
  toolVersion: peripheryVersion,
  mode: "report-only",
  runner: "scripts/code-hygiene-periphery.mjs",
  status: "scanned",
  generatedAt: new Date().toISOString(),
  install: {
    homebrew: "brew install periphery",
    source: "https://github.com/peripheryapp/periphery/releases/tag/3.7.4",
  },
  scanArgs,
  retainRules: {
    publicApi: true,
    swiftUiPreviews: true,
    objcAccessible: true,
    codableProperties: true,
  },
  externalPending: [],
  packagePaths,
  packages: [],
  summary: {
    packageCount: packagePaths.length,
    scannedPackages: 0,
    failedPackages: 0,
    packagesWithFindings: 0,
    totalFindings: 0,
    issueTypes: {},
  },
};

if (!binary) {
  report.status = "external-pending";
  report.externalPending.push({
    id: "periphery-binary-unavailable",
    message: "Periphery is not installed on PATH. Install the pinned Homebrew formula before calibration scans.",
  });
} else {
  const version = spawnSync(binary, ["version"], { encoding: "utf8" });
  const versionText = `${version.stdout ?? ""}${version.stderr ?? ""}`;
  if (!versionText.includes(peripheryVersion)) {
    report.status = "external-pending";
    report.externalPending.push({
      id: "periphery-version-mismatch",
      message: `Expected Periphery ${peripheryVersion}; got ${versionText.trim() || "unknown version"}.`,
    });
  } else {
    for (const packagePath of packagePaths) {
      const packageReport = scanPackage(binary, packagePath);
      report.packages.push(packageReport);
      if (packageReport.status === "scanned") report.summary.scannedPackages += 1;
      if (packageReport.status === "failed") report.summary.failedPackages += 1;
      if (packageReport.summary.totalFindings > 0) report.summary.packagesWithFindings += 1;
      report.summary.totalFindings += packageReport.summary.totalFindings;
      for (const [kind, count] of Object.entries(packageReport.summary.issueTypes)) {
        report.summary.issueTypes[kind] = (report.summary.issueTypes[kind] ?? 0) + count;
      }
    }
  }
}

fs.writeFileSync(outputJson, `${JSON.stringify(report, null, 2)}\n`);
fs.writeFileSync(outputMarkdown, renderMarkdown(report));
console.log(`code hygiene Periphery report wrote ${path.relative(rootDir, outputJson)}`);

function findPeripheryBinary() {
  const result = spawnSync("sh", ["-lc", "command -v periphery"], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : "";
}

function findSwiftPackages(startDir) {
  const ignored = new Set([".build", ".claude", ".git", "build", "DerivedData", "node_modules"]);
  const packages = [];
  walk(startDir);
  return packages.map((entry) => path.relative(rootDir, entry)).sort();

  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (ignored.has(entry.name)) continue;
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
      } else if (entry.name === "Package.swift") {
        packages.push(path.dirname(fullPath));
      }
    }
  }
}

function scanPackage(binary, packagePath) {
  const result = spawnSync(binary, scanArgs, {
    cwd: path.join(rootDir, packagePath),
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  const stdout = result.stdout?.trim() ?? "";
  const stderr = result.stderr?.trim() ?? "";
  let findings = [];
  let parseError = "";
  try {
    findings = collectFindings(stdout ? JSON.parse(stdout) : []);
  } catch (error) {
    parseError = error instanceof Error ? error.message : String(error);
  }
  return {
    path: packagePath,
    status: result.status === 0 && !parseError ? "scanned" : "failed",
    exitCode: result.status,
    summary: summarizePeriphery(findings),
    errorSummary: parseError || firstLines(stderr, 8),
  };
}

function collectFindings(payload) {
  if (Array.isArray(payload)) return payload;
  for (const key of ["results", "issues", "findings", "warnings"]) {
    if (Array.isArray(payload?.[key])) return payload[key];
  }
  return [];
}

function summarizePeriphery(findings) {
  const issueTypes = {};
  for (const finding of findings) {
    const kind = String(finding.kind ?? finding.type ?? finding.name ?? "unknown");
    issueTypes[kind] = (issueTypes[kind] ?? 0) + 1;
  }
  return {
    totalFindings: findings.length,
    issueTypes,
  };
}

function firstLines(value, limit) {
  return value.split(/\r?\n/).filter(Boolean).slice(0, limit).join("\n");
}

function renderMarkdown(report) {
  const lines = [
    "# Code Hygiene Periphery Report",
    "",
    `- Generated: ${report.generatedAt}`,
    `- Tool: Periphery ${report.toolVersion}`,
    `- Status: ${report.status}`,
    `- Mode: ${report.mode}`,
    `- Packages: ${report.summary.packageCount}`,
    `- Scanned packages: ${report.summary.scannedPackages}`,
    `- Failed packages: ${report.summary.failedPackages}`,
    `- Total findings: ${report.summary.totalFindings}`,
    "",
    "This report does not authorize automatic deletion. Swift public API, SwiftUI previews, Objective-C-accessible declarations, and Codable properties are retained by default.",
  ];
  if (report.externalPending.length > 0) {
    lines.push("", "## External Pending", "");
    for (const item of report.externalPending) lines.push(`- ${item.id}: ${item.message}`);
  }
  return `${lines.join("\n")}\n`;
}
