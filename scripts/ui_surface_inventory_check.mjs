#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  if (!object) return [];
  const value = object[field];
  if (value === undefined && !nonEmpty) return [];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function walk(relativeDir) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return [];
  const result = [];
  const stack = [relativeDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const absolute = path.join(rootDir, current);
    for (const entry of fs.readdirSync(absolute, { withFileTypes: true })) {
      const relativePath = path.posix.join(current, entry.name);
      if (entry.isDirectory()) {
        if ([".build", "build", "dist", "node_modules", "Resources", "Assets.xcassets", "Fonts", "Mocks"].includes(entry.name)) {
          continue;
        }
        stack.push(relativePath);
      } else {
        result.push(relativePath);
      }
    }
  }
  return result.sort();
}

function globToRegExp(glob) {
  let output = "^";
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index];
    const next = glob[index + 1];
    if (char === "*" && next === "*") {
      output += ".*";
      index += 1;
    } else if (char === "*") {
      output += "[^/]*";
    } else {
      output += char.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
    }
  }
  return new RegExp(`${output}$`);
}

function platformFor(relativePath) {
  if (relativePath.startsWith("macos/")) return "macos";
  if (relativePath.startsWith("ios/")) return "ios";
  if (relativePath.startsWith("apps/macos/")) return "macos";
  if (relativePath.startsWith("apps/ios/")) return "ios";
  if (relativePath.startsWith("android/")) return "android";
  if (relativePath.startsWith("web/")) return "web";
  return "unknown";
}

function isVisibleCandidate(relativePath) {
  const extension = path.extname(relativePath);
  if (![".swift", ".kt", ".tsx"].includes(extension)) return false;
  const basename = path.basename(relativePath);
  if (/ViewModel|PersistentSurfaceRegistry|Intents/.test(basename)) return false;
  const visibleName = /(View|Screen|Page|Panel|Sidebar|Composer|Button|Card|Menu|Sheet|Toast|Search|Terminal|Surface|Icon|Chrome|Bubble|Timeline|Shimmer|Picker|Controls|Overlay|Header|Footer|Segmented|Field|Row)/;
  if (extension === ".tsx") return true;
  const text = fs.readFileSync(path.join(rootDir, relativePath), "utf8");
  if (extension === ".swift") {
    return visibleName.test(basename) || /:\s*(some\s+)?View\b|NSView|NSPanel|NSWindow|LucideIcon|Image\(lucide/.test(text);
  }
  return visibleName.test(basename) || /@Composable/.test(text);
}

const registry = readJson("docs/ui/pattern-registry/patterns.registry.json");
const patternIds = new Set(requireArray(registry, "docs/ui/pattern-registry/patterns.registry.json", "patterns"));
const patternPlatforms = new Map();
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  patternPlatforms.set(patternId, new Set(requireArray(pattern, patternPath, "platforms")));
}

const debt = readJson("docs/ui/debt.baseline.json");
const debtIds = new Set(requireArray(debt, "docs/ui/debt.baseline.json", "entries").map((entry) => entry.id));

const protectedSurfaces = readJson("docs/ui/protected-surfaces.registry.json");
const protectedIds = new Set(requireArray(protectedSurfaces, "docs/ui/protected-surfaces.registry.json", "surfaces", { nonEmpty: false }).map((entry) => entry.id));

const exceptions = readJson("docs/ui/exceptions.registry.json");
const exceptionIds = new Set(requireArray(exceptions, "docs/ui/exceptions.registry.json", "exceptions", { nonEmpty: false }).map((entry) => entry.id));

