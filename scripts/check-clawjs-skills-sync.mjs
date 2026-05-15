import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const projectedDir = path.join(rootDir, "skills");
const canonicalDir = process.env.CLAWJS_SKILLS_DIR
  ? path.resolve(process.env.CLAWJS_SKILLS_DIR)
  : path.resolve(rootDir, "..", "..", "clawjs", "skills");

const requiredSkills = [
  "constitution-drift-audit",
  "architecture-drift-repair",
  "adr-to-guardrail",
  "decision-map-maintenance",
  "naming-surface-audit",
  "surface-registry-alignment",
  "cli-agent-surface-work",
  "source-file-boundary-refactor",
  "canonical-catalog-expansion",
  "data-storage-boundary-review",
  "host-boundary-review",
  "secrets-boundary-review",
  "integration-qa-lab",
  "host-dependent-validation",
  "performance-investigation",
  "public-hygiene-review",
  "docs-alignment-update",
  "code-review-risk",
  "commit-hygiene-public",
];

function hashFile(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function parseFrontmatter(text, relativePath, errors) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    errors.push(`${relativePath} is missing YAML frontmatter`);
    return null;
  }
  const fields = new Map();
  for (const line of match[1].split("\n")) {
    const field = line.match(/^([a-zA-Z][a-zA-Z0-9_-]*):\s*(.*)$/);
    if (field) {
      fields.set(field[1], field[2]);
    }
  }
  for (const key of ["name", "description", "keywords"]) {
    if (!fields.has(key) || fields.get(key) === "") {
      errors.push(`${relativePath} frontmatter is missing ${key}`);
    }
  }
  return fields;
}

const errors = [];

for (const skill of requiredSkills) {
  const projected = path.join(projectedDir, skill, "SKILL.md");
  if (!fs.existsSync(projected)) {
    errors.push(`missing projected skill ${skill}`);
    continue;
  }
  const fields = parseFrontmatter(
    fs.readFileSync(projected, "utf8"),
    path.relative(rootDir, projected),
    errors,
  );
  if (fields && fields.get("name") !== skill) {
    errors.push(`${path.relative(rootDir, projected)} frontmatter name must be ${skill}`);
  }
}

if (!fs.existsSync(canonicalDir)) {
  if (errors.length > 0) {
    console.error("Clawix skill projection check failed:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }
  console.log(`ClawJS canonical skills not found at ${canonicalDir}; projection presence check passed`);
  process.exit(0);
}

for (const entry of fs.readdirSync(projectedDir, { withFileTypes: true })) {
  if (!entry.isDirectory()) {
    continue;
  }
  const projected = path.join(projectedDir, entry.name, "SKILL.md");
  const canonical = path.join(canonicalDir, entry.name, "SKILL.md");
  if (!fs.existsSync(projected)) {
    errors.push(`skills/${entry.name} is missing SKILL.md`);
    continue;
  }
  parseFrontmatter(fs.readFileSync(projected, "utf8"), path.relative(rootDir, projected), errors);
  if (!fs.existsSync(canonical)) {
    errors.push(`projected skill ${entry.name} has no canonical ClawJS skill`);
    continue;
  }
  if (hashFile(projected) !== hashFile(canonical)) {
    errors.push(`projected skill ${entry.name} differs from canonical ClawJS skill`);
  }
}

if (errors.length > 0) {
  console.error("Clawix skill projection check failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Clawix skill projection check passed");
