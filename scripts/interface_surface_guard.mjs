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

function listFiles(relativeDir, extension, output = []) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return output;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      listFiles(relativePath, extension, output);
    } else if (entry.isFile() && relativePath.endsWith(extension)) {
      output.push(relativePath);
    }
  }
  return output;
}

function requireSnippet(relativePath, snippet) {
  if (!read(relativePath).includes(snippet)) {
    fail(`${relativePath} is missing required snippet: ${snippet}`);
  }
}

function countOccurrences(text, token) {
  return text.split(token).length - 1;
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

const v1ClosureSurfaceRequirements = {
  publishing: {
    matrix: ["| Publishing |", "`claw content brand|destination|campaign|entry|approval|publish`", "live channel publish `EXTERNAL PENDING`"],
    registry: ["claw content brand|destination|campaign|entry|approval|publish", "content Relay read/write routes", "EXTERNAL PENDING"],
  },
  database: {
    matrix: ["| Database and Workbench |", "`claw database ...`", "`claw db <collection> ...`", "`DatabaseApiClient`"],
    registry: ["claw database ...", "claw db <collection> ...", "DatabaseApiClient"],
  },
  index: {
    matrix: ["| Index/Search |", "`claw sessions index`", "`claw search rebuild`", "Codex read-only mirror tests"],
    registry: ["claw sessions index", "claw search rebuild", "Codex read-only mirror tests"],
  },
  marketplace: {
    matrix: ["| Marketplace |", "`claw marketplace choice`", "payment/live installs `EXTERNAL PENDING`"],
    registry: ["claw marketplace choice", "marketplace identity/profile/vertical APIs", "EXTERNAL PENDING"],
  },
  iotHome: {
    matrix: ["| IoT/Home |", "`claw iot homes|things|state|lights|climate|scenes|automations|approvals`", "physical devices `EXTERNAL PENDING`"],
    registry: ["claw iot homes|things|state|lights|climate|scenes|automations|approvals", "IoT Relay routes", "EXTERNAL PENDING"],
  },
  calendar: {
    matrix: ["| Calendar |", "`claw calendar list|get|create|update|delete`", "`claw time calendar`", "signed-host permission broker"],
    registry: ["claw calendar list|get|create|update|delete", "claw time calendar", "signed-host-permission-broker", "EXTERNAL PENDING"],
  },
  contacts: {
    matrix: ["| Contacts |", "`claw contacts list|get|create|update|archive`", "signed-host permission broker"],
    registry: ["claw contacts list|get|create|update|archive", "signed-host-permission-broker", "EXTERNAL PENDING"],
  },
  life: {
    matrix: ["| Life verticals |", "`claw signals catalog|seed-catalog|observe|list|delete`", "native/provider adapters `EXTERNAL PENDING`"],
    registry: ["claw signals catalog|seed-catalog|observe|list|delete", "signal resource registry/runtime contract", "EXTERNAL PENDING"],
  },
};

const matrixText = read("docs/interface-matrix.md");
for (const [id, requirement] of Object.entries(v1ClosureSurfaceRequirements)) {
  const surface = (registry.surfaces ?? []).find((entry) => entry.id === id);
  if (!surface) {
    fail(`interface registry is missing v1 closure surface ${id}`);
    continue;
  }
  if (surface.status !== "stable") fail(`${id} must be stable in the v1 closure registry`);
  const registryText = `${surface.programmaticSurface ?? ""}\n${surface.storageOwner ?? ""}\n${surface.validation ?? ""}`;
  for (const snippet of requirement.registry) {
    if (!registryText.includes(snippet)) fail(`${id} registry row is missing v1 closure snippet ${JSON.stringify(snippet)}`);
  }
  for (const snippet of requirement.matrix) {
    if (!matrixText.includes(snippet)) fail(`docs/interface-matrix.md is missing ${id} v1 closure snippet ${JSON.stringify(snippet)}`);
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
  "JSON payload with `v`, `host`, `port`, `token`, `shortCode`, `hostDisplayName`",
  "`HostActionPolicy` approval/audit API",
]) {
  requireSnippet("docs/interface-matrix.md", snippet);
}
requireSnippet("docs/naming-style-guide.md", "`shortCode`, `hostDisplayName`");

const pairingSurface = (registry.surfaces ?? []).find((entry) => entry.id === "pairing.qrJson");
if (!pairingSurface) {
  fail("interface registry is missing pairing.qrJson");
} else {
  const pairingSurfaceText = `${pairingSurface.programmaticSurface ?? ""}\n${pairingSurface.validation ?? ""}`;
  for (const snippet of ["shortCode", "hostDisplayName", "port 24080"]) {
    if (!pairingSurfaceText.includes(snippet)) {
      fail(`pairing.qrJson registry row is missing stable QR snippet ${JSON.stringify(snippet)}`);
    }
  }
}

const staleContractTargets = [
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift",
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md",
  "packages/ClawixCore/Sources/ClawixCore/BridgeModels.swift",
  "packages/ClawixCore/Tests/ClawixCoreTests/BridgeFrameRoundTripTests.swift",
  "cli/lib/pair.js",
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
  "linux/app/src-tauri/src/daemon_client.rs",
  "linux/app/src/lib/daemon_ws.ts",
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
  "windows/Clawix.App/Views/Settings/GeneralPage.xaml",
  "windows/Clawix.App/Views/Settings/UpdatesPage.xaml",
  "windows/Clawix.Tests/BridgeProtocolTests.cs",
  "STANDARDS.md",
  "playbooks/macos/settings.md",
  "docs/naming-style-guide.md",
  "docs/interface-matrix.md",
  "docs/interface-surface-clawix.registry.json",
  "docs/persistent-surface-clawix.manifest.json",
  "macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift",
  "macos/Sources/Clawix/FeatureFlags.swift",
  "macos/scripts/e2e_feature_flags_fixture.sh",
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
  { pattern: "@SerialName(\"mac\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "@SerialName(\"ipad\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "@SerialName(\"android\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "@SerialName(\"linux\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "@SerialName(\"windows\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "@SerialName(\"web\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.ios", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Ios", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.mac", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Mac", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.ipad", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Ipad", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.android", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Android", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.linux", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Linux", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.windows", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Windows", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.web", reason: "clientKind roles are companion/desktop" },
  { pattern: "ClientKind.Web", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"ios\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"mac\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"ipad\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"android\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"linux\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"windows\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "JsonStringEnumMemberName(\"web\")", reason: "clientKind roles are companion/desktop" },
  { pattern: "case ios", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"ios\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"mac\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"ipad\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"android\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"linux\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"windows\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "\"clientKind\":\"web\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"ios\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"mac\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"ipad\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"android\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"linux\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"windows\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "clientKind: \"web\"", reason: "clientKind roles are companion/desktop" },
  { pattern: "sendPrompt", reason: "wire send frame is sendMessage" },
  { pattern: "WireChat", reason: "wire vocabulary uses Session" },
  { pattern: "chatUpdated", reason: "wire vocabulary uses Session" },
  { pattern: "macName", reason: "host display field is hostDisplayName" },
  { pattern: "clawix://chat", reason: "session deep link is clawix://session/<sessionId>" },
  { pattern: "clawix://oauth-callback", reason: "OAuth deep link is clawix://auth/callback/<provider>" },
  { pattern: "clawix://pair/{token}", reason: "stable pairing contract is JSON QR" },
  { pattern: "clawix://pair/<token>", reason: "stable pairing contract is JSON QR" },
  { pattern: "clawix://pair?", reason: "stable pairing contract is JSON QR" },
  { pattern: "FeatureTier.beta", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "FeatureTier.experimental", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "experimental Mica", reason: "visible v1 settings must use stable/dev-only labels" },
  { pattern: "beta channel", reason: "visible v1 settings must use stable/dev-only labels" },
  { pattern: "case beta", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "case experimental", reason: "v1 surfaces must be stable, dev-only, or removed" },
  { pattern: "FeatureFlags.beta", reason: "use explicit stable/dev-only classification" },
  { pattern: "FeatureFlags.experimental", reason: "use explicit stable/dev-only classification" },
  { pattern: "experimental pages", reason: "visible v1 surfaces must use stable/dev-only labels" },
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
  "docs/persistent-surface-clawix.manifest.json",
  "macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift",
]) {
  const text = read(relativePath);
  if (text.includes('"clawix.protocol.bridge"')) {
    fail(`${relativePath} must use clawix.protocol.bridge.v1, not the unversioned bridge protocol id`);
  }
  if (!text.includes("clawix.protocol.bridge.v1")) {
    fail(`${relativePath} must expose clawix.protocol.bridge.v1`);
  }
}

for (const relativePath of [
  "linux/app/src-tauri/src/daemon_client.rs",
  "linux/app/src/lib/daemon_ws.ts",
]) {
  const text = read(relativePath);
  for (const pattern of ["\"body\": {", "frame.body"]) {
    if (text.includes(pattern)) {
      fail(`${relativePath} must use flat bridge v1 frames, found ${JSON.stringify(pattern)}`);
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
for (const pattern of ["let experimentalApi", "experimentalApi: true", "wire key remains", "legacy; subsumed"]) {
  if (clawixProtocol.includes(pattern)) {
    fail(`ClawixProtocol.swift must expose stable local v1 names for upstream wire fields: ${JSON.stringify(pattern)}`);
  }
}

const bridgedBackendRPC = read("macos/Helpers/Bridged/Sources/clawix-bridge/BackendRPC.swift");
const bridgedMain = read("macos/Helpers/Bridged/Sources/clawix-bridge/main.swift");
for (const [relativePath, source] of [
  ["macos/Helpers/Bridged/Sources/clawix-bridge/BackendRPC.swift", bridgedBackendRPC],
  ["macos/Helpers/Bridged/Sources/clawix-bridge/main.swift", bridgedMain],
]) {
  for (const pattern of ["let experimentalApi", "experimentalApi: true", "personality: nil"]) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must expose stable local v1 names for upstream wire fields: ${JSON.stringify(pattern)}`);
    }
  }
}

const upstreamExtensionWireKey = "experimentalApi";
const allowedUpstreamExtensionWireKeyCounts = new Map([
  ["macos/Sources/Clawix/AgentBackend/ClawixProtocol.swift", 1],
  ["macos/Helpers/Bridged/Sources/clawix-bridge/BackendRPC.swift", 1],
  ["macos/Tests/ClawixMeshTests/ClawixProtocolEncodingTests.swift", 1],
]);
const upstreamExtensionWireKeyFiles = [
  ...listFiles("macos", ".swift"),
  ...listFiles("ios", ".swift"),
  ...listFiles("android", ".kt"),
  ...listFiles("windows", ".cs"),
  ...listFiles("docs", ".md"),
  ...listFiles("docs", ".json"),
];
for (const relativePath of upstreamExtensionWireKeyFiles) {
  const count = countOccurrences(read(relativePath), upstreamExtensionWireKey);
  if (count === 0) continue;
  const expected = allowedUpstreamExtensionWireKeyCounts.get(relativePath);
  if (expected !== count) {
    fail(`${relativePath} must not expose ${upstreamExtensionWireKey}; only stable local extensionFields names may use the upstream wire key`);
  }
}
for (const [relativePath, expected] of allowedUpstreamExtensionWireKeyCounts) {
  const count = countOccurrences(read(relativePath), upstreamExtensionWireKey);
  if (count !== expected) {
    fail(`${relativePath} must contain exactly ${expected} upstream ${upstreamExtensionWireKey} wire-key mapping`);
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
  "pairingPayload(qrJson: String, bearer: String)",
  "case qrJson, bearer",
  "bearer: try c.decode(String.self, forKey: .bearer)",
  "try c.encode(bearer, forKey: .bearer)",
  "decodeIfPresent(ClientKind.self, forKey: .clientKind)",
  "decodeIfPresent(String.self, forKey: .clientId)",
  "try c.encodeIfPresent(clientKind, forKey: .clientKind)",
]) {
  if (bridgeProtocol.includes(pattern)) {
    fail(`BridgeProtocol.swift keeps auth identity optional: ${JSON.stringify(pattern)}`);
  }
}

for (const [relativePath, patterns] of [
  ["windows/Clawix.Engine/IEngineHost.cs", ["ChatChanged"]],
  ["windows/Clawix.Bridged/DaemonEngineHost.cs", ["ChatChanged", "chat / message surface", "ChatSnapshotFromBackend"]],
  ["windows/Clawix.Bridged/DaemonEngineHost.Events.cs", ["ChatSnapshotFromBackend"]],
  ["windows/Clawix.Tests/InMemoryEngineHost.cs", ["ChatChanged"]],
]) {
  const source = read(relativePath);
  for (const pattern of patterns) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must use session bridge vocabulary: ${JSON.stringify(pattern)}`);
    }
  }
}

const bridgeProtocolDoc = read("packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.md");
for (const snippet of [
  "The current schema version is `1`.",
  "`auth` `{ token, deviceName?, clientKind, clientId, installationId, deviceId }`",
  "`pairingPayload` `{ qrJson, token, shortCode }`",
]) {
  if (!bridgeProtocolDoc.includes(snippet)) {
    fail(`BridgeProtocol.md is missing auth v1 contract snippet ${JSON.stringify(snippet)}`);
  }
}

const linuxDaemonClient = read("linux/app/src-tauri/src/daemon_client.rs");
for (const snippet of [
  '"v": BRIDGE_SCHEMA_VERSION',
  '"host": pairing_host()',
  '"port": DEFAULT_PORT',
  '"token": &token',
]) {
  if (!linuxDaemonClient.includes(snippet)) {
    fail(`linux daemon pairing QR is missing stable payload snippet ${JSON.stringify(snippet)}`);
  }
}
for (const pattern of [
  'pub bearer: String',
  '"bearer":"',
  '"bearer":',
  '"host":"local"',
]) {
  if (linuxDaemonClient.includes(pattern)) {
    fail(`linux daemon pairing QR contains stale payload field ${JSON.stringify(pattern)}`);
  }
}

const cliPairSource = read("cli/lib/pair.js");
for (const pattern of ["includeShortCode: false", "omits shortCode from the QR", "shortCode is intentionally omitted from the QR"]) {
  if (cliPairSource.includes(pattern)) {
    fail(`CLI pairing QR must include the stable shortCode field, found ${JSON.stringify(pattern)}`);
  }
}
const cliPairTest = read("cli/test/pair.test.js");
for (const snippet of ["includes shortCode in QR payloads", "shortCode: 'ABC-DEF-GHJ'"]) {
  if (!cliPairTest.includes(snippet)) {
    fail(`CLI pairing tests must cover stable QR shortCode field ${JSON.stringify(snippet)}`);
  }
}
for (const pattern of ["omits shortCode from QR payloads", "includeShortCode: false"]) {
  if (cliPairTest.includes(pattern)) {
    fail(`CLI pairing tests must not preserve shortCode omission ${JSON.stringify(pattern)}`);
  }
}

for (const [relativePath, source] of [
  ["linux/app/src-tauri/src/lib.rs", read("linux/app/src-tauri/src/lib.rs")],
  ["linux/app/src-tauri/src/daemon_client.rs", linuxDaemonClient],
  ["linux/app/src/lib/daemon_ws.ts", read("linux/app/src/lib/daemon_ws.ts")],
  ["linux/app/src/views/ChatView.tsx", read("linux/app/src/views/ChatView.tsx")],
  ["linux/app/src/views/QuickAskHUD.tsx", read("linux/app/src/views/QuickAskHUD.tsx")],
]) {
  for (const pattern of ["send_prompt", "open_chat", "chat_id", "activeChatId"]) {
    if (source.includes(pattern)) {
      fail(`${relativePath} exposes stale Linux bridge command/session vocabulary ${JSON.stringify(pattern)}`);
    }
  }
}

for (const [relativePath, requiredSnippets, staleSnippets] of [
  [
    "android/app/src/main/java/com/example/clawix/android/core/BridgeProtocol.kt",
    ["PairingPayload(val qrJson: String, val token: String, val shortCode: String)"],
    ["PairingPayload(val qrJson: String, val bearer: String)"],
  ],
  [
    "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameEncoding.kt",
    ['b.put("token", body.token)', 'b.put("shortCode", body.shortCode)'],
    ['b.put("bearer", body.bearer)'],
  ],
  [
    "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameDecoding.kt",
    ['obj.requireString("token")', 'obj.requireString("shortCode")'],
    ['obj.requireString("bearer")'],
  ],
  [
    "android/app/src/main/java/com/example/clawix/android/core/PairingPayload.kt",
    ["val coordinatorUrl: String? = null", "val irohNodeId: String? = null"],
    ["clawix://pair"],
  ],
  [
    "android/app/src/main/java/com/example/clawix/android/bridge/Credentials.kt",
    ["val coordinatorUrl: String? = null", "val irohNodeId: String? = null", "KEY_COORDINATOR_URL", "KEY_IROH_NODE_ID"],
    ["macName"],
  ],
  [
    "web/src/bridge/frames.ts",
    ["token: z.string(),", "shortCode: z.string(),"],
    ["bearer: z.string(),"],
  ],
  [
    "windows/Clawix.Core/BridgeBody.cs",
    ["PairingPayload(string QrJson, string Token, string ShortCode)"],
    ["PairingPayload(string QrJson, string Bearer)"],
  ],
  [
    "windows/Clawix.Core/BridgeFrameEncoder.cs",
    ['writer.WriteString("token", pp.Token);', 'writer.WriteString("shortCode", pp.ShortCode);'],
    ['writer.WriteString("bearer", pp.Bearer);'],
  ],
  [
    "windows/Clawix.Core/BridgeFrameDecoder.cs",
    ['GetStr("token")', 'GetStr("shortCode")'],
    ['GetStr("bearer")'],
  ],
  [
    "windows/Clawix.Tests/PairingTests.cs",
    ['Assert.Equal(24080, root.GetProperty("port").GetInt32());', 'Assert.False(root.TryGetProperty("bearer", out _));', 'Assert.DoesNotContain("clawix://pair", json);'],
    [],
  ],
]) {
  const source = read(relativePath);
  for (const snippet of requiredSnippets) {
    if (!source.includes(snippet)) {
      fail(`${relativePath} is missing pairingPayload token contract snippet ${JSON.stringify(snippet)}`);
    }
  }
  for (const snippet of staleSnippets) {
    if (source.includes(snippet)) {
      fail(`${relativePath} contains stale pairingPayload bearer contract ${JSON.stringify(snippet)}`);
    }
  }
}

const androidBridgeRoundtripTest = read("android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt");
for (const snippet of [
  '"port":24080',
  '"shortCode":"ABC-234-XYZ"',
  '"hostDisplayName":"Studio Mac"',
]) {
  if (!androidBridgeRoundtripTest.includes(snippet)) {
    fail(`Android bridge round-trip pairing fixture is missing stable QR field ${JSON.stringify(snippet)}`);
  }
}
for (const pattern of [
  "roundtrip_chat_management_v2",
  "roundtrip_voice_v3",
  "roundtrip_images_v4",
  "legacy_payload",
  "legacy payload",
]) {
  if (androidBridgeRoundtripTest.includes(pattern)) {
    fail(`Android bridge round-trip tests must classify current frame families as v1, found ${JSON.stringify(pattern)}`);
  }
}

const deepLinkRoutingTests = read("macos/Tests/ClawixMeshTests/DeepLinkRoutingTests.swift");
for (const pattern of ["LegacyChatDeepLink", "LegacyOAuthCallbackDeepLink"]) {
  if (deepLinkRoutingTests.includes(pattern)) {
    fail(`Deep link routing tests must describe removed v1 routes as retired, found ${JSON.stringify(pattern)}`);
  }
}
for (const snippet of [
  "clawix://session/",
  "clawix://auth/callback/",
  "testRejectsRetiredChatDeepLink",
  "testRejectsRetiredOAuthCallbackDeepLink",
  "clawix://chat/",
  "clawix://oauth-callback/",
  "XCTAssertNil(ClawixDeepLink.parse(url))",
]) {
  if (!deepLinkRoutingTests.includes(snippet)) {
    fail(`Deep link routing tests must cover v1 accepted routes and retired-route rejection, missing ${JSON.stringify(snippet)}`);
  }
}

for (const relativePath of [
  "ios/Sources/Clawix/Bridge/Credentials.swift",
  "ios/Sources/Clawix/Bridge/BridgeClient.swift",
  "ios/Sources/Clawix/Pairing/ShortCodePairingFlow.swift",
]) {
  const source = read(relativePath);
  for (const phrase of ["Old pairings", "old pairings", "very old pairing payload", "v0.1.1", "long bearer", "bearer field"]) {
    if (source.includes(phrase)) {
      fail(`${relativePath} exposes stale iOS pairing wording ${JSON.stringify(phrase)}`);
    }
  }
}

for (const relativePath of [
  "macos/Sources/Clawix/Apps/AppBridgeMessageHandler.swift",
  "macos/Sources/Clawix/Apps/AGENT_CONTRACT.md",
]) {
  const source = read(relativePath);
  for (const phrase of ["v2 concern", "pre-approval for v2"]) {
    if (source.includes(phrase)) {
      fail(`${relativePath} must describe Apps tool dispatch without v2 placeholder wording ${JSON.stringify(phrase)}`);
    }
  }
}

for (const [relativePath, phrases] of [
  ["macos/Sources/Clawix/AgentBackend/ClawixClient.swift", ["place for v2"]],
  ["macos/Sources/Clawix/ClawJS/ClawJSSecretsClient.swift", ["Legacy brokered execute", "/execute/"]],
  ["macos/Sources/Clawix/Publishing/PublishingCalendarView.swift", ["lands in\n/// v2", "lands in v2"]],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", ["skills-v2 lands"]],
  ["macos/Sources/Clawix/ClawJS/ClawJSPublishingClient.swift", ["fields the v1", "endpoint in v2"]],
]) {
  const source = read(relativePath);
  for (const phrase of phrases) {
    if (source.includes(phrase)) {
      fail(`${relativePath} must describe current/future work without internal version placeholder wording ${JSON.stringify(phrase)}`);
    }
  }
}

for (const [relativePath, snippets] of [
  [
    "android/app/src/main/java/com/example/clawix/android/core/BridgeProtocol.kt",
    ["AudioRegister(val requestId: String", "AudioGetBytes(val requestId: String", "AudioListResult("],
  ],
  [
    "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameEncoding.kt",
    ["is BridgeBody.AudioRegister ->", "is BridgeBody.AudioBytesResult ->", 'b.put("chatCount", body.chatCount)'],
  ],
  [
    "android/app/src/main/java/com/example/clawix/android/core/BridgeFrameDecoding.kt",
    ['"audioRegister" -> BridgeBody.AudioRegister', '"audioBytesResult" -> BridgeBody.AudioBytesResult', '"audioDeleteResult" -> BridgeBody.AudioDeleteResult'],
  ],
  [
    "android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt",
    ["roundtrip_audio_catalog_v1", "BridgeBody.AudioRegister(", "BridgeBody.AudioDeleteResult("],
  ],
  [
    "windows/Clawix.Core/BridgeBody.cs",
    ["AudioRegister(string RequestId", "AudioGetBytes(string RequestId", "AudioListResult(string RequestId"],
  ],
  [
    "windows/Clawix.Core/BridgeFrameEncoder.cs",
    ['case BridgeBody.AudioRegister ar:', 'case BridgeBody.AudioBytesResult abr:', 'case BridgeBody.AudioDeleteResult adr:'],
  ],
  [
    "windows/Clawix.Core/BridgeFrameDecoder.cs",
    ['"audioRegister" => new BridgeBody.AudioRegister', '"audioBytesResult" => new BridgeBody.AudioBytesResult', '"audioDeleteResult" => new BridgeBody.AudioDeleteResult'],
  ],
  [
    "windows/Clawix.Tests/BridgeFixtureParityTests.cs",
    ["SwiftBridgeFixtures_DecodeAndRoundTrip", '"audioRegister"', '"audioDeleteResult"'],
  ],
  [
    "windows/scripts/dump-fixtures.sh",
    ['swift run BridgeFixtureExporter "$FIXTURES_OUT"'],
  ],
]) {
  const source = read(relativePath);
  for (const snippet of snippets) {
    if (!source.includes(snippet)) {
      fail(`${relativePath} is missing Windows v1 bridge audio fixture parity snippet ${JSON.stringify(snippet)}`);
    }
  }
}
for (const phrase of ["FixtureFileSynthesizer not yet wired", "manual export pending", "BridgeProtocolFixturesTests"]) {
  for (const relativePath of ["windows/scripts/dump-fixtures.sh", "windows/README.md", "windows/Clawix.Tests/Fixtures/README.md"]) {
    if (read(relativePath).includes(phrase)) {
      fail(`${relativePath} must use BridgeFixtureExporter without stale manual fixture wording ${JSON.stringify(phrase)}`);
    }
  }
}
const bridgeFixtureDir = path.join(rootDir, "windows/Clawix.Tests/Fixtures");
const bridgeFixtureCount = fs.readdirSync(bridgeFixtureDir).filter((entry) => entry.endsWith(".json")).length;
if (bridgeFixtureCount < 50) {
  fail(`windows/Clawix.Tests/Fixtures must include canonical Swift bridge JSON fixtures, found ${bridgeFixtureCount}`);
}

for (const relativePath of [
  "STANDARDS.md",
  "cli/README.md",
  "cli/bin/clawix.js",
  "cli/lib/doctor.js",
  "cli/lib/pair.js",
  "cli/lib/unpair.js",
  "android/app/src/main/java/com/example/clawix/android/bridge/Credentials.kt",
  "android/app/src/main/res/xml/network_security_config.xml",
  "windows/README.md",
  "windows/Clawix.App/Views/Settings/PairingPage.xaml",
]) {
  const source = read(relativePath);
  for (const phrase of ["pairing bearer", "Rotate bearer token", "bearer token authorises", "validates with bearer"]) {
    if (source.includes(phrase)) {
      fail(`${relativePath} exposes stale public pairing bearer wording ${JSON.stringify(phrase)}`);
    }
  }
}

for (const [relativePath, phrases] of [
  ["STANDARDS.md", ["QR code, bearer token"]],
  ["windows/Clawix.Engine/Pairing/PairingService.cs", ["stable bearer", "same store as the bearer", "bearer comparison"]],
  ["packages/ClawixEngine/Sources/ClawixEngine/PairingService.swift", ["stable bearer token"]],
  ["packages/ClawixEngine/Sources/ClawixEngine/BridgeSession.swift", ["stable bearer"]],
  ["macos/Sources/Clawix/AppState/SidebarItems.swift", ["host, port, bearer", "The bearer is"]],
]) {
  const source = read(relativePath);
  for (const phrase of phrases) {
    if (source.includes(phrase)) {
      fail(`${relativePath} exposes stale pairing bearer wording ${JSON.stringify(phrase)}`);
    }
  }
}

const databaseConnectionProfiles = read("macos/Sources/Clawix/Database/DatabaseConnectionProfiles.swift");
for (const pattern of ["case legacy", "compat-0.9.5", "return \"SSH 0.9.5\""]) {
  if (databaseConnectionProfiles.includes(pattern)) {
    fail(`DatabaseConnectionProfiles.swift exposes ambiguous legacy SSH option ${JSON.stringify(pattern)}`);
  }
}

const databaseWorkbenchSettingsPage = read("macos/Sources/Clawix/Database/DatabaseWorkbenchSettingsPage.swift");
if (databaseWorkbenchSettingsPage.includes("SSH client compatibility mode.")) {
  fail("DatabaseWorkbenchSettingsPage.swift must describe SSH selection as a protocol mode, not a compatibility mode");
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

const dictationHotkeyManager = read("macos/Sources/Clawix/Dictation/HotkeyManager.swift");
for (const pattern of ["migratedV2", "dictation.hotkey.migratedV2", "One-shot migration"]) {
  if (dictationHotkeyManager.includes(pattern)) {
    fail(`HotkeyManager.swift contains clean-v1 incompatible hotkey migration ${JSON.stringify(pattern)}`);
  }
}

const persistentSurfaceRegistry = read("macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift");
for (const pattern of ["hotkeyMigratedV2", "dictation.hotkey.migratedV2", "Dictation hotkey migrated v2"]) {
  if (persistentSurfaceRegistry.includes(pattern)) {
    fail(`PersistentSurfaceRegistry.swift exposes clean-v1 incompatible hotkey migration ${JSON.stringify(pattern)}`);
  }
}
for (const pattern of ["autoEnterDefaultsKey", "dictation.autoEnter", "Dictation auto enter"]) {
  if (persistentSurfaceRegistry.includes(pattern)) {
    fail(`PersistentSurfaceRegistry.swift exposes clean-v1 incompatible dictation auto-enter key ${JSON.stringify(pattern)}`);
  }
}

const appSource = read("macos/Sources/Clawix/App.swift");
if (appSource.includes("migrateLegacySidebarPrefs")) {
  fail("App.swift must not run pre-v1 sidebar preference migration");
}
if (appSource.includes("one-shot legacy")) {
  fail("App.swift must not describe audio catalog bootstrap as a legacy migration");
}

const bridgeDaemonSource = read("macos/Helpers/Bridged/Sources/clawix-bridge/main.swift");
for (const pattern of ["peerCount stays 0", "wiring it to `BridgeServer` lives in v1.x", "this iteration; wiring"]) {
  if (bridgeDaemonSource.includes(pattern)) {
    fail(`clawix-bridge heartbeat must not describe live peerCount as unresolved work: ${JSON.stringify(pattern)}`);
  }
}
if (!bridgeDaemonSource.includes("\"peerCount\": BridgeStats.shared.activeSessionCount")) {
  fail("clawix-bridge heartbeat must publish peerCount from BridgeStats.shared.activeSessionCount");
}

const appStateSource = read("macos/Sources/Clawix/AppState.swift");
for (const pattern of ["legacyRouteKey", "CLAWIX_REPLICA_ROUTE", "legacy daemons", "legacy flows"]) {
  if (appStateSource.includes(pattern)) {
    fail(`AppState.swift contains clean-v1 incompatible launch/session compatibility wording ${JSON.stringify(pattern)}`);
  }
}
if (!appStateSource.includes("let daemonBridgeEnabled = !fixtureActive && BackgroundBridgeService.shared.isActive")) {
  fail("AppState.swift must derive daemonBridgeEnabled from BackgroundBridgeService.shared.isActive");
}
if (!appStateSource.includes("ProcessInfo.processInfo.environment[\"CLAWIX_DISABLE_BACKEND\"] != \"1\",\n           !daemonBridgeEnabled")) {
  fail("AppState.swift must gate GUI-owned backend bootstrap behind !daemonBridgeEnabled");
}
if (!appStateSource.includes("ProcessInfo.processInfo.environment[\"CLAWIX_BRIDGE_DISABLE\"] != \"1\",\n           !daemonBridgeEnabled")) {
  fail("AppState.swift must gate GUI-owned BridgeServer bootstrap behind !daemonBridgeEnabled");
}
if (!appStateSource.includes("} else if daemonBridgeEnabled {") || !appStateSource.includes("DaemonBridgeClient(appState: self, pairing: pairing)")) {
  fail("AppState.swift must connect to the background bridge daemon instead of starting a second bridge when daemonBridgeEnabled");
}
const daemonBranchStart = appStateSource.indexOf("} else if daemonBridgeEnabled {");
const daemonBranchEnd = appStateSource.indexOf("// Auto-reload threads", daemonBranchStart);
const daemonBranch = daemonBranchStart >= 0 && daemonBranchEnd >= 0 ? appStateSource.slice(daemonBranchStart, daemonBranchEnd) : "";
if (daemonBranch.includes("BridgeServer(") || daemonBranch.includes("await clawix.bootstrap()")) {
  fail("daemonBridgeEnabled branch must not start a GUI-owned BridgeServer or backend");
}
for (const relativePath of listFiles("macos/Sources/Clawix", ".swift")) {
  if (relativePath === "macos/Sources/Clawix/AppState.swift") continue;
  const source = read(relativePath);
  if (source.includes("BridgeServer(")) {
    fail(`${relativePath} must not instantiate BridgeServer outside AppState's daemon-gated bootstrap`);
  }
  if (source.includes("ClawixService(")) {
    fail(`${relativePath} must not instantiate ClawixService outside AppState's daemon-gated bootstrap`);
  }
}

for (const [relativePath, source] of [
  ["macos/Sources/Clawix/Bridge/MeshStore.swift", read("macos/Sources/Clawix/Bridge/MeshStore.swift")],
  ["macos/Sources/Clawix/Bridge/MeshClient.swift", read("macos/Sources/Clawix/Bridge/MeshClient.swift")],
  ["macos/Sources/Clawix/AppState/ChatHydration.swift", read("macos/Sources/Clawix/AppState/ChatHydration.swift")],
]) {
  for (const pattern of ["legacy Swift bridge", "legacy daemons", "legacy synchronous rollout"]) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must describe daemon/in-process bridge boundaries without legacy compatibility wording`);
    }
  }
}

const sidebarItems = read("macos/Sources/Clawix/AppState/SidebarItems.swift");
for (const pattern of ["legacyBrowserStateKey", "legacyBrowserActiveKey", "BrowserTabs", "BrowserActiveTabId"]) {
  if (sidebarItems.includes(pattern)) {
    fail(`SidebarItems.swift contains clean-v1 incompatible browser-tab legacy key ${JSON.stringify(pattern)}`);
  }
}

const dictationCoordinator = read("macos/Sources/Clawix/Dictation/DictationCoordinator.swift");
for (const pattern of ["autoEnterDefaultsKey", "dictation.autoEnter"]) {
  if (dictationCoordinator.includes(pattern)) {
    fail(`DictationCoordinator.swift contains clean-v1 incompatible auto-enter migration ${JSON.stringify(pattern)}`);
  }
}

const autoSendKey = read("macos/Sources/Clawix/Dictation/AutoSendKey.swift");
if (autoSendKey.includes("dictation.autoEnter")) {
  fail("AutoSendKey.swift must not document pre-v1 auto-enter migration");
}

const dictationCoordinatorSource = read("macos/Sources/Clawix/Dictation/DictationCoordinator.swift");
for (const pattern of ["legacy `cloud` enum", "legacy implementation", "legacy cloud", "new routing"]) {
  if (dictationCoordinatorSource.includes(pattern)) {
    fail(`DictationCoordinator.swift must classify provider fallback as stable v1, not legacy: ${JSON.stringify(pattern)}`);
  }
}

const enhancementService = read("macos/Sources/Clawix/Dictation/Enhancement/EnhancementService.swift");
for (const pattern of ["legacy provider chain", "legacy chain", "legacy implementations", "new-routing", "new AIClient routing"]) {
  if (enhancementService.includes(pattern)) {
    fail(`EnhancementService.swift must classify provider fallback as stable v1, not legacy: ${JSON.stringify(pattern)}`);
  }
}

const sidebarView = read("macos/Sources/Clawix/SidebarView.swift");
for (const pattern of ["LegacySidebarOrganizationMode", "SidebarOrganizationMode", "migrateLegacySidebarPrefs"]) {
  if (sidebarView.includes(pattern)) {
    fail(`SidebarView.swift contains clean-v1 incompatible sidebar migration ${JSON.stringify(pattern)}`);
  }
}

const quickAskController = read("macos/Sources/Clawix/QuickAsk/QuickAskController.swift");
for (const pattern of ["legacyFrameKey", "quickAsk.panelFrame"]) {
  if (quickAskController.includes(pattern)) {
    fail(`QuickAskController.swift contains clean-v1 incompatible panel-frame fallback ${JSON.stringify(pattern)}`);
  }
}

const textInjector = read("macos/Sources/Clawix/Dictation/TextInjector.swift");
if (textInjector.includes("useAppleScriptPasteLegacy")) {
  fail("TextInjector.swift must not fall back to the pre-v1 AppleScript paste preference");
}
for (const pattern of ["useAppleScriptPasteLegacy", "UseAppleScriptPaste", "Legacy AppleScript paste preference"]) {
  if (persistentSurfaceRegistry.includes(pattern)) {
    fail(`PersistentSurfaceRegistry.swift exposes clean-v1 incompatible AppleScript paste legacy key ${JSON.stringify(pattern)}`);
  }
}
for (const pattern of ["legacyKeychainPurged", "clawix.legacyKeychainPurged.v1", "Legacy keychain purge gate"]) {
  if (persistentSurfaceRegistry.includes(pattern)) {
    fail(`PersistentSurfaceRegistry.swift exposes clean-v1 incompatible keychain purge gate ${JSON.stringify(pattern)}`);
  }
}

const appDelegateSource = read("macos/Sources/Clawix/App.swift");
if (appDelegateSource.includes("LegacyKeychainPurge.runOnce")) {
  fail("App.swift must not run pre-v1 Keychain cleanup at launch");
}
if (fs.existsSync(path.join(rootDir, "macos/Sources/Clawix/Bootstrap/LegacyKeychainPurge.swift"))) {
  fail("LegacyKeychainPurge.swift must not ship in clean v1");
}

const secretsManager = read("macos/Sources/Clawix/Secrets/SecretsManager.swift");
if (secretsManager.includes("migrateLegacyConnectionAuths")) {
  fail("SecretsManager.swift must not migrate pre-v1 connection auth files");
}

const serviceManagerSource = read("macos/Sources/Clawix/ClawJS/ClawJSServiceManager.swift");
for (const pattern of ["legacy services", "still own a token store"]) {
  if (serviceManagerSource.includes(pattern)) {
    fail(`ClawJSServiceManager.swift must classify token-file services as explicit v1 contracts, not legacy: ${JSON.stringify(pattern)}`);
  }
}

const toolRoleSource = read("macos/Sources/Clawix/ClawixToolRole.swift");
for (const pattern of ["CLXAppRole=tasks", "ClawixToolRole(rawValue: raw)"]) {
  if (toolRoleSource.includes(pattern)) {
    fail(`ClawixToolRole.swift must require tool:<slug> roles for v1 mini-apps: ${JSON.stringify(pattern)}`);
  }
}

const devScriptSource = read("macos/scripts/dev.sh");
for (const pattern of ["CLAWIX_DEV_SKIP_TASKS", "role_value=\"tasks\""]) {
  if (devScriptSource.includes(pattern)) {
    fail(`macos/scripts/dev.sh must not emit or accept pre-v1 mini-app role controls: ${JSON.stringify(pattern)}`);
  }
}

const hostsPageSource = read("macos/Sources/Clawix/Settings/HostsPage.swift");
if (hostsPageSource.includes("typealias MachinesPage = HostsPage")) {
  fail("HostsPage.swift must not keep the pre-v1 MachinesPage alias");
}

const settingsControlsSource = read("macos/Sources/Clawix/Settings/SettingsView+Controls.swift");
for (const pattern of ["fillsWidth", "source compatibility"]) {
  if (settingsControlsSource.includes(pattern)) {
    fail(`SettingsView+Controls.swift must not keep no-op compatibility parameters: ${JSON.stringify(pattern)}`);
  }
}

const secretKindIconSource = read("macos/Sources/Clawix/Secrets/SecretKindIcon.swift");
if (secretKindIconSource.includes("source compatibility")) {
  fail("SecretKindIcon.swift must not keep no-op compatibility parameters");
}

const macosPackage = read("macos/Package.swift");
if (macosPackage.includes("legacy JSON blob store")) {
  fail("macos/Package.swift must describe current persistence without legacy blob-store wording");
}

for (const [relativePath, patterns] of [
  ["macos/Sources/Clawix/ThinScrollbar.swift", ["scrollView.scrollerStyle = .legacy", "scroller.scrollerStyle = .legacy", "horizontal.scrollerStyle = .legacy"]],
  ["macos/Sources/Clawix/QuickAsk/QuickAskView.swift", [".thinScrollers(style: .legacy)"]],
  ["macos/Sources/Clawix/Chat/ChatView+TranscriptScroller.swift", ["ThinScrollerInstaller(style: .legacy)"]],
  ["macos/Sources/Clawix/Terminal/TerminalEmulatorView.swift", ["scrollerStyle: .legacy"]],
]) {
  const source = read(relativePath);
  for (const pattern of patterns) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must use .clawixAlwaysVisible instead of exposing AppKit legacy scroller naming: ${JSON.stringify(pattern)}`);
    }
  }
}

const lucideBridgeSource = read("macos/Sources/Clawix/LucideBridge.swift");
for (const pattern of ["legacy SF Symbol", "init(lucideOrSystem", "Compatibility shim"]) {
  if (lucideBridgeSource.includes(pattern)) {
    fail(`LucideBridge.swift must not keep pre-v1 icon compatibility shims: ${JSON.stringify(pattern)}`);
  }
}

for (const relativePath of [
  "apps/macos/Sources/Clawix/LucideBridge.swift",
  "apps/ios/Sources/Clawix/Theme/LucideBridge.swift",
]) {
  const source = read(relativePath);
  for (const pattern of ["legacy SF Symbol"]) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must describe current Lucide bridge paths without legacy wording: ${JSON.stringify(pattern)}`);
    }
  }
}

for (const [relativePath, patterns] of [
  ["ios/Sources/Clawix/ChatDetail/ChatDetailView.swift", ["legacy stop(_:)"]],
  ["ios/Sources/Clawix/ClawixApp.swift", ["legacy `openChatId` flag", "openChatId", "openChat("]],
  ["ios/Sources/Clawix/Bridge/BridgeStore.swift", ["legacy daemon", "legacy peers", "openChatId", "openChat("]],
  ["ios/Sources/Clawix/Theme/LucideBridge.swift", ["legacy SF Symbol"]],
]) {
  const source = read(relativePath);
  for (const pattern of patterns) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must not describe current iOS v1 paths with legacy wording: ${JSON.stringify(pattern)}`);
    }
  }
}

