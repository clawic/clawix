import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const registryPath = path.join(rootDir, "docs/interface-surface-clawix.registry.json");
const matrixPath = path.join(rootDir, "docs/interface-matrix.md");
const violations = [];

function fail(message) {
  violations.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readOptional(relativePath) {
  const absolutePath = path.join(rootDir, relativePath);
  return fs.existsSync(absolutePath) ? fs.readFileSync(absolutePath, "utf8") : "";
}

function requireSnippet(relativePath, snippet) {
  if (!read(relativePath).includes(snippet)) {
    fail(`${relativePath} is missing required snippet: ${snippet}`);
  }
}

const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
if (registry.version !== 1) fail("interface registry version must be 1");
if (registry.sourceConversationId !== "019e2727-cf2b-7c41-9feb-1fd2b5c77554") {
  fail("interface registry must reference the source conversation id");
}

const allowedStatuses = new Set(["stable", "dev-only", "removed"]);
const requiredFeatureFlags = new Set([
  "voiceToText",
  "quickAsk",
  "secrets",
  "mcp",
  "localModels",
  "browserUsage",
  "git",
  "remoteMesh",
  "publishing",
  "apps",
  "design",
  "life",
  "skills",
  "skillCollections",
  "claw",
  "identity",
  "telegram",
  "screenTools",
  "macUtilities",
  "databaseWorkbench",
  "marketplace",
  "calendar",
  "contacts",
  "database",
  "index",
  "iotHome",
  "agents",
  "openCode",
  "simulators",
]);
const requiredIds = new Set([
  "bridge.v1",
  "deepLinks.session",
  "deepLinks.authCallback",
  "pairing.qrJson",
  "providers.routing",
  "connections",
]);

const seenIds = new Set();
const seenFeatureFlags = new Set();
for (const surface of registry.surfaces ?? []) {
  if (!surface.id) fail("each interface surface needs an id");
  if (seenIds.has(surface.id)) fail(`duplicate interface surface id: ${surface.id}`);
  seenIds.add(surface.id);

  if (!allowedStatuses.has(surface.status)) {
    fail(`${surface.id} has invalid status ${JSON.stringify(surface.status)}`);
  }
  if (surface.status === "stable") {
    for (const field of ["owner", "humanSurface", "programmaticSurface", "storageOwner", "validation"]) {
      if (!surface[field]) fail(`${surface.id} stable surface is missing ${field}`);
    }
  }
  if (surface.status === "experimental" || surface.status === "beta") {
    fail(`${surface.id} uses forbidden ambiguous status ${surface.status}`);
  }
  if (surface.featureFlag) seenFeatureFlags.add(surface.featureFlag);
}

for (const id of requiredIds) {
  if (!seenIds.has(id)) fail(`interface registry is missing required surface id ${id}`);
}
for (const featureFlag of requiredFeatureFlags) {
  if (!seenFeatureFlags.has(featureFlag)) {
    fail(`interface registry is missing current AppFeature ${featureFlag}`);
  }
}

function validateLifeRegistryResource(relativePath) {
  const envelope = JSON.parse(read(relativePath));
  const invalid = (envelope.entries ?? []).filter((entry) => !allowedStatuses.has(entry.status));
  if (invalid.length > 0) {
    fail(`${relativePath} has non-v1 life statuses: ${invalid.map((entry) => `${entry.id}:${entry.status}`).join(", ")}`);
  }
  const stable = (envelope.entries ?? []).filter((entry) => entry.status === "stable");
  const devOnly = (envelope.entries ?? []).filter((entry) => entry.status === "dev-only");
  if (stable.length === 0) fail(`${relativePath} must expose at least one stable life vertical`);
  if (devOnly.length === 0) fail(`${relativePath} must classify non-v1 life verticals as dev-only instead of provisional`);
}

validateLifeRegistryResource("macos/Sources/Clawix/Resources/life-registry.json");
validateLifeRegistryResource("ios/Sources/Clawix/Life/Resources/life-registry.json");

for (const snippet of [
  "This matrix is the Clawix gate for ADR 0007",
  "`stable`",
  "`dev-only`",
  "EXTERNAL PENDING",
  "clawix://session/<sessionId>",
  "clawix://auth/callback/<provider>",
  "JSON payload with `v`, `host`, `port`, `token`",
  "`HostActionPolicy` approval/audit API",
]) {
  requireSnippet("docs/interface-matrix.md", snippet);
}

const staleContractTargets = [
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift",
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md",
  "packages/ClawixCore/Sources/ClawixCore/BridgeModels.swift",
  "packages/ClawixCore/Tests/ClawixCoreTests/BridgeFrameRoundTripTests.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/EngineHost.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/BridgeSession.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/BridgeSessionNIO.swift",
  "android/app/src/main/java/com/example/clawix/android/core/BridgeProtocol.kt",
  "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameEncoding.kt",
  "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameDecoding.kt",
  "android/app/src/main/java/com/example/clawix/android/bridge/BridgeClient.kt",
  "android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt",
  "ios/Sources/Clawix/Bridge/BridgeClient.swift",
  "ios/Sources/Clawix/Pairing/ShortCodePairingFlow.swift",
  "ios/Sources/Clawix/Pairing/PeerPairingView.swift",
  "web/src/bridge/frames.ts",
  "web/src/bridge/client.ts",
  "web/src/screens/shell/version-mismatch.tsx",
  "web/tests/unit/wire.test.ts",
  "windows/CLAUDE.md",
  "windows/Clawix.Core/BridgeBody.cs",
  "windows/Clawix.Core/BridgeFrame.cs",
  "windows/Clawix.Core/BridgeFrameDecoder.cs",
  "windows/Clawix.Core/BridgeFrameEncoder.cs",
  "windows/Clawix.Core/ClientKind.cs",
  "windows/Clawix.Core/Models/WireSession.cs",
  "windows/Clawix.Bridged/Program.cs",
  "windows/Clawix.Engine/BridgeSession.cs",
  "windows/Clawix.Engine/Pairing/PairingService.cs",
  "windows/Clawix.Tests/BridgeProtocolTests.cs",
  "docs/interface-matrix.md",
  "docs/persistent-surface-clawix.manifest.json",
  "macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift",
  "macos/Sources/Clawix/FeatureFlags.swift",
  "macos/Sources/Clawix/AppState/Routes.swift",
  "macos/Sources/Clawix/AppState/DeepLinks.swift",
  "macos/Sources/Clawix/Providers/OAuth/OAuthStrategy.swift",
  "macos/Sources/Clawix/Providers/OAuth/AnthropicOAuthStrategy.swift",
  "macos/Sources/Clawix/Sidebar/SidebarView+Projects.swift",
  "macos/Sources/Clawix/ContentChrome.swift",
  "macos/Sources/Clawix/SidebarChatContextMenu.swift",
  "macos/Sources/Clawix/SidebarView.swift",
  "macos/Sources/Clawix/Pairing/PairingScreen.swift",
  "macos/scripts/build_app.sh",
  "macos/Tests/ClawixMeshTests/PersistentSurfaceRegistryTests.swift",
  "macos/Helpers/Bridged/Sources/clawix-bridge/main.swift",
  "macos/Helpers/Bridged/Sources/clawix-bridge/WebStaticServer.swift",
  "macos/Helpers/Bridged/Tests/e2e_bridge_daemon.py",
  "macos/Helpers/Bridged/Tests/e2e_opencode_daemon.py",
];

const stalePatterns = [
  { pattern: "bridgeProtocolVersion", reason: "bridge wire version is bridgeSchemaVersion" },
  { pattern: "BRIDGE_PROTOCOL_VERSION", reason: "bridge wire version is BRIDGE_SCHEMA_VERSION" },
  { pattern: "\"protocolVersion\"", reason: "bridge wire envelope field is schemaVersion" },
  { pattern: "\"schemaVersion\":5", reason: "stable bridge schema version must be 1" },
  { pattern: "\"schemaVersion\":8", reason: "stable bridge schema version must be 1" },
  { pattern: "Schema version 5", reason: "stable bridge schema version must be 1" },
  { pattern: "Schema version 8", reason: "stable bridge schema version must be 1" },
  { pattern: "127.0.0.1:7777", reason: "stable bridge port must be 24080" },
  { pattern: "port = 7777", reason: "stable bridge port must be 24080" },
  { pattern: "(ushort)7777", reason: "stable bridge port must be 24080" },
  { pattern: "@SerialName(\"ios\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.ios", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Ios", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"ios\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "case ios", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"ios\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"ios\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "sendPrompt", reason: "wire send frame is sendMessage" },
  { pattern: "WireChat", reason: "wire vocabulary uses Session" },
  { pattern: "chatUpdated", reason: "wire vocabulary uses Session" },
  { pattern: "macName", reason: "host display field is hostDisplayName" },
  { pattern: "clawix://chat", reason: "session deep link is clawix://session/<sessionId>" },
  { pattern: "clawix://oauth-callback", reason: "OAuth deep link is clawix://auth/callback/<provider>" },
  { pattern: "clawix://pair/{token}", reason: "stable pairing contract is JSON QR" },
  { pattern: "clawix://pair?", reason: "stable pairing contract is JSON QR" },
  { pattern: "FeatureTier.beta", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "FeatureTier.experimental", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "case beta", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "case experimental", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "FeatureFlags.beta", reason: "use explicit stable/dev-only classification" },
  { pattern: "FeatureFlags.experimental", reason: "use explicit stable/dev-only classification" },
];

for (const relativePath of staleContractTargets) {
  const text = readOptional(relativePath);
  if (!text) continue;
  for (const { pattern, reason } of stalePatterns) {
    if (text.includes(pattern)) {
      fail(`${relativePath} contains stale v1 surface ${JSON.stringify(pattern)}: ${reason}`);
    }
  }
}

for (const relativePath of [
  "macos/Sources/Clawix/Life/LifeRegistry.swift",
  "ios/Sources/Clawix/Life/LifeRegistry.swift",
]) {
  const text = read(relativePath);
  for (const pattern of ["case alpha", "case planned", "case deprecated"]) {
    if (text.includes(pattern)) {
      fail(`${relativePath} contains stale life status ${JSON.stringify(pattern)}`);
    }
  }
  if (!text.includes("entries(includeDevOnly: false)")) {
    fail(`${relativePath} must default LifeRegistry.entries to stable-only surfaces`);
  }
}

const clawixProtocol = read("macos/Sources/Clawix/AgentBackend/ClawixProtocol.swift");
for (const pattern of ["EXPERIMENTAL.", "experimental API methods", "requires experimentalApi capability"]) {
  if (clawixProtocol.includes(pattern)) {
    fail(`ClawixProtocol.swift contains ambiguous experimental wording ${JSON.stringify(pattern)}`);
  }
}

const bridgeProtocol = read("packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift");
for (const pattern of ["legacy (v1-v5)", "legacyTypeTag", "encodeLegacyPayload", "decodeLegacy"]) {
  if (bridgeProtocol.includes(pattern)) {
    fail(`BridgeProtocol.swift contains ambiguous legacy bridge helper ${JSON.stringify(pattern)}`);
  }
}
for (const pattern of [
  "clientKind: ClientKind?",
  "clientId: String?",
  "installationId: String?",
  "deviceId: String?",
  "decodeIfPresent(ClientKind.self, forKey: .clientKind)",
  "decodeIfPresent(String.self, forKey: .clientId)",
  "try c.encodeIfPresent(clientKind, forKey: .clientKind)",
]) {
  if (bridgeProtocol.includes(pattern)) {
    fail(`BridgeProtocol.swift keeps auth identity optional: ${JSON.stringify(pattern)}`);
  }
}

const bridgeProtocolDoc = read("packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md");
for (const snippet of [
  "The current schema version is `1`.",
  "`auth` `{ token, deviceName?, clientKind, clientId, installationId, deviceId }`",
]) {
  if (!bridgeProtocolDoc.includes(snippet)) {
    fail(`BridgeProtocol.md is missing auth v1 contract snippet ${JSON.stringify(snippet)}`);
  }
}

const databaseConnectionProfiles = read("macos/Sources/Clawix/Database/DatabaseConnectionProfiles.swift");
for (const pattern of ["case legacy", "compat-0.9.5", "return \"SSH 0.9.5\""]) {
  if (databaseConnectionProfiles.includes(pattern)) {
    fail(`DatabaseConnectionProfiles.swift exposes ambiguous legacy SSH option ${JSON.stringify(pattern)}`);
  }
}

if (fs.existsSync(path.join(rootDir, "macos/Sources/Clawix/Marketplace/MarketplaceScreenV2.swift"))) {
  fail("MarketplaceScreenV2.swift must not ship while Marketplace v1 is the registered public surface");
}

const clawJSProfileClient = read("macos/Sources/Clawix/ClawJS/ClawJSProfileClient.swift");
if (clawJSProfileClient.includes("marketplace/2.0.0")) {
  fail("ClawJSProfileClient.swift must not describe the Profile client as marketplace/2.0.0");
}

const bridgeModels = read("packages/ClawixCore/Sources/ClawixCore/BridgeModels.swift");
for (const pattern of [
  "legacy payloads",
  "old peers",
  "Old peers",
  "old Mac",
  "Old Macs",
  "phased rollout",
  "pre-multi-runtime",
  "legacy badging",
  "v7 peers",
  "v8 reference",
]) {
  if (bridgeModels.includes(pattern)) {
    fail(`BridgeModels.swift contains compatibility-only wording ${JSON.stringify(pattern)}`);
  }
}

if (violations.length > 0) {
  console.error("Interface surface guard failed:");
  for (const violation of violations) console.error(`- ${violation}`);
  process.exit(1);
}

console.log("Interface surface guard passed");
