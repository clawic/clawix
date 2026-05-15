#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const failures = [];

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function fail(message) {
  failures.push(message);
}

const requiredSnippets = [
  ["macos/Sources/Clawix/Apps/AppsStore.swift", "ClawixPersistentSurfacePaths.frameworkGlobalChild(\"apps\""],
  ["macos/Sources/Clawix/Design/DesignStore.swift", "ClawixPersistentSurfacePaths.frameworkGlobalChild(\"design\""],
  ["macos/Sources/Clawix/Design/EditorStore.swift", "ClawixPersistentSurfacePaths.frameworkGlobalChild(\"design\""],
  ["ios/Sources/Clawix/Design/DesignStore.swift", ".appendingPathComponent(frameworkRootName"],
  ["ios/Sources/Clawix/Design/EditorStore.swift", ".appendingPathComponent(frameworkRootName"],
  ["macos/Sources/Clawix/Apps/AGENT_CONTRACT.md", "~/.claw/apps/"],
  ["docs/interface-matrix.md", "Reject App Support as canonical Apps path"],
  ["docs/interface-matrix.md", "Framework workspace storage"],
];

for (const [relativePath, snippet] of requiredSnippets) {
  if (!read(relativePath).includes(snippet)) {
    fail(`${relativePath} is missing required storage-boundary snippet ${JSON.stringify(snippet)}`);
  }
}

const forbiddenByPath = new Map([
  ["macos/Sources/Clawix/Apps/AppsStore.swift", ["Application Support/Clawix/Apps", "Library/Application Support/Clawix/Apps"]],
  ["macos/Sources/Clawix/Apps/AppRecord.swift", ["Application Support/Clawix/Apps", "Library/Application Support/Clawix/Apps"]],
  ["macos/Sources/Clawix/Apps/AGENT_CONTRACT.md", ["Application Support/Clawix/Apps", "Library/Application Support/Clawix/Apps"]],
  ["macos/Sources/Clawix/Design/DesignStore.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["macos/Sources/Clawix/Design/EditorStore.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["macos/Sources/Clawix/Design/EditorDocument.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/Design/DesignStore.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/Design/EditorStore.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/Design/EditorDocument.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["docs/persistent-surface-clawix.manifest.json", ["Application Support/Clawix/Apps", "Application Support/Clawix/Design"]],
]);

for (const [relativePath, patterns] of forbiddenByPath) {
  const text = read(relativePath);
  for (const pattern of patterns) {
    if (text.includes(pattern)) {
      fail(`${relativePath} still contains retired Clawix-owned framework storage path ${JSON.stringify(pattern)}`);
    }
  }
}

const manifest = JSON.parse(read("docs/persistent-surface-clawix.manifest.json"));
const nodes = new Map(manifest.nodes.map((node) => [node.id, node]));
for (const [id, expectedPath] of [
  ["claw.framework.apps", "~/.claw/apps"],
  ["claw.framework.design", "~/.claw/design"],
]) {
  const node = nodes.get(id);
  if (!node) {
    fail(`persistent surface manifest is missing ${id}`);
    continue;
  }
  if (node.owner !== "claw") fail(`${id} owner must be claw`);
  if (node.path !== expectedPath) fail(`${id} path must be ${expectedPath}`);
  if (node.storageClass !== "frameworkGlobal") fail(`${id} storageClass must be frameworkGlobal`);
  if (node.canonicality !== "frameworkCanonical") fail(`${id} canonicality must be frameworkCanonical`);
}

for (const staleId of ["clawix.apps", "clawix.design"]) {
  if (nodes.has(staleId)) fail(`persistent surface manifest still exposes retired host-owned node ${staleId}`);
}

if (failures.length > 0) {
  console.error("Storage boundary guard failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("storage boundary guard passed");