const androidBridgeRoundtrip = read("android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt");
if (androidBridgeRoundtrip.includes("open_chat_omits_limit_when_null")) {
  fail("Android bridge round-trip tests must use session vocabulary for openSession coverage");
}

const secretsBackendSource = read("macos/Sources/Clawix/ClawJS/ClawJSSecretsBackend.swift");
for (const pattern of ["not yet wired to ClawJS Secrets HTTP backend", "BackupContents", "Legacy types"]) {
  if (secretsBackendSource.includes(pattern)) {
    fail(`ClawJSSecretsBackend.swift must not expose incomplete backup compatibility methods: ${JSON.stringify(pattern)}`);
  }
}

const skillDetailSource = read("macos/Sources/Clawix/Skills/SkillDetailView.swift");
for (const pattern of ["TODO: wire to Secrets", "Secret picker (TODO"]) {
  if (skillDetailSource.includes(pattern)) {
    fail(`SkillDetailView.swift must provide a real secretRef picker instead of visible TODO text: ${JSON.stringify(pattern)}`);
  }
}

const localModelsServiceSource = read("macos/Sources/Clawix/LocalModels/LocalModelsService.swift");
for (const pattern of ["for v1 just swallow", "future error banner", "try? await client.unload"]) {
  if (localModelsServiceSource.includes(pattern)) {
    fail(`LocalModelsService.swift must surface local model action failures in v1: ${JSON.stringify(pattern)}`);
  }
}

