import Foundation

// Minimal Codable types for the JSON-RPC 2.0 protocol exposed by
// `clawix app-server --listen stdio://`. Only the v1 surface that
// Clawix touches (initialize + thread/turn for streaming chat) is
// modeled. Everything else is read as raw JSON via `JSONValue` and
// only decoded on demand.
//
// Reference (committed in Resources/clawix-schema/):
//   ClientRequest.json, ClientNotification.json, ServerNotification.json,
//   v2/{ThreadStartParams, TurnStartParams, AgentMessageDeltaNotification,
//        ItemStartedNotification, …}.json
//
// Field names match the schema exactly (camelCase, no remapping).

// MARK: - JSON-RPC envelopes

enum ClawixRPCID: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.typeMismatch(
            ClawixRPCID.self,
            .init(codingPath: decoder.codingPath, debugDescription: "id must be int or string")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

struct ClawixOutgoingRequest<P: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: P
}

struct ClawixOutgoingNotification<P: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: P
}

struct ClawixOutgoingResponse<R: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: ClawixRPCID
    let result: R
}

struct ClawixErrorBody: Codable {
    let code: Int
    let message: String
    let data: JSONValue?
}

struct ClawixOutgoingErrorResponse: Encodable {
    let jsonrpc = "2.0"
    let id: ClawixRPCID
    let error: ClawixErrorBody
}

// Single shape for any inbound message. The dispatcher inspects which
// fields are present (`id`/`method`/`result`/`error`) to decide whether
// it is a response, a server-initiated request, or a notification.
struct ClawixIncomingMessage: Decodable {
    let jsonrpc: String?
    let id: ClawixRPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: ClawixErrorBody?
}

// MARK: - Method names (just constants so we don't typo)

enum ClawixMethod {
    static let initialize        = "initialize"
    static let initialized       = "initialized"      // notification
    static let threadStart       = "thread/start"
    static let threadResume      = "thread/resume"
    static let threadFork        = "thread/fork"
    static let threadRollback    = "thread/rollback"
    static let threadList        = "thread/list"
    static let threadSetName     = "thread/name/set"
    static let threadArchive     = "thread/archive"
    static let threadUnarchive   = "thread/unarchive"
    static let turnStart         = "turn/start"
    static let turnInterrupt     = "turn/interrupt"
    static let modelList         = "model/list"
    static let accountRateLimitsRead = "account/rateLimits/read"

    // Server -> client notifications
    static let nThreadStarted    = "thread/started"
    static let nThreadArchived   = "thread/archived"
    static let nThreadUnarchived = "thread/unarchived"
    static let nThreadNameUpdated = "thread/name/updated"
    static let nTurnStarted      = "turn/started"
    static let nTurnCompleted    = "turn/completed"
    static let nItemStarted      = "item/started"
    static let nItemCompleted    = "item/completed"
    static let nAgentMsgDelta    = "item/agentMessage/delta"
    static let nReasoningDelta   = "item/reasoning/textDelta"
    static let nReasoningSumDelta = "item/reasoning/summaryTextDelta"
    static let nThreadTokenUsage = "thread/tokenUsage/updated"
    static let nAccountRateLimitsUpdated = "account/rateLimits/updated"
    static let nError            = "error"

    // Server -> client requests we know how to refuse safely
    static let rFileChangeApproval     = "item/fileChange/requestApproval"
    static let rExecApproval           = "item/commandExecution/requestApproval"
    static let rPermissionsApproval    = "item/permissions/requestApproval"
    static let rToolUserInput          = "item/tool/requestUserInput"
    static let rChatgptAuthRefresh     = "account/chatgptAuthTokens/refresh"
}

// MARK: - initialize

struct InitializeClientInfo: Encodable {
    let name: String
    let title: String?
    let version: String
}

struct InitializeCapabilities: Encodable {
    /// Opt into experimental API methods and fields (e.g. `collaborationMode`
    /// on `turn/start` and `thread/start`). Without this, the daemon rejects
    /// turn/start with -32600 "requires experimentalApi capability".
    let experimentalApi: Bool?
    let optOutNotificationMethods: [String]?
}

struct InitializeParams: Encodable {
    let clientInfo: InitializeClientInfo
    let capabilities: InitializeCapabilities?
}

