import Foundation

// MARK: - Kind / Scope / SyncMode

/// Subtype of a skill, surfaced as a filter chip and as an icon in the
/// catalog grid. Maps to `metadata.clawjs.kind` in the SKILL.md
/// frontmatter (agentskills.io standard) and to the directory under
/// `~/.clawjs/skills/<kind>/<slug>/SKILL.md` where the file lives.
enum SkillKind: String, Codable, CaseIterable, Identifiable {
    /// "How the agent thinks/talks/decides." Replaces ClawJS Soul.
    /// Only one is meaningfully active at the top of the system prompt;
    /// the user can stack more but they get concatenated, not blended.
    case personality
    /// "How to do X." Procedural recipe with optional parameters
    /// (tone/length/intent etc.). Most skills are procedures.
    case procedure
    /// "A bit of context to inject." Short reusable instruction block —
    /// the building-block primitive ("how to use Cloudflare with my secrets").
    case snippet
    /// "A bundle of personality + procedures + snippets." Curated combo,
    /// e.g. a `devops-cloudflare` role pulling several pieces together.
    case role

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personality: return "Personality"
        case .procedure:   return "Procedure"
        case .snippet:     return "Snippet"
        case .role:        return "Role"
        }
    }

    var icon: String {
        switch self {
        case .personality: return "person.crop.circle"
        case .procedure:   return "list.bullet.rectangle"
        case .snippet:     return "doc.text"
        case .role:        return "rectangle.3.group"
        }
    }
}

/// Where a skill applies. Resolved at thread-start time into a single
/// active set per `(projectId, chatId)` context with chat > project >
/// global priority.
enum SkillScopeKind: String, Codable, CaseIterable {
    case global
    case project
    case tag
    case chat
}

struct SkillScope: Codable, Equatable, Hashable {
    var kind: SkillScopeKind
    /// Populated when `kind == .project`. Multiple ids → skill applies
    /// to any chat in any of those projects.
    var projectIds: [String]
    /// Populated when `kind == .tag`. The runtime treats tag-scoped
    /// skills as available everywhere; the user opts in per chat.
    var tagNames: [String]
    /// Populated when `kind == .chat`. UUID stringified.
    var chatIds: [String]

    static let global = SkillScope(kind: .global, projectIds: [], tagNames: [], chatIds: [])

    init(kind: SkillScopeKind, projectIds: [String] = [], tagNames: [String] = [], chatIds: [String] = []) {
        self.kind = kind
        self.projectIds = projectIds
        self.tagNames = tagNames
        self.chatIds = chatIds
    }
}

enum SkillSyncMode: String, Codable, CaseIterable {
    case symlink
    case copy
}

// MARK: - Param schema (for parametrizable templates)

enum SkillParamType: String, Codable, CaseIterable {
    case string
    case enumValue = "enum"
    case number
    case bool
    /// Reference to a Secrets-Vault secret. The UI shows a secret picker.
    case secretRef
}

struct SkillParam: Codable, Equatable, Identifiable, Hashable {
    var key: String
    var label: String
    var type: SkillParamType
    /// Populated when `type == .enumValue`.
    var options: [String]?
    /// Default value (any JSON-compatible primitive).
    var defaultValue: SkillParamValue?
    var required: Bool
    /// Help text shown below the form field.
    var prompt: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, type, options, required, prompt
        case defaultValue = "default"
    }
}

/// Tagged union of values a `SkillParam` can hold. Mirrors what
/// SKILL.md frontmatter can declare (string/number/bool/enum). The
/// `secretRef` case carries the secret id; the daemon fetches the
/// actual value from the Vault at compile time and never lets it
/// reach the LLM as a literal in clear text.
enum SkillParamValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case secretRef(id: String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        // {"$secret": "id"} encoding for secret refs.
        struct SecretEnvelope: Codable { let secret: String; enum CodingKeys: String, CodingKey { case secret = "$secret" } }
        if let env = try? c.decode(SecretEnvelope.self) { self = .secretRef(id: env.secret); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported SkillParamValue")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s):   try c.encode(s)
        case .number(let n):   try c.encode(n)
        case .bool(let b):     try c.encode(b)
        case .secretRef(let id): try c.encode(["$secret": id])
        }
    }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"
        case .bool(let b):   return b ? "true" : "false"
        case .secretRef(let id): return "secret:\(id)"
        }
    }
}

// MARK: - Capsule

/// Short context block (≤300 chars) that gets injected EARLY in the
/// system prompt before the full skill body. Designed for
/// progressive-disclosure agents that read the capsule first and only
/// pull the rest when the task matches.
struct SkillCapsule: Codable, Equatable, Hashable {
    var text: String
    var priority: Int
    /// Activation hints. The runtime currently uses these as searchable
    /// tags only; future versions may use them for auto-pulling the
    /// full body when the user message matches.
    var readWhen: [String]
}

// MARK: - Instance