const profileEditorSource = read("macos/Sources/Clawix/Profile/ProfileEditor.swift");
for (const pattern of ["Reveal mnemonic", "placeholder here", "try? await manager."]) {
  if (profileEditorSource.includes(pattern)) {
    fail(`ProfileEditor.swift must not expose recovery no-ops or swallow profile action failures: ${JSON.stringify(pattern)}`);
  }
}

const databaseWorkbenchViewSource = read("macos/Sources/Clawix/Database/DatabaseWorkbenchView.swift");
if (databaseWorkbenchViewSource.includes("future execution logs")) {
  fail("DatabaseWorkbenchView.swift must describe the current v1 execution surface, not future logs");
}

const databaseWorkbenchSessionSource = read("macos/Sources/Clawix/Database/DatabaseWorkbenchSession.swift");
if (databaseWorkbenchSessionSource.includes("Execution remains disabled until a local runner is wired")) {
  fail("DatabaseWorkbenchSession.swift must not report local SQLite execution as unwired");
}

const templateDetailSource = read("macos/Sources/Clawix/Design/TemplateDetailView.swift");
for (const pattern of ["A future iteration", "Phase 2", "Phase 4"]) {
  if (templateDetailSource.includes(pattern)) {
    fail(`TemplateDetailView.swift must surface editor errors and avoid stale phase labels: ${JSON.stringify(pattern)}`);
  }
}

