import Foundation
import SwiftUI

// MARK: - Runtime catalog

/// Runtime an agent is bound to. Mirrors the adapters registered in
/// `clawjs-node/src/runtime/adapters`. The agent owns its runtime as
/// part of its identity; switching runtime means editing the agent
/// rather than picking a different model on the fly.
enum AgentRuntimeKind: String, CaseIterable, Identifiable, Codable {
    case codex
    case openclaude
    case hermes
    case claw
    case demo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex:      return "Codex"
        case .openclaude: return "OpenClaude"
        case .hermes:     return "Hermes"
        case .claw:       return "Claw"
        case .demo:       return "Demo"
        }
    }

    /// Default model slug the editor pre-fills for a brand-new agent
    /// using this runtime. The actual resolution against `~/.codex/`,
    /// `~/.openclaude.json`, etc. is performed by the framework's
    /// `RuntimeAdapter` at thread-start time.
    var defaultModel: String {
        switch self {
        case .codex:      return "gpt-5.1"
        case .openclaude: return "claude-opus-4-7"
        case .hermes:     return "hermes-4-7"
        case .claw:       return "claw-default"
        case .demo:       return "demo"
        }
    }
}

// MARK: - Autonomy

/// Slider position. Each level corresponds to a default policy for
/// every gated action; `AgentAutonomyOverride` lets the user pin a
/// specific action to a stricter level than the slider would imply
/// (e.g. always ask before `git push` even when the agent is
/// otherwise on `act_full`).
enum AgentAutonomyLevel: String, CaseIterable, Identifiable, Codable {
    case observe
    case suggest
    case actLimited = "act_limited"
    case actFull = "act_full"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .observe:    return "Observe"
        case .suggest:    return "Suggest"
        case .actLimited: return "Act limited"
        case .actFull:    return "Act full"
        }
    }

    var blurb: String {
        switch self {
        case .observe:
            return "Watches and reports. Never edits, runs commands, or sends messages on its own."
        case .suggest:
            return "Proposes patches and commands but waits for explicit approval before applying anything."
        case .actLimited:
            return "Executes reversible changes inside its scope. Asks before destructive or external actions."
        case .actFull:
            return "Operates autonomously within its scope. Only approval-flagged actions still gate."
        }
    }
}

struct AgentAutonomyOverride: Equatable, Codable {
    var action: String
    var level: AgentAutonomyLevel
}

// MARK: - Avatar

enum AgentAvatarKind: String, Codable {
    case logoTint
    case customImage
}

struct AgentAvatar: Equatable, Codable {
    var kind: AgentAvatarKind = .logoTint
    /// Hex tint applied to `ClawixLogoIcon` when `kind == .logoTint`.
    var tintHex: String = "#7C9CFF"
    /// Relative path under the agent's folder (e.g. `avatar.png`)
    /// when `kind == .customImage`. The absolute path is composed by
    /// `AgentStore` at read time.
    var imageRelativePath: String?

    var tintColor: Color {
        AgentAvatar.color(fromHex: tintHex) ?? Color(red: 0.486, green: 0.612, blue: 1.0)
    }