/// Marker that a skill is a configured instance of another (template).
/// When `frozen == false`, the runtime renders the body by reading the
/// template's body and substituting `params`. When `frozen == true`,
/// the body is pre-rendered and saved literally; the link to
/// `ofTemplate` is dropped so future template changes don't drift in.
struct SkillInstanceRef: Codable, Equatable, Hashable {
    var ofTemplate: String
    var params: [String: SkillParamValue]
    var frozen: Bool
}

// MARK: - Soul module data (kind: personality)

/// Subset of the 14-module SoulSpec the personality kind preserves on
/// disk so the params form can render the same sliders / dropdowns the
/// ClawJS Soul UI uses. The body of the SKILL.md is the compiled prose
/// version (what `clawjs soul compile` already produces). On disk this
/// is just YAML inside `metadata.clawjs.soul`.
struct SkillSoulModules: Codable, Equatable, Hashable {
    /// Which preset (engineer, executive, tutor, ...) this personality
    /// was forked from, if any.
    var presetId: String?
    /// Free-form bag for the 14 modules. Untyped at this layer because
    /// the Swift side only renders/round-trips them — the structure is
    /// owned by ClawJS. Using a JSON-value encoding so we don't need
    /// to mirror every field shape on Swift.
    var modules: [String: SkillJSONValue]
}

/// Minimal JSON value carrier so we can round-trip the soul modules
/// (and other untyped extension fields) without pinning every shape.
indirect enum SkillJSONValue: Codable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SkillJSONValue])
    case object([String: SkillJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([SkillJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: SkillJSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .number(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }
}

// MARK: - Curated preset (child of a parametrizable template)

/// A parametrizable template can declare a curated list of presets that
/// render as child rows in the catalog UI. Picking one creates an
/// instance with those params (still `frozen: false` by default so the
/// user gets template updates).
struct SkillPreset: Codable, Equatable, Identifiable, Hashable {
    var slug: String
    var label: String
    var params: [String: SkillParamValue]

    var id: String { slug }
}

// MARK: - SkillSpec

/// Materialized view of one SKILL.md file. The Swift side never writes
/// directly to disk — it round-trips through the bridge / SkillsStore
/// to keep ClawJS as the single source of truth. The `body` is already
/// markdown (rendered if this is a non-frozen instance).
struct SkillSpec: Codable, Equatable, Identifiable, Hashable {
    var slug: String
    var name: String
    var description: String
    var version: String
    var kind: SkillKind
    var body: String
    var scope: SkillScope
    var tags: [String]
    var syncTo: [String]
    var syncMode: SkillSyncMode
    var params: [SkillParam]?
    var instance: SkillInstanceRef?
    var capsule: SkillCapsule?
    /// Only present for `kind == .personality`.
    var soul: SkillSoulModules?
    /// Only present on parametrizable templates that have curated
    /// children.
    var presets: [SkillPreset]?
    /// Distribution metadata.
    var builtin: Bool
    /// "codex" / "hermes" / "cursor" / nil. Set when the auto-importer
    /// pulled this skill in from an external agent's home dir.
    var importedFrom: String?
    /// Author label as shown in the UI. Free-form.
    var author: String?
    /// ISO-8601 last update timestamp, used for "updated 2 days ago".
    var updatedAt: String?

    var id: String { slug }

    /// Convenience: is this a parametrizable template that the user
    /// can configure? (params declared, not itself an instance)
    var isTemplate: Bool { (params?.isEmpty == false) && instance == nil }

    /// Convenience: is this a saved configured instance of a template?
    var isInstance: Bool { instance != nil }
}

// MARK: - Sync targets (configured externally, in ClawJS config.yaml)

struct SkillSyncTarget: Codable, Equatable, Identifiable, Hashable {
    var id: String          // e.g. "codex", "hermes", "cursor-myproject"
    var label: String       // human-readable
    var home: String        // expanded path on disk
    var mode: SkillSyncMode
    /// Health: when did the last sync run finish; was it successful.
    var lastSyncedAt: String?
    var lastError: String?
}

// MARK: - Active skill state (UI side, per scope)

/// What the user has toggled "on" at a given scope. Translated into
/// `[ActiveSkill]` for the wire when `ThreadStartParams` /
/// `TurnStartParams` are constructed.
struct ActiveSkillState: Equatable, Hashable, Identifiable {
    let slug: String
    let kind: SkillKind
    /// "global" | "project:<id>" | "chat:<id>"
    let scopeTag: String
    /// Stable across sessions, lower = earlier in the prompt.
    let priority: Int
    /// Set when activating an instance with the runtime override of
    /// the template's params. nil for plain skills.
    let params: [String: SkillParamValue]?

    var id: String { "\(scopeTag):\(slug)" }
}

// NOTE: iOS v1 of Skills is read/browse-only. The daemon never asks
// iOS for activation toggles — those are owned by the Mac app and
// arrive cross-device via `skillsActiveChanged` once the v6 bridge
// frames land (Phase 5 daemon-side, currently TODO). When iOS gets
// write capability, port `toWire()` from the macOS copy of this file
// and connect it to the iOS BridgeStore. Not implemented here to
// avoid a half-finished surface that ships before the bridge does.