const paletteExtractorSource = read("macos/Sources/Clawix/Design/PaletteExtractor.swift");
for (const pattern of ["does not yet support", "Phase 3"]) {
  if (paletteExtractorSource.includes(pattern)) {
    fail(`PaletteExtractor.swift must describe unsupported sources as explicit v1 scope: ${JSON.stringify(pattern)}`);
  }
}

const agentsHomeSource = read("macos/Sources/Clawix/Agents/AgentsHomeView.swift");
for (const pattern of ["Importer is wired in as a stub", "importPicker", "tray.and.arrow.down"]) {
  if (agentsHomeSource.includes(pattern)) {
    fail(`AgentsHomeView.swift must not expose a non-functional import affordance: ${JSON.stringify(pattern)}`);
  }
}

const eventInspectorSource = read("macos/Sources/Clawix/Calendar/Views/EventInspectorPanel.swift");
for (const pattern of ["Add invitees", "Repeat: never", "Alert: 15 minutes before", "placeholder: true"]) {
  if (eventInspectorSource.includes(pattern)) {
    fail(`EventInspectorPanel.swift must not render calendar fields absent from the v1 event model: ${JSON.stringify(pattern)}`);
  }
}

const powerModeEditorSource = read("macos/Sources/Clawix/Dictation/PowerMode/PowerModeEditor.swift");
for (const pattern of ["coming soon", "not active yet", "nothing fires", "contextAwareness"]) {
  if (powerModeEditorSource.includes(pattern)) {
    fail(`PowerModeEditor.swift must not expose inert enhancement controls: ${JSON.stringify(pattern)}`);
  }
}
const localizableStringsSource = read("macos/Sources/Clawix/Resources/Localizable.xcstrings");
for (const pattern of ["Enhancement (coming soon)", "nothing fires until the Enhancement module ships"]) {
  if (localizableStringsSource.includes(pattern)) {
    fail(`Localizable.xcstrings must not keep stale visible v1 placeholder copy: ${JSON.stringify(pattern)}`);
  }
}

