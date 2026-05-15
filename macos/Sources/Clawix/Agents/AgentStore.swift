import Foundation
import SwiftUI
import Combine
import ClawixCore
import SecretsModels
import SecretsVault

/// UI facade for framework-owned agent / personality / skill-collection
/// / connection records. The production path delegates reads and writes
/// to `claw agents|personalities|skill-collections|connections`; the
/// local filesystem implementation remains only as a test fixture and
/// emergency fallback when a custom `home` is injected.
///
/// ```
/// ~/.claw/
/// ├── agents/<id>/agent.yaml + instructions.md + ...
/// ├── personalities/<id>/personality.yaml + prompt.md
/// ├── skill-collections/<id>/collection.yaml
/// ├── connections/<id>/connection.yaml
/// ├── memory/                  # public, shared
/// └── presets/                 # builtins
/// ```
///
@MainActor
final class AgentStore: ObservableObject {

    static let shared = AgentStore()

    // MARK: - Published state

    @Published private(set) var agents: [Agent] = []
    @Published private(set) var personalities: [AgentPersonality] = []
    @Published private(set) var skillCollections: [SkillCollection] = []
    @Published private(set) var connections: [Connection] = []

    // MARK: - Init

    init(home: URL? = nil, frameworkClient: ClawJSFrameworkRecordsClient? = nil) {
        if let home {
            self.home = home
        } else {
            self.home = AgentStore.defaultHome()
        }
        self.frameworkClient = frameworkClient ?? (home == nil ? .shared : nil)
        if self.frameworkClient == nil {
            ensureDirectories()
            ensureBuiltins()
        }
        reloadAll()
    }

    private let home: URL
    private let frameworkClient: ClawJSFrameworkRecordsClient?