// MARK: - thread/start

struct ThreadStartParams: Encodable {
    let cwd: String?
    let model: String?
    let approvalPolicy: String?      // "never" | "on-request" | "untrusted" | "on-failure"
    let sandbox: String?             // "read-only" | "workspace-write" | "danger-full-access"
    let personality: String?         // "none" | "friendly" | "pragmatic" (legacy; subsumed by activeSkills kind=personality)
    /// "fast" | "flex" | nil. Matches the composer's speed picker.
    let serviceTier: String?
    /// Skills active for this thread, resolved by the client from the
    /// global/project/chat hierarchy. Order matters: lower priority
    /// concatenated first, higher priority later (so it overrides).
    /// The daemon resolves slugs into SKILL.md content via ClawJS and
    /// prepends the compiled fragment to the system prompt before
    /// dispatching to Codex.
    let activeSkills: [ActiveSkill]?
    /// EXPERIMENTAL. Switches the session into collaboration mode
    /// machinery. `mode = "plan"` arms the agent to consult the user via
    /// `item/tool/requestUserInput`; `mode = "default"` is execute-as-you-go.
    let collaborationMode: CollaborationModePayload?
}

/// Wire description of a skill the thread should boot with. Only the
/// slug travels; the daemon owns the SKILL.md filesystem and reads the
/// body itself, keeping the request small. `params` is set when the
/// active entry refers to a parametrizable template instance — the
/// daemon substitutes them while rendering the body.
struct ActiveSkill: Encodable {
    /// Stable slug as it appears under `~/.clawjs/skills/<kind>/<slug>/`.
    let slug: String
    /// "personality" | "procedure" | "snippet" | "role". Helps the daemon
    /// place the rendered fragment in the right slot of the compiled
    /// system prompt (personality first, then snippets, then procedures).
    let kind: String
    /// "global" | "project:<id>" | "chat:<id>". Lets the daemon log/audit
    /// where the activation came from without re-resolving on its side.
    let scope: String
    /// Lower numbers concatenate first; higher numbers override. Default
    /// 0 when not known. Daemon stable-sorts on this before compiling.
    let priority: Int
    /// Free-form key/value bag for parametrized template instances. nil
    /// for plain skills that don't take params. Values are encoded as
    /// JSON-compatible primitives; the daemon substitutes them into the
    /// body following the SKILL.md template conventions.
    let params: [String: JSONValue]?
}

/// EXPERIMENTAL. Recent runtimes accept this payload on
/// thread/start and turn/start to switch the session into plan mode.
/// Older daemons silently ignore the unknown key.
struct CollaborationModePayload: Encodable {
    let mode: String                 // "plan" | "default"
    let settings: CollaborationModeSettingsPayload
}

struct CollaborationModeSettingsPayload: Encodable {
    let model: String                // required by the schema
    let developer_instructions: String?
    let reasoning_effort: String?
}

struct ThreadHandle: Decodable {
    let id: String
    let cwd: String?
    let createdAt: String?
    let cliVersion: String?

    enum CodingKeys: String, CodingKey {
        case id, cwd, createdAt, cliVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        self.cliVersion = try c.decodeIfPresent(String.self, forKey: .cliVersion)
        // The CLI sometimes emits createdAt as a Unix timestamp (number) and
        // sometimes as an ISO-8601 string. Accept both, normalize to String.
        if let s = try? c.decodeIfPresent(String.self, forKey: .createdAt) {
            self.createdAt = s
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .createdAt) {
            self.createdAt = String(d)
        } else {
            self.createdAt = nil
        }
    }
}

struct ThreadStartResult: Decodable {
    let thread: ThreadHandle
    let model: String?
}

// MARK: - thread/resume

struct ThreadResumeParams: Encodable {
    let threadId: String
}

// Same shape as start
typealias ThreadResumeResult = ThreadStartResult

// MARK: - turn/start

/// One element of `turn/start`'s `input` array. Codex's app-server
/// protocol accepts a small discriminated union of input items. We
/// support `text` for the prompt body and `localImage` for inline image
/// attachments materialized to temp files (the daemon's wire protocol
/// uses the same shape, see `clawix-bridged`'s mirror enum). Encoding
/// is hand-rolled because Codable's default derivation would emit both
/// fields for every case.
enum TurnStartUserInput: Encodable {
    case text(String)
    case localImage(path: String)