const generalSettingsSource = read("macos/Sources/Clawix/Settings/SettingsView+GeneralPage.swift");
for (const pattern of ["upcoming", "stub helper", "won't have your chats yet"]) {
  if (generalSettingsSource.includes(pattern)) {
    fail(`SettingsView+GeneralPage.swift must describe the current bridge contract, not a stub future: ${JSON.stringify(pattern)}`);
  }
}

const databaseWorkbenchSettingsSource = read("macos/Sources/Clawix/Database/DatabaseWorkbenchSettingsPage.swift");
for (const pattern of ["future approved run", "future approved connection"]) {
  if (databaseWorkbenchSettingsSource.includes(pattern)) {
    fail(`DatabaseWorkbenchSettingsPage.swift must use explicit approval language instead of future placeholders: ${JSON.stringify(pattern)}`);
  }
}

const iotScreenSource = read("macos/Sources/Clawix/IoT/IoTScreen.swift");
for (const pattern of ["Future: manager.switchHome", "Button {\n                            //"]) {
  if (iotScreenSource.includes(pattern)) {
    fail(`IoTScreen.swift must not expose no-op multi-home controls: ${JSON.stringify(pattern)}`);
  }
}

const databaseManagerSource = read("macos/Sources/Clawix/Database/DatabaseManager.swift");
if (!databaseManagerSource.includes("private func performMutation")) {
  fail("DatabaseManager.swift must route record mutation failures into lastError");
}