    /// Local hex parser. The project already ships a `Color.init?(hex:)`
    /// extension in `ProviderBrandIcon.swift`, but call sites in this
    /// file fall back to a free function so the avatar struct stays
    /// self-contained for tests / previews that don't import the
    /// Settings module's transitive dependencies.
    static func color(fromHex hex: String) -> Color? {
        var trimmed = hex.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double( value & 0x0000FF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Integration binding

/// One row of `integrations.yaml`: this agent talks to this connection
/// on this channel. A single Connection (one bot token, one OAuth
/// session) can be reused by N agents, each bound to its own channel
/// list. Direction lets a single agent be inbound-only (listen + reply)
/// or outbound-only (push reports out, not a chat partner).
struct AgentIntegrationBinding: Equatable, Identifiable, Codable {
    var id: String
    var connectionId: String
    var channelRef: String
    var direction: Direction = .both
    var label: String?

    enum Direction: String, Codable, CaseIterable {
        case inbound
        case outbound
        case both
    }
}

// MARK: - Delegation

/// Subset of `delegation.yaml`. `reportsTo` is a sibling agent id (or
/// nil for top-level agents); `allowedSubagents` enumerates which
/// agents this one may invoke as tools. `scopeInherits` controls
/// whether skills / secrets / projects of the invoking agent leak to
/// the invoked one, with the obvious risk of permission widening.
struct AgentDelegation: Equatable, Codable {
    var reportsTo: String?
    var allowedSubagents: [String] = []
    var scopeInherits: Bool = false
}

// MARK: - Agent

struct Agent: Identifiable, Equatable, Codable {
    /// Stable id used by `~/.clawjs/agents/<id>/` and by `WireChat.agentId`.
    /// For the built-in default Codex agent this is `agent.default.codex`
    /// and the editor refuses to mutate it.
    var id: String
    var name: String
    var role: String
    var runtime: AgentRuntimeKind
    var model: String
    var avatar: AgentAvatar

    var instructionsFreeText: String

    var personalityIds: [String]
    var skillAllowlist: [String]
    var skillCollectionIds: [String]
    var secretAllowlist: [String]
    var secretTags: [String]
    var projectIds: [String]
    var integrationBindings: [AgentIntegrationBinding]

    var autonomyLevel: AgentAutonomyLevel
    var autonomyOverrides: [AgentAutonomyOverride]
    var delegation: AgentDelegation

    var createdAt: Date
    var updatedAt: Date

    /// Whether this agent is a built-in template the editor keeps
    /// read-only. The default Codex agent is the only one today; it
    /// shadows the previous `AgentRuntimeChoice` behaviour so existing
    /// chats keep working without a migration.
    var isBuiltin: Bool

    static let defaultCodexId: String = "agent.default.codex"

    static func defaultCodex(model: String = "gpt-5.1") -> Agent {
        Agent(
            id: defaultCodexId,
            name: "Codex",
            role: "Default coding agent",
            runtime: .codex,
            model: model,
            avatar: AgentAvatar(kind: .logoTint, tintHex: "#7C9CFF"),
            instructionsFreeText: "",
            personalityIds: [],
            skillAllowlist: [],
            skillCollectionIds: [],
            secretAllowlist: [],
            secretTags: [],
            projectIds: [],
            integrationBindings: [],
            autonomyLevel: .actLimited,
            autonomyOverrides: [],
            delegation: AgentDelegation(),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            isBuiltin: true
        )
    }

    static func newDraft(runtime: AgentRuntimeKind = .codex) -> Agent {
        let now = Date()
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        return Agent(
            id: "agent.\(suffix)",
            name: "New Agent",
            role: "",
            runtime: runtime,
            model: runtime.defaultModel,
            avatar: AgentAvatar(kind: .logoTint, tintHex: AgentAvatarPalette.next()),
            instructionsFreeText: "",
            personalityIds: [],
            skillAllowlist: [],
            skillCollectionIds: [],
            secretAllowlist: [],
            secretTags: [],
            projectIds: [],
            integrationBindings: [],
            autonomyLevel: .actLimited,
            autonomyOverrides: [],
            delegation: AgentDelegation(),
            createdAt: now,
            updatedAt: now,
            isBuiltin: false
        )
    }
}

// MARK: - Personality

struct AgentPersonality: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var description: String
    var promptMarkdown: String
    var version: Int
    var createdAt: Date
    var updatedAt: Date

    static func newDraft() -> AgentPersonality {
        let now = Date()
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        return AgentPersonality(
            id: "personality.\(suffix)",
            name: "New personality",
            description: "",
            promptMarkdown: "",
            version: 1,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - Skill collection

struct SkillCollection: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var description: String
    var includedTags: [String]
    var createdAt: Date
    var updatedAt: Date

    static func newDraft() -> SkillCollection {
        let now = Date()
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        return SkillCollection(
            id: "collection.\(suffix)",
            name: "New collection",
            description: "",
            includedTags: [],
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - Connection

/// Catalog of services we know how to integrate with. Adding a new
/// service is a deliberate change (UI, OAuth/token flow, watchers in
/// `clawjs-integrations`), so this enum is intentionally finite rather
/// than free-string.
enum ConnectionService: String, CaseIterable, Identifiable, Codable {
    case telegram
    case slack
    case discord
    case email
    case sms
    case webhook
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .telegram: return "Telegram"
        case .slack:    return "Slack"
        case .discord:  return "Discord"
        case .email:    return "Email"
        case .sms:      return "SMS"
        case .webhook:  return "Webhook"
        case .custom:   return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .telegram: return "paperplane"
        case .slack:    return "number"
        case .discord:  return "gamecontroller"
        case .email:    return "envelope"
        case .sms:      return "message"
        case .webhook:  return "link"
        case .custom:   return "puzzlepiece.extension"
        }
    }
}

struct Connection: Identifiable, Equatable, Codable {
    var id: String
    var service: ConnectionService
    var label: String
    /// Free-form scopes (e.g. `["chat:read", "chat:write"]` for Slack,
    /// `["bot"]` for Telegram). Surfaced in the connection card.
    var scopes: [String]
    var lastSyncAt: Date?
    var createdAt: Date
    var updatedAt: Date

    static func newDraft(service: ConnectionService = .telegram) -> Connection {
        let now = Date()
        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        return Connection(
            id: "connection.\(service.rawValue).\(suffix)",
            service: service,
            label: "New \(service.label) connection",
            scopes: [],
            lastSyncAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - Audit log entry

struct AgentAuditEntry: Identifiable, Equatable, Codable {
    var id: String
    var timestamp: Date
    var actorAgentId: String
    var subjectAgentId: String?
    var action: String
    var result: String
    var note: String?
}

// MARK: - Avatar palette

/// Rotating palette used for fresh `Agent` drafts so the home grid is
/// immediately visually distinct without forcing the user to pick a
/// tint up front. The next-call cursor advances per-call so consecutive
/// "New agent" actions paint different colours.
enum AgentAvatarPalette {
    private static let colors: [String] = [
        "#7C9CFF", // periwinkle
        "#F2A1C2", // pink
        "#FFCC66", // amber
        "#7BD3EA", // teal
        "#B3A7FF", // lavender
        "#86E3A0", // mint
        "#FF8E72", // coral
        "#E0AAFF"  // orchid
    ]
    private static var cursor: Int = 0

    static func next() -> String {
        let c = colors[cursor % colors.count]
        cursor += 1
        return c
    }
}

// The Color(hex:) initializer used by `AgentAvatar.tintColor` is
// declared by `ProviderBrandIcon.swift` so there is exactly one
// hex-decoding helper in the target.