    private enum Keys: String, CodingKey {
        case type, text, path
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let body):
            try c.encode("text", forKey: .type)
            try c.encode(body, forKey: .text)
        case .localImage(let path):
            try c.encode("localImage", forKey: .type)
            try c.encode(path, forKey: .path)
        }
    }
}

struct TurnStartParams: Encodable {
    let threadId: String
    let input: [TurnStartUserInput]
    let model: String?
    let effort: String?              // "none" | "minimal" | "low" | "medium" | "high" | "xhigh"
    /// "fast" | "flex" | nil. Matches the composer's speed picker
    /// (Standard = nil → default tier, Fast = "fast" → priority queue).
    let serviceTier: String?
    /// Per-turn override of the thread's active skill set. nil means
    /// "reuse what was on `thread/start`". Useful when the user toggles
    /// a skill after the thread has booted; the next turn carries the
    /// fresh list and the daemon recomputes the prompt prelude.
    let activeSkills: [ActiveSkill]?
    /// EXPERIMENTAL. Same shape as on ThreadStartParams; per-turn override
    /// so the user can flip plan mode on/off without restarting the thread.
    let collaborationMode: CollaborationModePayload?
}

struct TurnHandle: Decodable {
    let id: String
}

struct TurnStartResult: Decodable {
    let turn: TurnHandle
}

// MARK: - turn/interrupt

struct TurnInterruptParams: Encodable {
    let threadId: String
    let turnId: String
}

struct TurnInterruptResult: Decodable {}

// MARK: - thread/fork
//
// Forks an existing thread into a new one that mirrors the parent's
// rollout up to the latest turn. The runtime writes the new
// `session_meta` with `forked_from_id` pointing back at the parent and
// copies every prior event into the new rollout, so the forked thread
// resumes with the same context. After the call lands we behave like
// any freshly-created thread: turn/start, deltas, etc.

struct ThreadForkParams: Encodable {
    let threadId: String
    /// When true, the response omits `thread.turns` so we don't pay the
    /// cost of receiving the full turn list when the client already has
    /// the local copy.
    let excludeTurns: Bool?
}

typealias ThreadForkResult = ThreadStartResult

// MARK: - thread/rollback
//
// Drops `numTurns` turns from the end of the thread on disk. We use it
// to implement "edit a previous user message": rollback up to (and
// including) the turn that started with the edited user prompt, then
// re-issue `turn/start` with the new text. The server returns the
// updated thread; we just need to know it succeeded, so the result is
// decoded as an empty object.

struct ThreadRollbackParams: Encodable {
    let threadId: String
    let numTurns: Int
}

struct ThreadRollbackResult: Decodable {}

// MARK: - thread/list + runtime mutations

struct ThreadListParams: Encodable {
    let archived: Bool?
    let cursor: String?
    let cwd: String?
    let limit: Int?
    let modelProviders: [String]?
    let searchTerm: String?
    let sortDirection: String?
    let sortKey: String?
    let sourceKinds: [String]?
    let useStateDbOnly: Bool?
}

struct ThreadListResponse: Decodable {
    let data: [AgentThreadSummary]
    let nextCursor: String?
    let backwardsCursor: String?
}

struct ThreadSetNameParams: Encodable {
    let threadId: String
    let name: String
}

struct ThreadSetNameResponse: Decodable {}

struct ThreadArchiveParams: Encodable {
    let threadId: String
}

struct ThreadArchiveResponse: Decodable {}

struct ThreadUnarchiveParams: Encodable {
    let threadId: String
}

struct ThreadUnarchiveResponse: Decodable {}

struct ThreadIdNotification: Decodable {
    let threadId: String
}

struct ThreadNameUpdatedNotification: Decodable {
    let threadId: String
    let threadName: String?
}

// MARK: - notifications we consume

// item/agentMessage/delta
struct AgentMessageDelta: Decodable {
    let delta: String
    let itemId: String
    let threadId: String
    let turnId: String
}

// item/reasoning/textDelta and item/reasoning/summaryTextDelta share shape
struct ReasoningTextDelta: Decodable {
    let delta: String
    let itemId: String
    let threadId: String
    let turnId: String
}