const iotManagerSource = read("macos/Sources/Clawix/IoT/IoTManager.swift");
if (!iotManagerSource.includes("private func performAction")) {
  fail("IoTManager.swift must route IoT action failures into lastError");
}

const automationsViewSource = read("macos/Sources/Clawix/AutomationsView.swift");
for (const pattern of ["Button {} label", "New automation", "Learn more"]) {
  if (automationsViewSource.includes(pattern)) {
    fail(`AutomationsView.swift must not expose a creation control without a v1 creation flow: ${JSON.stringify(pattern)}`);
  }
}

const sidebarProjectsSource = read("macos/Sources/Clawix/Sidebar/SidebarView+Projects.swift");
for (const pattern of [
  "struct PinnedRow",
  "Unpin chat",
  "Fork to local",
  "Fork to new worktree",
  "Open in mini window",
  "Create a permanent worktree",
  "Archive chats",
]) {
  if (sidebarProjectsSource.includes(pattern)) {
    fail(`SidebarView+Projects.swift must not expose project or pinned-row menu actions without v1 handlers: ${JSON.stringify(pattern)}`);
  }
}

const configurationSettingsSource = read("macos/Sources/Clawix/Settings/SettingsView+ConfigurationPage.swift");
if (configurationSettingsSource.includes("Button {} label")) {
  fail("SettingsView+ConfigurationPage.swift must not keep disabled reinstall controls without a v1 action");
}

