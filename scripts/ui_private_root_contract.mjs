import fs from "node:fs";
import path from "node:path";

const manifestRelativePath = "docs/ui/private-visual-validation.manifest.json";

function readManifest(rootDir) {
  const manifestPath = path.join(rootDir, manifestRelativePath);
  return JSON.parse(fs.readFileSync(manifestPath, "utf8"));
}

export function privateRootAliasEntries(rootDir, options = {}) {
  const manifest = readManifest(rootDir);
  const requiredEntries = Array.isArray(manifest.rootAliases)
    ? manifest.rootAliases.map((entry) => ({ ...entry, required: true }))
    : [];
  if (!options.includeOptional) return requiredEntries;
  const optionalEntries = Array.isArray(manifest.optionalRootAliases)
    ? manifest.optionalRootAliases.map((entry) => ({ ...entry, required: false }))
    : [];
  return [...requiredEntries, ...optionalEntries];
}

export function privateRootEnvForAlias(rootDir, alias) {
  const entry = privateRootAliasEntries(rootDir, { includeOptional: true }).find((candidate) => candidate?.alias === alias);
  if (!entry?.env) {
    throw new Error(`${manifestRelativePath}.rootAliases or optionalRootAliases is missing ${alias}`);
  }
  const manifest = readManifest(rootDir);
  if (entry.required && (!Array.isArray(manifest.requiredRoots) || !manifest.requiredRoots.includes(entry.env))) {
    throw new Error(`${manifestRelativePath}.requiredRoots is missing ${entry.env}`);
  }
  return entry.env;
}