const inventoryPath = "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
requireFields(inventory, inventoryPath, ["schemaVersion", "status", "policy", "reviewAfter", "sourceRoots", "coverage"]);
if (inventory?.reviewAfter && inventory.reviewAfter < today) {
  fail(`${inventoryPath}.reviewAfter expired on ${inventory.reviewAfter}`);
}

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredSourceRoots = [
  "macos/Sources/Clawix",
  "ios/Sources/Clawix",
  "apps/macos/Sources",
  "apps/ios/Sources",
  "android/app/src/main/java/com/example/clawix/android",
  "web/src",
];
const sourceRoots = requireArray(inventory, inventoryPath, "sourceRoots");
for (const sourceRoot of sourceRoots) {
  if (sourceRoot.startsWith("/") || sourceRoot.startsWith("~/") || sourceRoot.includes("\\") || sourceRoot.includes("..") || sourceRoot.startsWith("file://") || /^[A-Z]:\\/.test(sourceRoot)) {
    fail(`${inventoryPath}.sourceRoots must use safe relative paths`);
    continue;
  }
  if (platformFor(sourceRoot) === "unknown") fail(`${inventoryPath}.sourceRoots includes ungoverned root ${sourceRoot}`);
  if (!fs.existsSync(path.join(rootDir, sourceRoot))) fail(`${inventoryPath}.sourceRoots missing root ${sourceRoot}`);
}
for (const sourceRoot of requiredSourceRoots) {
  if (!sourceRoots.includes(sourceRoot)) fail(`${inventoryPath}.sourceRoots must include ${sourceRoot}`);
}
const platformCoverage = new Set();
const coverage = requireArray(inventory, inventoryPath, "coverage");
const compiledCoverage = [];
const coverageIds = new Set();
for (const [index, entry] of coverage.entries()) {
  const label = `${inventoryPath}.coverage[${index}]`;
  requireFields(entry, label, ["id", "platform", "scopes", "classification", "reason"]);
  if (!entry) continue;
  if (coverageIds.has(entry.id)) fail(`${label}.id duplicates ${entry.id}`);
  coverageIds.add(entry.id);
  platformCoverage.add(entry.platform);
  if (!requiredPlatforms.includes(entry.platform)) fail(`${label}.platform is not governed`);
  const scopes = requireArray(entry, label, "scopes");
  const excludeScopes = requireArray(entry, label, "excludeScopes", { nonEmpty: false });
  if (!["pattern", "debt", "exception", "protected"].includes(entry.classification)) {
    fail(`${label}.classification must be pattern, debt, exception, or protected`);
  }
  if (entry.classification === "pattern") {
    for (const patternId of requireArray(entry, label, "patterns")) {
      if (!patternIds.has(patternId)) fail(`${label}.patterns references unknown pattern ${patternId}`);
      const platforms = patternPlatforms.get(patternId) || new Set();
      if (platforms.size > 0 && !platforms.has(entry.platform)) {
        fail(`${label}.patterns references ${patternId}, which is not declared for ${entry.platform}`);
      }
    }
  }
  if (entry.classification === "debt") {
    for (const debtId of requireArray(entry, label, "debtIds")) {
      if (!debtIds.has(debtId)) fail(`${label}.debtIds references unknown debt ${debtId}`);
    }
  }
  if (entry.classification === "protected") {
    for (const surfaceId of requireArray(entry, label, "surfaceIds")) {
      if (!protectedIds.has(surfaceId)) fail(`${label}.surfaceIds references unknown protected surface ${surfaceId}`);
    }
  }
  if (entry.classification === "exception") {
    for (const exceptionId of requireArray(entry, label, "exceptionIds")) {
      if (!exceptionIds.has(exceptionId)) fail(`${label}.exceptionIds references unknown exception ${exceptionId}`);
    }
  }
  compiledCoverage.push({
    id: entry.id,
    platform: entry.platform,
    classification: entry.classification,
    scopes: scopes.map((scope) => [scope, globToRegExp(scope)]),
    excludeScopes: excludeScopes.map((scope) => [scope, globToRegExp(scope)]),
  });
}

for (const platform of requiredPlatforms) {
  if (!platformCoverage.has(platform)) fail(`${inventoryPath}.coverage must include ${platform}`);
}

const candidates = sourceRoots.flatMap(walk).filter(isVisibleCandidate);
const uncovered = [];
const ambiguous = [];
for (const candidate of candidates) {
  const platform = platformFor(candidate);
  const matches = compiledCoverage.filter((entry) => {
    if (entry.platform !== platform) return false;
    if (entry.excludeScopes.some(([, pattern]) => pattern.test(candidate))) return false;
    return entry.scopes.some(([, pattern]) => pattern.test(candidate));
  });
  if (matches.length === 0) {
    uncovered.push(candidate);
  } else if (matches.length > 1) {
    ambiguous.push({ candidate, matches });
  }
}

if (uncovered.length > 0) {
  fail(
    [
      "visible UI candidates are not mapped in docs/ui/visible-surfaces.inventory.json",
      ...uncovered.slice(0, 80).map((candidate) => `  ${candidate}`),
      uncovered.length > 80 ? `  ...and ${uncovered.length - 80} more` : "",
    ].filter(Boolean).join("\n"),
  );
}

if (ambiguous.length > 0) {
  fail(
    [
      "visible UI candidates must map to exactly one inventory classification",
      ...ambiguous.slice(0, 80).map(({ candidate, matches }) => (
        `  ${candidate}: ${matches.map((entry) => `${entry.id}:${entry.classification}`).join(", ")}`
      )),
      ambiguous.length > 80 ? `  ...and ${ambiguous.length - 80} more` : "",
    ].filter(Boolean).join("\n"),
  );
}

if (errors.length > 0) {
  console.error("UI surface inventory check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI surface inventory check passed (${candidates.length} visible candidates)`);
