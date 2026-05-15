import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const ignoredDirs = new Set(["node_modules", "dist", ".git", ".build", "build", ".next", ".tmp", "coverage", "artifacts", "test-results", "playwright-report"]);
const allowedUnscopedPackages = new Set(["clawix"]);
const allowedBins = new Set(["clawix"]);

function listPackageFiles(targetPath) {
  const stat = fs.statSync(targetPath);
  if (stat.isFile()) return path.basename(targetPath) === "package.json" ? [targetPath] : [];
  return fs.readdirSync(targetPath, { withFileTypes: true }).flatMap((entry) => {
    if (ignoredDirs.has(entry.name)) return [];
    const next = path.join(targetPath, entry.name);
    if (entry.isDirectory()) return listPackageFiles(next);
    return entry.name === "package.json" ? [next] : [];
  });
}

function relative(filePath) {
  return path.relative(rootDir, filePath);
}

function binKeys(bin) {
  if (typeof bin === "string") return [path.basename(bin)];
  if (bin && typeof bin === "object" && !Array.isArray(bin)) return Object.keys(bin);
  return [];
}

const violations = [];
for (const file of listPackageFiles(rootDir)) {
  const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
  if (parsed.name && parsed.name !== "__APP_NAME__" && !String(parsed.name).startsWith("@clawix/") && !allowedUnscopedPackages.has(parsed.name)) {
    violations.push(`${relative(file)} package name "${parsed.name}" must be @clawix/* or the approved clawix product-host CLI package`);
  }
  for (const bin of binKeys(parsed.bin)) {
    if (!allowedBins.has(bin)) violations.push(`${relative(file)} exposes unapproved bin "${bin}"`);
  }
}

if (violations.length > 0) {
  console.error("Package surface guard failed:");
  for (const violation of violations) console.error(`- ${violation}`);
  process.exit(1);
}

console.log("Package surface guard passed");