for (const pattern of ["ImportAgentRow", "Import another agent configuration", "Button {} label"]) {
  if (generalSettingsSource.includes(pattern)) {
    fail(`SettingsView+GeneralPage.swift must not expose disabled import-agent affordances: ${JSON.stringify(pattern)}`);
  }
}

const driveScreenSource = read("macos/Sources/Clawix/Drive/DriveScreen.swift");
for (const pattern of ["try? await manager.client.createTailnetShare", "try? await manager.client.createTunnelShare", "try? await manager.client.createAgentShare", "shares = try? await manager.client.listAllShares"]) {
  if (driveScreenSource.includes(pattern)) {
    fail(`DriveScreen.swift must surface Drive detail action failures instead of swallowing them: ${JSON.stringify(pattern)}`);
  }
}

const indexSearchesSource = read("macos/Sources/Clawix/Index/Searches/SearchesTabView.swift");
if (indexSearchesSource.includes("try? await manager.runSearch")) {
  fail("SearchesTabView.swift must surface saved-search run failures");
}

const indexMonitorsSource = read("macos/Sources/Clawix/Index/Monitors/MonitorsTabView.swift");
if (indexMonitorsSource.includes("try? await manager.fireMonitor")) {
  fail("MonitorsTabView.swift must surface monitor fire failures");
}