    private static func defaultHome() -> URL {
        if let override = ProcessInfo.processInfo.environment[ClawEnv.home],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawWorkspace, isDirectory: true)
        return url
    }

    // MARK: - Layout helpers

    private var agentsDir: URL          { home.appendingPathComponent("agents", isDirectory: true) }
    private var personalitiesDir: URL   { home.appendingPathComponent("personalities", isDirectory: true) }
    private var collectionsDir: URL     { home.appendingPathComponent("skill-collections", isDirectory: true) }
    private var connectionsDir: URL     { home.appendingPathComponent("connections", isDirectory: true) }
    private var presetsDir: URL         { home.appendingPathComponent("presets", isDirectory: true) }
    private var publicMemoryDir: URL    { home.appendingPathComponent("memory", isDirectory: true) }

    private func dir(forAgent id: String) -> URL          { agentsDir.appendingPathComponent(id, isDirectory: true) }
    private func dir(forAgentPersonality id: String) -> URL    { personalitiesDir.appendingPathComponent(id, isDirectory: true) }
    private func dir(forCollection id: String) -> URL     { collectionsDir.appendingPathComponent(id, isDirectory: true) }
    private func dir(forConnection id: String) -> URL     { connectionsDir.appendingPathComponent(id, isDirectory: true) }

    private func ensureDirectories() {
        for url in [agentsDir, personalitiesDir, collectionsDir, connectionsDir, presetsDir, publicMemoryDir] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reload

    func reloadAll() {
        if let frameworkClient {
            do {
                agents = try frameworkClient.listAgents()
                personalities = try frameworkClient.listPersonalities()
                skillCollections = try frameworkClient.listSkillCollections()
                connections = try frameworkClient.listConnections()
                return
            } catch {
                agents = [Agent.defaultCodex()]
                personalities = []
                skillCollections = []
                connections = []
                return
            }
        }
        agents = loadAgents()
        personalities = loadPersonalities()
        skillCollections = loadCollections()
        connections = loadConnections()
    }

    // MARK: - Builtins

    private func ensureBuiltins() {
        let builtinAgentDir = dir(forAgent: Agent.defaultCodexId)
        let agentYaml = builtinAgentDir.appendingPathComponent("agent.yaml")
        if !FileManager.default.fileExists(atPath: agentYaml.path) {
            try? FileManager.default.createDirectory(at: builtinAgentDir, withIntermediateDirectories: true)
            let agent = Agent.defaultCodex()
            try? writeAgent(agent, into: builtinAgentDir)
        }
        // Built-in personality preset so the user lands on at least one
        // entry the first time they open the Personalities surface.
        ensureBuiltinAgentPersonalityIfMissing(
            id: "personality.terse-pragma",
            name: "Terse Pragma",
            description: "Drops pleasantries, leads with the answer.",
            prompt: "Reply in the smallest number of tokens that carry the meaning. Lead with the answer. No preamble, no apology, no \"sure thing\"."
        )
        ensureBuiltinAgentPersonalityIfMissing(
            id: "personality.ironic-mentor",
            name: "Ironic Mentor",
            description: "Senior engineer voice with dry humor.",
            prompt: "Speak like a senior engineer reviewing a junior teammate's PR. Concise, never condescending, dry humor only when it helps the lesson stick."
        )
        ensureBuiltinCollectionIfMissing(
            id: "collection.research",
            name: "Research",
            description: "Web search, summarisation, evidence-finding skills.",
            tags: ["research", "web", "summarize"]
        )
        ensureBuiltinCollectionIfMissing(
            id: "collection.engineering",
            name: "Engineering",
            description: "Codebase navigation, refactoring, test-running skills.",
            tags: ["engineering", "refactor", "test"]
        )
    }

    private func ensureBuiltinAgentPersonalityIfMissing(id: String, name: String, description: String, prompt: String) {
        let folder = dir(forAgentPersonality: id)
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("personality.yaml").path) { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let p = AgentPersonality(id: id, name: name, description: description, promptMarkdown: prompt,
                            version: 1, createdAt: Date(), updatedAt: Date())
        try? writeAgentPersonality(p, into: folder)
    }

    private func ensureBuiltinCollectionIfMissing(id: String, name: String, description: String, tags: [String]) {
        let folder = dir(forCollection: id)
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("collection.yaml").path) { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let c = SkillCollection(id: id, name: name, description: description, includedTags: tags,
                                createdAt: Date(), updatedAt: Date())
        try? writeCollection(c, into: folder)
    }

    // MARK: - Agents

    private func loadAgents() -> [Agent] {
        var result: [Agent] = []
        let entries = (try? FileManager.default.contentsOfDirectory(at: agentsDir,
                                                                    includingPropertiesForKeys: nil)) ?? []
        for url in entries {
            if let agent = readAgent(from: url) {
                result.append(agent)
            }
        }
        result.sort { lhs, rhs in
            if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin && !rhs.isBuiltin }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return result
    }

    func agent(id: String) -> Agent? {
        agents.first { $0.id == id }
    }

    func upsertAgent(_ agent: Agent) {
        if let frameworkClient {
            var copy = agent
            copy.updatedAt = Date()
            try? frameworkClient.upsertAgent(copy)
            reloadAll()
            return
        }
        let folder = dir(forAgent: agent.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copy = agent
        copy.updatedAt = Date()
        try? writeAgent(copy, into: folder)
        reloadAll()
    }

    @discardableResult
    func duplicateAgent(id: String) -> Agent? {
        guard let source = agent(id: id) else { return nil }
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        var copy = source
        copy.id = "agent.\(suffix)"
        copy.name = source.name + " copy"
        copy.isBuiltin = false
        copy.createdAt = Date()
        copy.updatedAt = Date()
        upsertAgent(copy)
        return copy
    }

    func deleteAgent(id: String) {
        guard let agent = agent(id: id), !agent.isBuiltin else { return }
        if let frameworkClient {
            try? frameworkClient.deleteAgent(id: id)
            reloadAll()
            return
        }
        let folder = dir(forAgent: id)
        try? FileManager.default.removeItem(at: folder)
        reloadAll()
    }

    /// Persist an entire agent record to disk. Splits the data into
    /// the per-file convention the plan calls for (`agent.yaml`,
    /// `instructions.md`, `personalities.yaml`, …) so the on-disk
    /// layout is browseable.
    private func writeAgent(_ agent: Agent, into folder: URL) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let agentYaml: [(String, SimpleYaml.Value)] = [
            ("id", .string(agent.id)),
            ("name", .string(agent.name)),
            ("role", .string(agent.role)),
            ("runtime", .string(agent.runtime.rawValue)),
            ("model", .string(agent.model)),
            ("avatarKind", .string(agent.avatar.kind.rawValue)),
            ("avatarTintHex", .string(agent.avatar.tintHex)),
            ("avatarImage", .string(agent.avatar.imageRelativePath ?? "")),
            ("autonomyLevel", .string(agent.autonomyLevel.rawValue)),
            ("isBuiltin", .bool(agent.isBuiltin)),
            ("createdAt", .string(iso.string(from: agent.createdAt))),
            ("updatedAt", .string(iso.string(from: agent.updatedAt))),
        ]
        try SimpleYaml.emit(agentYaml).write(
            to: folder.appendingPathComponent("agent.yaml"),
            atomically: true, encoding: .utf8)

        try agent.instructionsFreeText.write(
            to: folder.appendingPathComponent("instructions.md"),
            atomically: true, encoding: .utf8)

        let personalitiesYaml = SimpleYaml.emit([
            ("personalities", .array(agent.personalityIds.map { .string($0) }))
        ])
        try personalitiesYaml.write(
            to: folder.appendingPathComponent("personalities.yaml"),
            atomically: true, encoding: .utf8)

        let skillsYaml = SimpleYaml.emit([
            ("allowlist", .array(agent.skillAllowlist.map { .string($0) })),
            ("collections", .array(agent.skillCollectionIds.map { .string($0) })),
        ])
        try skillsYaml.write(
            to: folder.appendingPathComponent("skills.yaml"),
            atomically: true, encoding: .utf8)

        let secretsYaml = SimpleYaml.emit([
            ("allowlist", .array(agent.secretAllowlist.map { .string($0) })),
            ("tags",      .array(agent.secretTags.map { .string($0) })),
        ])
        try secretsYaml.write(
            to: folder.appendingPathComponent("secrets.yaml"),
            atomically: true, encoding: .utf8)

        let projectsYaml = SimpleYaml.emit([
            ("projects", .array(agent.projectIds.map { .string($0) }))
        ])
        try projectsYaml.write(
            to: folder.appendingPathComponent("projects.yaml"),
            atomically: true, encoding: .utf8)

        // Integrations + permissions + delegation are richer than the
        // flat YAML grammar, so they go through JSON. The plan calls
        // for `.yaml` extensions; we keep the extension and write JSON
        // inside (still git-friendly, still inspectable, no schema
        // surprises). Once a stricter YAML emitter lands we re-encode.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(agent.integrationBindings).write(
            to: folder.appendingPathComponent("integrations.yaml"))
        try encoder.encode(agent.autonomyOverrides).write(
            to: folder.appendingPathComponent("permissions.yaml"))
        try encoder.encode(agent.delegation).write(
            to: folder.appendingPathComponent("delegation.yaml"))
    }

    private func readAgent(from folder: URL) -> Agent? {
        let yamlPath = folder.appendingPathComponent("agent.yaml")
        guard let yamlText = try? String(contentsOf: yamlPath, encoding: .utf8) else { return nil }
        let yaml = SimpleYaml.parse(yamlText)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let id = SimpleYaml.string(yaml, "id", default: folder.lastPathComponent)
        let runtimeRaw = SimpleYaml.string(yaml, "runtime", default: "codex")
        let runtime = AgentRuntimeKind(rawValue: runtimeRaw) ?? .codex
        let autonomyRaw = SimpleYaml.string(yaml, "autonomyLevel", default: AgentAutonomyLevel.actLimited.rawValue)
        let autonomy = AgentAutonomyLevel(rawValue: autonomyRaw) ?? .actLimited
        let avatarKindRaw = SimpleYaml.string(yaml, "avatarKind", default: AgentAvatarKind.logoTint.rawValue)
        let avatarKind = AgentAvatarKind(rawValue: avatarKindRaw) ?? .logoTint
        let createdAt = iso.date(from: SimpleYaml.string(yaml, "createdAt")) ?? Date()
        let updatedAt = iso.date(from: SimpleYaml.string(yaml, "updatedAt")) ?? createdAt

        let instructions = (try? String(contentsOf: folder.appendingPathComponent("instructions.md"),
                                        encoding: .utf8)) ?? ""

        let personalitiesYaml = (try? String(contentsOf: folder.appendingPathComponent("personalities.yaml"),
                                             encoding: .utf8)) ?? ""
        let personalityIds = SimpleYaml.stringArray(SimpleYaml.parse(personalitiesYaml), "personalities")

        let skillsYaml = (try? String(contentsOf: folder.appendingPathComponent("skills.yaml"),
                                      encoding: .utf8)) ?? ""
        let skillsDict = SimpleYaml.parse(skillsYaml)
        let skillAllowlist = SimpleYaml.stringArray(skillsDict, "allowlist")
        let collectionIds = SimpleYaml.stringArray(skillsDict, "collections")

        let secretsYaml = (try? String(contentsOf: folder.appendingPathComponent("secrets.yaml"),
                                       encoding: .utf8)) ?? ""
        let secretsDict = SimpleYaml.parse(secretsYaml)
        let secretAllowlist = SimpleYaml.stringArray(secretsDict, "allowlist")
        let secretTags = SimpleYaml.stringArray(secretsDict, "tags")

        let projectsYaml = (try? String(contentsOf: folder.appendingPathComponent("projects.yaml"),
                                        encoding: .utf8)) ?? ""
        let projectIds = SimpleYaml.stringArray(SimpleYaml.parse(projectsYaml), "projects")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let bindings: [AgentIntegrationBinding] = {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("integrations.yaml")),
                  let decoded = try? decoder.decode([AgentIntegrationBinding].self, from: data) else { return [] }
            return decoded
        }()
        let overrides: [AgentAutonomyOverride] = {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("permissions.yaml")),
                  let decoded = try? decoder.decode([AgentAutonomyOverride].self, from: data) else { return [] }
            return decoded
        }()
        let delegation: AgentDelegation = {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("delegation.yaml")),
                  let decoded = try? decoder.decode(AgentDelegation.self, from: data) else {
                return AgentDelegation()
            }
            return decoded
        }()

        return Agent(
            id: id,
            name: SimpleYaml.string(yaml, "name", default: "Unnamed agent"),
            role: SimpleYaml.string(yaml, "role"),
            runtime: runtime,
            model: SimpleYaml.string(yaml, "model", default: runtime.defaultModel),
            avatar: AgentAvatar(
                kind: avatarKind,
                tintHex: SimpleYaml.string(yaml, "avatarTintHex", default: "#7C9CFF"),
                imageRelativePath: {
                    let p = SimpleYaml.string(yaml, "avatarImage")
                    return p.isEmpty ? nil : p
                }()
            ),
            instructionsFreeText: instructions,
            personalityIds: personalityIds,
            skillAllowlist: skillAllowlist,
            skillCollectionIds: collectionIds,
            secretAllowlist: secretAllowlist,
            secretTags: secretTags,
            projectIds: projectIds,
            integrationBindings: bindings,
            autonomyLevel: autonomy,
            autonomyOverrides: overrides,
            delegation: delegation,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isBuiltin: SimpleYaml.bool(yaml, "isBuiltin")
        )
    }

    // MARK: - Personalities

    private func loadPersonalities() -> [AgentPersonality] {
        var result: [AgentPersonality] = []
        let entries = (try? FileManager.default.contentsOfDirectory(at: personalitiesDir,
                                                                    includingPropertiesForKeys: nil)) ?? []
        for url in entries {
            if let p = readAgentPersonality(from: url) { result.append(p) }
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }

    func personality(id: String) -> AgentPersonality? {
        personalities.first { $0.id == id }
    }

    func upsertAgentPersonality(_ p: AgentPersonality) {
        if let frameworkClient {
            var copy = p
            copy.updatedAt = Date()
            try? frameworkClient.upsertPersonality(copy)
            reloadAll()
            return
        }
        let folder = dir(forAgentPersonality: p.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copy = p
        copy.updatedAt = Date()
        try? writeAgentPersonality(copy, into: folder)
        reloadAll()
    }

    func deleteAgentPersonality(id: String) {
        if let frameworkClient {
            try? frameworkClient.deletePersonality(id: id)
            for var agent in agents where agent.personalityIds.contains(id) {
                agent.personalityIds.removeAll { $0 == id }
                try? frameworkClient.upsertAgent(agent)
            }
            reloadAll()
            return
        }
        let folder = dir(forAgentPersonality: id)
        try? FileManager.default.removeItem(at: folder)
        // Drop references from any agent that had it plugged in.
        for var agent in agents where agent.personalityIds.contains(id) {
            agent.personalityIds.removeAll { $0 == id }
            upsertAgent(agent)
        }
        reloadAll()
    }

    private func writeAgentPersonality(_ p: AgentPersonality, into folder: URL) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let yaml = SimpleYaml.emit([
            ("id", .string(p.id)),
            ("name", .string(p.name)),
            ("description", .string(p.description)),
            ("version", .int(p.version)),
            ("createdAt", .string(iso.string(from: p.createdAt))),
            ("updatedAt", .string(iso.string(from: p.updatedAt))),
        ])
        try yaml.write(to: folder.appendingPathComponent("personality.yaml"),
                       atomically: true, encoding: .utf8)
        try p.promptMarkdown.write(to: folder.appendingPathComponent("prompt.md"),
                                   atomically: true, encoding: .utf8)
    }

    private func readAgentPersonality(from folder: URL) -> AgentPersonality? {
        let yamlPath = folder.appendingPathComponent("personality.yaml")
        guard let yamlText = try? String(contentsOf: yamlPath, encoding: .utf8) else { return nil }
        let yaml = SimpleYaml.parse(yamlText)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let prompt = (try? String(contentsOf: folder.appendingPathComponent("prompt.md"),
                                  encoding: .utf8)) ?? ""
        let createdAt = iso.date(from: SimpleYaml.string(yaml, "createdAt")) ?? Date()
        let updatedAt = iso.date(from: SimpleYaml.string(yaml, "updatedAt")) ?? createdAt
        return AgentPersonality(
            id: SimpleYaml.string(yaml, "id", default: folder.lastPathComponent),
            name: SimpleYaml.string(yaml, "name", default: "Unnamed personality"),
            description: SimpleYaml.string(yaml, "description"),
            promptMarkdown: prompt,
            version: SimpleYaml.int(yaml, "version", default: 1),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Skill Collections

    private func loadCollections() -> [SkillCollection] {
        var result: [SkillCollection] = []
        let entries = (try? FileManager.default.contentsOfDirectory(at: collectionsDir,
                                                                    includingPropertiesForKeys: nil)) ?? []
        for url in entries {
            if let c = readCollection(from: url) { result.append(c) }
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }

    func collection(id: String) -> SkillCollection? {
        skillCollections.first { $0.id == id }
    }

    func upsertCollection(_ c: SkillCollection) {
        if let frameworkClient {
            var copy = c
            copy.updatedAt = Date()
            try? frameworkClient.upsertSkillCollection(copy)
            reloadAll()
            return
        }
        let folder = dir(forCollection: c.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copy = c
        copy.updatedAt = Date()
        try? writeCollection(copy, into: folder)
        reloadAll()
    }

    func deleteCollection(id: String) {
        if let frameworkClient {
            try? frameworkClient.deleteSkillCollection(id: id)
            for var agent in agents where agent.skillCollectionIds.contains(id) {
                agent.skillCollectionIds.removeAll { $0 == id }
                try? frameworkClient.upsertAgent(agent)
            }
            reloadAll()
            return
        }
        let folder = dir(forCollection: id)
        try? FileManager.default.removeItem(at: folder)
        for var agent in agents where agent.skillCollectionIds.contains(id) {
            agent.skillCollectionIds.removeAll { $0 == id }
            upsertAgent(agent)
        }
        reloadAll()
    }

    private func writeCollection(_ c: SkillCollection, into folder: URL) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let yaml = SimpleYaml.emit([
            ("id", .string(c.id)),
            ("name", .string(c.name)),
            ("description", .string(c.description)),
            ("tags", .array(c.includedTags.map { .string($0) })),
            ("createdAt", .string(iso.string(from: c.createdAt))),
            ("updatedAt", .string(iso.string(from: c.updatedAt))),
        ])
        try yaml.write(to: folder.appendingPathComponent("collection.yaml"),
                       atomically: true, encoding: .utf8)
    }

    private func readCollection(from folder: URL) -> SkillCollection? {
        let yamlPath = folder.appendingPathComponent("collection.yaml")
        guard let yamlText = try? String(contentsOf: yamlPath, encoding: .utf8) else { return nil }
        let yaml = SimpleYaml.parse(yamlText)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let createdAt = iso.date(from: SimpleYaml.string(yaml, "createdAt")) ?? Date()
        let updatedAt = iso.date(from: SimpleYaml.string(yaml, "updatedAt")) ?? createdAt
        return SkillCollection(
            id: SimpleYaml.string(yaml, "id", default: folder.lastPathComponent),
            name: SimpleYaml.string(yaml, "name", default: "Unnamed collection"),
            description: SimpleYaml.string(yaml, "description"),
            includedTags: SimpleYaml.stringArray(yaml, "tags"),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Connections

    private func loadConnections() -> [Connection] {
        var result: [Connection] = []
        let entries = (try? FileManager.default.contentsOfDirectory(at: connectionsDir,
                                                                    includingPropertiesForKeys: nil)) ?? []
        for url in entries {
            if let c = readConnection(from: url) { result.append(c) }
        }
        result.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        return result
    }

    func connection(id: String) -> Connection? {
        connections.first { $0.id == id }
    }

    func upsertConnection(_ c: Connection) {
        if let frameworkClient {
            var copy = c
            copy.updatedAt = Date()
            try? frameworkClient.upsertConnection(copy)
            reloadAll()
            return
        }
        let folder = dir(forConnection: c.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copy = c
        copy.updatedAt = Date()
        try? writeConnection(copy, into: folder)
        reloadAll()
    }

    /// Persist the secret material for a connection (bot token, OAuth
    /// refresh token, etc.) in the canonical encrypted Secrets vault.
    func writeConnectionAuth(connectionId: String, secret: String) {
        guard let store = SecretsManager.shared.store else { return }
        writeConnectionAuth(connectionId: connectionId, secret: secret, store: store)
    }

    private func writeConnectionAuth(connectionId: String, secret: String, store: ClawJSSecretsStore) {
        let folder = dir(forConnection: connectionId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let internalName = connectionAuthInternalName(connectionId)
        if let existing = try? store.fetchSecret(byInternalName: internalName) {
            try? store.trashSecret(id: existing.id)
        }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let container = try ensureSecretsContainer(in: store)
            let draft = DraftSecret(
                kind: .apiKey,
                internalName: internalName,
                title: "Connection Auth - \(connectionId)",
                fields: [
                    DraftField(
                        name: "value",
                        fieldKind: .password,
                        placement: .header,
                        isSecret: true,
                        isConcealed: true,
                        secretValue: trimmed,
                        sortOrder: 0
                    )
                ]
            )
            let created = try store.createSecret(in: container, draft: draft)
            _ = try store.updateGovernance(
                secretId: created.id,
                to: Governance(
                    allowedHosts: [],
                    allowedHeaders: ["Authorization"],
                    allowInUrl: false,
                    allowInBody: false,
                    allowInEnv: false,
                    allowInsecureTransport: false,
                    allowLocalNetwork: false,
                    approvalMode: .everyUse
                )
            )
            if var connection = connection(id: connectionId), let frameworkClient {
                connection.updatedAt = Date()
                try? frameworkClient.upsertConnection(connection, secretRef: "vault://connections/\(connectionId)")
                reloadAll()
            }
        } catch {
            return
        }
    }

    func hasConnectionAuth(connectionId: String) -> Bool {
        guard let store = SecretsManager.shared.store else { return false }
        let internalName = connectionAuthInternalName(connectionId)
        if let secret = try? store.fetchSecret(byInternalName: internalName), secret.trashedAt == nil {
            return true
        }
        return false
    }

    private func connectionAuthInternalName(_ connectionId: String) -> String {
        "connection.\(connectionId).auth"
    }

    private func ensureSecretsContainer(in store: ClawJSSecretsStore) throws -> VaultRecord {
        let containers = try store.listVaults()
        if let existing = containers.first(where: { $0.name == SystemSecrets.containerName }) {
            return existing
        }
        return try store.createVault(name: SystemSecrets.containerName)
    }

    func deleteConnection(id: String) {
        if let frameworkClient {
            try? frameworkClient.deleteConnection(id: id)
            for var agent in agents where agent.integrationBindings.contains(where: { $0.connectionId == id }) {
                agent.integrationBindings.removeAll { $0.connectionId == id }
                try? frameworkClient.upsertAgent(agent)
            }
            reloadAll()
            return
        }
        let folder = dir(forConnection: id)
        try? FileManager.default.removeItem(at: folder)
        for var agent in agents where agent.integrationBindings.contains(where: { $0.connectionId == id }) {
            agent.integrationBindings.removeAll { $0.connectionId == id }
            upsertAgent(agent)
        }
        reloadAll()
    }

    private func writeConnection(_ c: Connection, into folder: URL) throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var pairs: [(String, SimpleYaml.Value)] = [
            ("id", .string(c.id)),
            ("service", .string(c.service.rawValue)),
            ("label", .string(c.label)),
            ("scopes", .array(c.scopes.map { .string($0) })),
            ("createdAt", .string(iso.string(from: c.createdAt))),
            ("updatedAt", .string(iso.string(from: c.updatedAt))),
        ]
        if let lastSync = c.lastSyncAt {
            pairs.append(("lastSyncAt", .string(iso.string(from: lastSync))))
        }
        try SimpleYaml.emit(pairs).write(
            to: folder.appendingPathComponent("connection.yaml"),
            atomically: true, encoding: .utf8)
    }

    private func readConnection(from folder: URL) -> Connection? {
        let yamlPath = folder.appendingPathComponent("connection.yaml")
        guard let yamlText = try? String(contentsOf: yamlPath, encoding: .utf8) else { return nil }
        let yaml = SimpleYaml.parse(yamlText)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let serviceRaw = SimpleYaml.string(yaml, "service", default: ConnectionService.telegram.rawValue)
        let service = ConnectionService(rawValue: serviceRaw) ?? .custom
        let createdAt = iso.date(from: SimpleYaml.string(yaml, "createdAt")) ?? Date()
        let updatedAt = iso.date(from: SimpleYaml.string(yaml, "updatedAt")) ?? createdAt
        let lastSync = iso.date(from: SimpleYaml.string(yaml, "lastSyncAt"))
        return Connection(
            id: SimpleYaml.string(yaml, "id", default: folder.lastPathComponent),
            service: service,
            label: SimpleYaml.string(yaml, "label", default: service.label),
            scopes: SimpleYaml.stringArray(yaml, "scopes"),
            lastSyncAt: lastSync,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Composition resolver

    /// Resolves the system-prompt fragment for an agent: concatenates
    /// every plugged-in personality's `prompt.md` (in order) and
    /// appends the agent's free-text instructions at the bottom. The
    /// daemon receives the result through `WireAgent.systemPromptResolved`
    /// when a thread is opened; if the resolver fails the daemon
    /// falls back to the legacy runtime-default behaviour.
    func resolvedSystemPrompt(for agent: Agent) -> String {
        var parts: [String] = []
        for pid in agent.personalityIds {
            if let p = personality(id: pid) {
                parts.append(p.promptMarkdown)
            }
        }
        if !agent.instructionsFreeText.isEmpty {
            parts.append(agent.instructionsFreeText)
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    /// Audit-log entry. Append-only file under
    /// `~/.claw/agents/<id>/audit.log`. Each line is JSON for grep /
    /// jq friendliness.
    func appendAudit(_ entry: AgentAuditEntry, on agentId: String) {
        let folder = dir(forAgent: agentId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("audit.log")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }
        let appended = line + "\n"
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(appended.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? appended.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