// item/started and item/completed
//
// `item.type` is the discriminator we care about. The payload is a union
// of all known thread item shapes (CommandExecutionThreadItem,
// FileChangeThreadItem, WebSearchThreadItem, McpToolCallThreadItem,
// DynamicToolCallThreadItem, AgentMessageThreadItem, …); every type-
// specific field is optional so a single struct can decode any of them.
struct ItemEnvelope: Decodable {
    let item: ItemPayload
    let threadId: String
    let turnId: String
}

struct ItemPayload: Decodable {
    let id: String
    let type: String

    // agentMessage
    let text: String?

    // commandExecution
    let command: String?
    let commandActions: [CommandActionPayload]?
    let status: String?
    let durationMs: Int64?

    // fileChange
    let changes: [FileChangePayload]?

    // webSearch
    let query: String?

    // mcpToolCall / dynamicToolCall
    let server: String?
    let tool: String?
}

struct CommandActionPayload: Decodable {
    /// "read" | "listFiles" | "search" | "unknown"
    let type: String
    let path: String?
    let name: String?
    let query: String?
    let command: String?
}

struct FileChangePayload: Decodable {
    let path: String
}

// turn/started, turn/completed
struct TurnEnvelope: Decodable {
    let threadId: String
    let turn: TurnPayload
}

struct TurnPayload: Decodable {
    let id: String
    let status: String?              // "in_progress" | "completed" | …
    let error: JSONValue?
}

// thread/started
struct ThreadStartedEnvelope: Decodable {
    let thread: ThreadHandle
}

// thread/tokenUsage/updated
struct ThreadTokenUsageEnvelope: Decodable {
    let threadId: String
    let turnId: String
    let tokenUsage: ThreadTokenUsage
}

struct ThreadTokenUsage: Decodable, Equatable {
    let last: TokenUsageBreakdown
    let total: TokenUsageBreakdown
    let modelContextWindow: Int64?
}

struct TokenUsageBreakdown: Decodable, Equatable {
    let cachedInputTokens: Int64
    let inputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64
}

// MARK: - server-initiated requests (refused in v1)

struct ApprovalDecisionResponse: Encodable {
    let decision: String             // "decline"
}

// MARK: - item/tool/requestUserInput (plan mode questions)

struct ToolRequestUserInputParams: Decodable {
    let itemId: String
    let threadId: String
    let turnId: String
    let questions: [ToolRequestUserInputQuestion]
}

struct ToolRequestUserInputQuestion: Decodable, Identifiable {
    let id: String
    let header: String
    let question: String
    let options: [ToolRequestUserInputOption]?
    let isOther: Bool?
    let isSecret: Bool?
}

struct ToolRequestUserInputOption: Decodable, Hashable {
    let label: String
    let description: String
}

struct ToolRequestUserInputResponse: Encodable {
    /// Schema requires every question id be present in the answers map,
    /// even when only one was answered. Callers fill missing keys with
    /// `ToolRequestUserInputAnswer(answers: [])` for "no answer".
    let answers: [String: ToolRequestUserInputAnswer]
}

struct ToolRequestUserInputAnswer: Encodable {
    let answers: [String]
}

// model/list

struct ModelListEntry: Decodable {
    let slug: String?
    let displayName: String?
    let id: String?
}

struct ModelListResult: Decodable {
    let data: [ModelListEntry]?
}

// MARK: - account/rateLimits

struct RateLimitWindow: Decodable, Equatable {
    let usedPercent: Int
    let resetsAt: Int64?
    let windowDurationMins: Int64?
}

struct CreditsSnapshot: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct RateLimitSnapshot: Decodable, Equatable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
    let limitId: String?
    let limitName: String?
}

struct GetAccountRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    /// Per-bucket view keyed by metered `limit_id` (e.g. "codex",
    /// "codex_<model>"). Optional because older daemons only emit the
    /// top-level `rateLimits` field.
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

struct AccountRateLimitsUpdatedNotification: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

// MARK: - JSONValue (untyped JSON)

indirect enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let arr = try? c.decode([JSONValue].self) { self = .array(arr); return }
        if let obj = try? c.decode([String: JSONValue].self) { self = .object(obj); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