const marketplaceManagerSource = read("macos/Sources/Clawix/Marketplace/MarketplaceManager.swift");
if (marketplaceManagerSource.includes("catch {}")) {
  fail("MarketplaceManager.swift must not swallow marketplace mutation failures");
}

const publishingManagerSource = read("macos/Sources/Clawix/Publishing/PublishingManager.swift");
for (const pattern of ["(try? await families)", "(try? await channels)"]) {
  if (publishingManagerSource.includes(pattern)) {
    fail(`PublishingManager.swift must not silently turn bootstrap list failures into empty v1 surfaces: ${JSON.stringify(pattern)}`);
  }
}

const publishingCalendarSource = read("macos/Sources/Clawix/Publishing/PublishingCalendarView.swift");
for (const pattern of ["Future:", "_ = date", "prefillScheduleAt: nil))"]) {
  if (publishingCalendarSource.includes(pattern)) {
    fail(`PublishingCalendarView.swift must prefill composer schedule dates instead of leaving calendar-cell scheduling provisional: ${JSON.stringify(pattern)}`);
  }
}

const publishingComposerSource = read("macos/Sources/Clawix/Publishing/PublishingComposerView.swift");
if (!publishingComposerSource.includes("let prefillScheduleAt: Date?")) {
  fail("PublishingComposerView.swift must accept calendar-provided schedule dates");
}

const agentModelsSource = read("macos/Sources/Clawix/Agents/AgentModels.swift");
for (const pattern of ["customImage", "imageRelativePath"]) {
  if (agentModelsSource.includes(pattern)) {
    fail(`AgentModels.swift must not keep unsupported custom-image avatar schema in the v1 surface: ${JSON.stringify(pattern)}`);
  }
}

const agentStoreSource = read("macos/Sources/Clawix/Agents/AgentStore.swift");
if (agentStoreSource.includes("avatarImage")) {
  fail("AgentStore.swift must not persist unsupported custom-image avatar fields in v1 agent records");
}

const skillsViewSource = read("macos/Sources/Clawix/Skills/SkillsView.swift");
if (skillsViewSource.includes("placeholder; full editor")) {
  fail("SkillsView.swift must not label the v1 new-skill sheet as a placeholder");
}

const iosClawixAppSource = read("ios/Sources/Clawix/ClawixApp.swift");
for (const pattern of ["RootNav.skills", "case skills", "SkillsListView()"]) {
  if (iosClawixAppSource.includes(pattern)) {
    fail(`iOS must not expose the local seed Skills catalog as a v1 product surface: ${JSON.stringify(pattern)}`);
  }
}

const iosChatListSource = read("ios/Sources/Clawix/ChatList/ChatListView.swift");
if (iosChatListSource.includes("onOpenSkills")) {
  fail("ChatListView.swift must not keep a visible iOS Skills entry until the bridge consumes real skillsList/skillsView frames");
}

for (const [relativePath, patterns] of [
  ["web/src/screens/database/database-view.tsx", ["Wire frames not yet exposed", "placeholder layout", "follow-up schema bump"]],
  ["web/src/screens/memory/memory-view.tsx", ["Wire frames not yet exposed", "placeholder layout", "future schema bump"]],
  ["web/src/screens/secrets/secrets-view.tsx", ["unlock frame still", "placeholder form", "wire the actual unlock frame"]],
]) {
  const source = read(relativePath);
  for (const pattern of patterns) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must describe web companion boundaries as v1 classification, not unfinished placeholder work: ${JSON.stringify(pattern)}`);
    }
  }
}

const windowsPhaseStubFiles = [
  "windows/Clawix.App/MainWindow.xaml.cs",
  "windows/Clawix.App/ViewModels/SidebarViewModel.cs",
  "windows/Clawix.App/ViewModels/ComposerViewModel.cs",
  "windows/Clawix.App/Views/LoginGateView.xaml.cs",
  "windows/Clawix.App/Views/SidebarView.xaml.cs",
  "windows/Clawix.App/Views/ComposerView.xaml.cs",
  "windows/Clawix.App/Views/SecretsScreen.xaml.cs",
  "windows/Clawix.App/Views/DictationOverlay.xaml.cs",
  "windows/Clawix.App/Views/ProjectEditorSheet.xaml.cs",
  "windows/Clawix.App/Views/MarkdownDocumentView.xaml.cs",
  "windows/Clawix.App/Views/Settings/GeneralPage.xaml.cs",
];
const windowsHasPhaseStubs = windowsPhaseStubFiles.some((relativePath) => readOptional(relativePath).includes("Phase 4"));
const windowsShellSurface = (registry.surfaces ?? []).find((surface) => surface.id === "windows.winuiShell");
if (windowsHasPhaseStubs) {
  if (windowsShellSurface?.status !== "dev-only") {
    fail("Windows WinUI shell has Phase 4 action stubs and must remain explicitly dev-only");
  }
  if (!read("docs/interface-matrix.md").includes("| Windows WinUI shell |")) {
    fail("interface matrix must classify the Windows WinUI shell as dev-only while Phase 4 action stubs remain");
  }
}

const inertSkillsBridgeFramePatterns = [
  "skillsList",
  "skillsView",
  "skillsCreate",
  "skillsUpdate",
  "skillsRemove",
  "skillsActivate",
  "skillsDeactivate",
  "skillsSync",
  "skillsImport",
  "skillsListResult",
  "skillsViewResult",
  "skillsActiveChanged",
];
for (const relativePath of [
  "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/BridgeIntent.swift",
  "macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift",
  "docs/persistent-surface-clawix.manifest.json",
]) {
  const source = read(relativePath);
  for (const pattern of inertSkillsBridgeFramePatterns) {
    if (source.includes(pattern)) {
      fail(`${relativePath} must not expose inert Skills bridge frame ${JSON.stringify(pattern)} until it has a real dispatcher`);
    }
  }
}

const agentStore = read("macos/Sources/Clawix/Agents/AgentStore.swift");
for (const pattern of [
  "migrateLegacyConnectionAuth",
  "readLegacyConnectionAuth",
  "legacyConnectionAuthURL",
  "readConnectionAuth",
  "auth.encrypted",
]) {
  if (agentStore.includes(pattern)) {
    fail(`AgentStore.swift contains clean-v1 incompatible connection auth legacy path ${JSON.stringify(pattern)}`);
  }
}

if (violations.length > 0) {
  console.error("Interface surface guard failed:");
  for (const violation of violations) console.error(`- ${violation}`);
  process.exit(1);
}

console.log("Interface surface guard passed");
