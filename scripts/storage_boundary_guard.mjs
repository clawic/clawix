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
  ["macos/Sources/Clawix/Persistence/TranscriptionsRepository.swift", "frameworkGlobalChild(ClawixPersistentSurfacePaths.components.audio"],
  ["macos/Sources/Clawix/Audio/UserAudioBubble.swift", "framework audio catalog only"],
  ["macos/Sources/Clawix/QuickAsk/QuickAskSlashCommands.swift", "framework-owned snippets"],
  ["macos/Sources/Clawix/QuickAsk/QuickAskMentions.swift", "ClawJSFrameworkRecordsClient.shared.listSnippets"],
  ["macos/Sources/Clawix/Dictation/WhisperPromptStore.swift", "framework-owned snippets"],
  ["macos/Sources/Clawix/Dictation/Enhancement/PromptLibrary.swift", "framework-owned snippets"],
  ["macos/Sources/Clawix/Providers/FeatureRouting.swift", "framework stores only opaque account refs"],
  ["macos/Sources/Clawix/Agents/AgentStore.swift", "production path delegates reads and writes"],
  ["macos/Sources/Clawix/Agents/AgentStore.swift", "frameworkClient.listAgents"],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", "Source of truth lives in ClawJS"],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", "frameworkClient?.upsertSkillRecord"],
  ["macos/Sources/Clawix/HostActions/HostActionPolicy.swift", "Requires explicit host approval."],
  ["macos/Sources/Clawix/MacUtilities/MacUtilitiesController.swift", "HostActionPolicy.authorize"],
  ["macos/Sources/Clawix/ScreenTools/ScreenToolService.swift", "HostActionPolicy.authorize"],
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
  ["macos/Sources/Clawix/Persistence/TranscriptionsRepository.swift", ["Application Support/Clawix/dictation-audio", "Application Support/Clawix/dictation-audio-debug"]],
  ["macos/Sources/Clawix/AppState/MessageSending.swift", ["AudioMessageStore.shared.ingest", "legacy store is still the source of truth"]],
  ["macos/Sources/Clawix/AppState/EngineHost.swift", ["AudioMessageStore.shared.data", "Fall through to legacy"]],
  ["macos/Sources/Clawix/Audio/UserAudioBubble.swift", ["AudioMessageStore.shared.data", "Fall through to legacy"]],
  ["macos/Helpers/Bridged/Sources/clawix-bridge/main.swift", ["AudioMessageStore.shared.ingest", "AudioMessageStore.shared.data", "Fall through to legacy"]],
  ["macos/Sources/Clawix/QuickAsk/QuickAskSlashCommands.swift", ["UserDefaults.standard.set", "UserDefaults.standard.data", "quickAsk.slashCommandsCustom"]],
  ["macos/Sources/Clawix/QuickAsk/QuickAskMentions.swift", ["UserDefaults.standard.set", "UserDefaults.standard.data", "quickAsk.mentionPromptsCustom"]],
  ["macos/Sources/Clawix/Dictation/WhisperPromptStore.swift", ["UserDefaults.standard.set", "UserDefaults.standard.data", "dictation.whisperPrompts"]],
  ["macos/Sources/Clawix/Dictation/Enhancement/PromptLibrary.swift", ["dictation.enhancement.customPrompts"]],
  ["macos/Sources/Clawix/Providers/FeatureRouting.swift", ["providerAccountKey", "modelKey(", "providerEnabledKey", "feature.<feature>.providerAccountId", "feature.<feature>.modelId", "provider.<provider>.enabled"]],
  ["macos/Sources/Clawix/Agents/AgentStore.swift", ["Filesystem source-of-truth"]],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", ["UserDefaults.standard", "ClawixSkillsActiveByScope", "ClawixSkillsUserCatalog", "bridge frames v6", "seed data + UserDefaults"]],
  ["docs/persistent-surface-clawix.manifest.json", [
    "Application Support/Clawix/Apps",
    "Application Support/Clawix/Design",
    "Application Support/Clawix/dictation-audio",
    "Application Support/Clawix/audio-meta.json",
    "quickAsk.slashCommandsCustom",
    "quickAsk.mentionPromptsCustom",
    "dictation.whisperPrompts",
    "dictation.enhancement.customPrompts",
    "feature.<feature>.providerAccountId",
    "feature.<feature>.modelId",
    "provider.<provider>.enabled",
    "ClawixSkillsActiveByScope",
    "ClawixSkillsUserCatalog",
  ]],
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
  ["claw.framework.audio", "~/.claw/audio"],
  ["claw.framework.snippets", "~/.claw/core.sqlite#snippets"],
  ["claw.framework.agents", "~/.claw/agents,~/.claw/personalities,~/.claw/skill-collections,~/.claw/connections"],
  ["claw.framework.skills", "~/.claw/core.sqlite#skills"],
  ["claw.framework.providerRouting", "~/.claw/core.sqlite#provider_routing,provider_settings"],
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

const hostActionAudit = nodes.get("clawix.hostActionAudit");
if (!hostActionAudit) {
  fail("persistent surface manifest is missing clawix.hostActionAudit");
} else {
  if (hostActionAudit.owner !== "clawix") fail("clawix.hostActionAudit owner must be clawix");
  if (hostActionAudit.path !== "~/Library/Application Support/Clawix/host-action-audit.jsonl") {
    fail("clawix.hostActionAudit path must be ~/Library/Application Support/Clawix/host-action-audit.jsonl");
  }
  if (hostActionAudit.storageClass !== "hostOperational") fail("clawix.hostActionAudit storageClass must be hostOperational");
  if (hostActionAudit.canonicality !== "hostOnly") fail("clawix.hostActionAudit canonicality must be hostOnly");
}

for (const staleId of ["clawix.apps", "clawix.design", "clawix.audioCatalog", "clawix.audioCatalogMetadata", "clawix.dictationAudio"]) {
  if (nodes.has(staleId)) fail(`persistent surface manifest still exposes retired host-owned node ${staleId}`);
}

if (failures.length > 0) {
  console.error("Storage boundary guard failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("storage boundary guard passed");
