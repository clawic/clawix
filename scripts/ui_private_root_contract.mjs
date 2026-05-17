import fs from "node:fs";
import path from "node:path";

const manifestRelativePath = "docs/ui/private-visual-validation.manifest.json";

export function privateRootAliasEntries(rootDir) {
  const manifestPath = path.join(rootDir, manifestRelativePath);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  return Array.isArray(manifest.rootAliases) ? manifest.rootAliases : [];
}

export function privateRootEnvForAlias(rootDir, alias) {
  const entry = privateRootAliasEntries(rootDir).find((candidate) => candidate?.alias === alias);
  if (!entry?.env) {
    throw new Error(`${manifestRelativePath}.rootAliases is missing ${alias}`);
  }
  const manifestPath = path.join(rootDir, manifestRelativePath);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (!Array.isArray(manifest.requiredRoots) || !manifest.requiredRoots.includes(entry.env)) {
    throw new Error(`${manifestRelativePath}.requiredRoots is missing ${entry.env}`);
  }
  return entry.env;
}
