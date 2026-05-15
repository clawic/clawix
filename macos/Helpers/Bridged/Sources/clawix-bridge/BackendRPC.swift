import Foundation

actor BackendClient {
    private let binary: BackendBinary
    private var process: Process?
    private var stdin: Pipe?
    private var stdoutBuffer = Data()
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<JSONValue?, Error>] = [:]
    private let continuationBox = EventContinuationBox()
    nonisolated let events: AsyncStream<BackendEvent>

    init(binary: BackendBinary) {
        self.binary = binary
        var captured: AsyncStream<BackendEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        continuationBox.continuation = captured
    }

    func start() throws {
        guard process == nil else { return }
        let proc = Process()
        proc.executableURL = binary.path
        proc.arguments = ["app-server", "--listen", "stdio://"]
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = nil
        proc.environment = env
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = error
        stdin = input
        attachStdout(output)
        attachStderr(error)
        try proc.run()
        process = proc
        proc.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }
    }

    func send<P: Encodable>(method: String, params: P, timeoutSeconds: TimeInterval? = nil) async throws -> JSONValue? {
        guard process != nil else { throw BackendError.notRunning }
        let id = nextId
        nextId += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            if let timeoutSeconds {
                let nanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    await self?.timeoutPending(id: id, method: method, seconds: timeoutSeconds)
                }
            }
            do {
                try write(BackendRequest(id: id, method: method, params: params))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    func send<P: Encodable, R: Decodable>(method: String, params: P, expecting: R.Type, timeoutSeconds: TimeInterval? = nil) async throws -> R {
        guard let raw = try await send(method: method, params: params, timeoutSeconds: timeoutSeconds) else {
            throw BackendError.invalidResponse
        }
        return try raw.decode(R.self)
    }

    func notify<P: Encodable>(method: String, params: P) throws {
        try write(BackendNotification(method: method, params: params))
    }

    nonisolated func resolve<R: Encodable>(id: RPCID, result: R) throws {
        Task { try await self.write(BackendResponse(id: id, result: result)) }
    }

    private func attachStdout(_ pipe: Pipe) {
        let weak = WeakBackend(self)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            Task { await weak.value?.appendStdout(data) }
        }
    }

    private func attachStderr(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                BridgeLog.write("backend stderr \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }

    private func appendStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0a) {
            let line = stdoutBuffer.subdata(in: 0..<nl)
            stdoutBuffer.removeSubrange(0...nl)
            guard !line.isEmpty else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard let message = try? JSONDecoder().decode(BackendIncoming.self, from: data) else { return }
        if let id = message.id, message.method == nil {
            guard case .int(let intId) = id, let continuation = pending.removeValue(forKey: intId) else { return }
            if let error = message.error {
                continuation.resume(throwing: BackendError.rpc(error.message))
            } else {
                continuation.resume(returning: message.result)
            }
            return
        }
        if let method = message.method {
            if let id = message.id {
                continuationBox.continuation?.yield(.request(id: id, method: method, params: message.params))
            } else {
                continuationBox.continuation?.yield(.notification(method: method, params: message.params))
            }
        }
    }

    private func write<T: Encodable>(_ value: T) throws {
        guard let stdin else { throw BackendError.notRunning }
        let data = try JSONEncoder().encode(value) + Data([0x0a])
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }

    private func timeoutPending(id: Int, method: String, seconds: TimeInterval) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        BridgeLog.write("backend request timeout method=\(method) seconds=\(seconds)")
        continuation.resume(throwing: BackendError.timeout(method, seconds))
    }

    private func handleTermination() {
        process = nil
        for continuation in pending.values {
            continuation.resume(throwing: BackendError.notRunning)
        }
        pending.removeAll()
    }
}

final class EventContinuationBox: @unchecked Sendable {
    var continuation: AsyncStream<BackendEvent>.Continuation?
}

final class WeakBackend: @unchecked Sendable {
    weak var value: BackendClient?
    init(_ value: BackendClient) { self.value = value }
}

enum BackendEvent {
    case notification(method: String, params: JSONValue?)
    case request(id: RPCID, method: String, params: JSONValue?)
}

enum BackendError: Error, CustomStringConvertible {
    case notRunning
    case invalidResponse
    case rpc(String)
    case timeout(String, TimeInterval)

    var description: String {
        switch self {
        case .notRunning: return "backend not running"
        case .invalidResponse: return "invalid backend response"
        case .rpc(let message): return message
        case .timeout(let method, let seconds): return "\(method) timed out after \(Int(seconds))s"
        }
    }
}

struct BackendRequest<P: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: P
}

struct BackendNotification<P: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: P
}

struct BackendResponse<R: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RPCID
    let result: R
}

struct BackendIncoming: Decodable {
    let id: RPCID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: BackendRPCError?
}

struct BackendRPCError: Decodable {
    let code: Int
    let message: String
}

enum RPCID: Codable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let int = try? c.decode(Int.self) {
            self = .int(int)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let int): try c.encode(int)
        case .string(let string): try c.encode(string)
        }
    }
}

struct InitializeClientInfo: Encodable {
    let name: String
    let title: String?
    let version: String
}

struct InitializeCapabilities: Encodable {
    let extensionFields: Bool?
    let optOutNotificationMethods: [String]?

    enum CodingKeys: String, CodingKey {
        case extensionFields = "experimentalApi"
        case optOutNotificationMethods
    }
}

struct InitializeParams: Encodable {
    let clientInfo: InitializeClientInfo
    let capabilities: InitializeCapabilities?
}

struct EmptyObject: Encodable {}
struct EmptyResponse: Decodable {}

// MARK: - Codex `account/rateLimits` types

/// Mirrors the GUI target's `RateLimitWindow` (see
/// `clawix/macos/Sources/Clawix/AgentBackend/ClawixProtocol.swift`).
/// Decoded straight off `account/rateLimits/read.rateLimits.primary`
/// (and `secondary`, and the per-bucket entries inside
/// `rateLimitsByLimitId`). New fields Codex adds (planType,
/// rateLimitReachedType) decode-tolerantly because we only pull the
/// keys we declare here.
struct DaemonRateLimitWindow: Decodable {
    let usedPercent: Int
    let resetsAt: Int64?
    let windowDurationMins: Int64?

    init(usedPercent: Int, resetsAt: Int64?, windowDurationMins: Int64?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleRateLimitKey.self)
        self.usedPercent = try c.decodeFlexiblePercent(keys: ["usedPercent", "used_percent"])
        self.resetsAt = try c.decodeFlexibleIfPresent(Int64.self, keys: ["resetsAt", "resets_at"])
        self.windowDurationMins = try c.decodeFlexibleIfPresent(Int64.self, keys: ["windowDurationMins", "window_minutes", "windowMinutes"])
    }
}

struct DaemonCreditsSnapshot: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleRateLimitKey.self)
        self.hasCredits = try c.decodeFlexible(Bool.self, keys: ["hasCredits", "has_credits"])
        self.unlimited = try c.decodeFlexible(Bool.self, keys: ["unlimited"])
        self.balance = try c.decodeFlexibleIfPresent(String.self, keys: ["balance"])
    }
}

struct DaemonRateLimitSnapshot: Decodable {
    let primary: DaemonRateLimitWindow?
    let secondary: DaemonRateLimitWindow?
    let credits: DaemonCreditsSnapshot?
    let limitId: String?
    let limitName: String?

    init(
        primary: DaemonRateLimitWindow?,
        secondary: DaemonRateLimitWindow?,
        credits: DaemonCreditsSnapshot?,
        limitId: String?,
        limitName: String?
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.limitId = limitId
        self.limitName = limitName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleRateLimitKey.self)
        self.primary = try c.decodeFlexibleIfPresent(DaemonRateLimitWindow.self, keys: ["primary"])
        self.secondary = try c.decodeFlexibleIfPresent(DaemonRateLimitWindow.self, keys: ["secondary"])
        self.credits = try c.decodeFlexibleIfPresent(DaemonCreditsSnapshot.self, keys: ["credits"])
        self.limitId = try c.decodeFlexibleIfPresent(String.self, keys: ["limitId", "limit_id"])
        self.limitName = try c.decodeFlexibleIfPresent(String.self, keys: ["limitName", "limit_name"])
    }
}

struct DaemonGetAccountRateLimitsResponse: Decodable {
    let rateLimits: DaemonRateLimitSnapshot
    let rateLimitsByLimitId: [String: DaemonRateLimitSnapshot]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleRateLimitKey.self)
        self.rateLimits = try c.decodeFlexible(DaemonRateLimitSnapshot.self, keys: ["rateLimits", "rate_limits"])
        self.rateLimitsByLimitId = try c.decodeFlexibleIfPresent(
            [String: DaemonRateLimitSnapshot].self,
            keys: ["rateLimitsByLimitId", "rate_limits_by_limit_id"]
        )
    }
}

struct DaemonAccountRateLimitsUpdatedNotification: Decodable {
    let rateLimits: DaemonRateLimitSnapshot
    let rateLimitsByLimitId: [String: DaemonRateLimitSnapshot]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleRateLimitKey.self)
        self.rateLimits = try c.decodeFlexible(DaemonRateLimitSnapshot.self, keys: ["rateLimits", "rate_limits"])
        self.rateLimitsByLimitId = try c.decodeFlexibleIfPresent(
            [String: DaemonRateLimitSnapshot].self,
            keys: ["rateLimitsByLimitId", "rate_limits_by_limit_id"]
        )
    }
}

private struct FlexibleRateLimitKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == FlexibleRateLimitKey {
    func decodeFlexible<T: Decodable>(_ type: T.Type, keys: [String]) throws -> T {
        for key in keys {
            guard let codingKey = FlexibleRateLimitKey(stringValue: key), contains(codingKey) else { continue }
            return try decode(type, forKey: codingKey)
        }
        throw DecodingError.keyNotFound(
            FlexibleRateLimitKey(stringValue: keys.first ?? "")!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing any of keys: \(keys.joined(separator: ", "))")
        )
    }

    func decodeFlexibleIfPresent<T: Decodable>(_ type: T.Type, keys: [String]) throws -> T? {
        for key in keys {
            guard let codingKey = FlexibleRateLimitKey(stringValue: key), contains(codingKey) else { continue }
            return try decodeIfPresent(type, forKey: codingKey)
        }
        return nil
    }

    func decodeFlexiblePercent(keys: [String]) throws -> Int {
        for key in keys {
            guard let codingKey = FlexibleRateLimitKey(stringValue: key), contains(codingKey) else { continue }
            if let value = try? decode(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try? decode(Double.self, forKey: codingKey) {
                return Int(value.rounded())
            }
        }
        throw DecodingError.keyNotFound(
            FlexibleRateLimitKey(stringValue: keys.first ?? "")!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing percent key: \(keys.joined(separator: ", "))")
        )
    }
}

struct ThreadStartParams: Encodable {
    let cwd: String?
    let model: String?
    let approvalPolicy: String?
    let sandbox: String?
    let personalizationPreset: String?
    let serviceTier: String?
    let collaborationMode: CollaborationModePayload?

    enum CodingKeys: String, CodingKey {
        case cwd
        case model
        case approvalPolicy
        case sandbox
        case personalizationPreset = "personality"
        case serviceTier
        case collaborationMode
    }
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
        id = try c.decode(String.self, forKey: .id)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        cliVersion = try c.decodeIfPresent(String.self, forKey: .cliVersion)
        if let s = try? c.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = s
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = String(d)
        } else {
            createdAt = nil
        }
    }
}

struct ThreadStartResult: Decodable {
    let thread: ThreadHandle
    let model: String?
}

struct ThreadArchiveParams: Encodable {
    let threadId: String
}

struct ThreadUnarchiveParams: Encodable {
    let threadId: String
}

struct ThreadSetNameParams: Encodable {
    let threadId: String
    let name: String
}

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

    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? c.decode([LossyAgentThreadSummary].self, forKey: .data).compactMap(\.value)) ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

private struct LossyAgentThreadSummary: Decodable {
    let value: AgentThreadSummary?

    init(from decoder: Decoder) throws {
        value = try? AgentThreadSummary(from: decoder)
    }
}

struct AgentThreadSummary: Decodable {
    let id: String
    let cwd: String?
    let name: String?
    let preview: String
    let path: String?
    let createdAt: Int64?
    let updatedAt: Int64
    let archived: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case cwd
        case name
        case title
        case threadName = "thread_name"
        case preview
        case path
        case createdAt
        case updatedAt
        case archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        name = try c.decodeFirstNonEmptyString(forKeys: [.name, .title, .threadName])
        preview = (try? c.decode(String.self, forKey: .preview)) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path)
        createdAt = Self.decodeInt64IfPresent(c, forKey: .createdAt)
        updatedAt = Self.decodeInt64IfPresent(c, forKey: .updatedAt) ?? createdAt ?? 0
        archived = Self.decodeBoolIfPresent(c, forKey: .archived)
    }

    private static func decodeInt64IfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int64? {
        if let value = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            if let int = Int64(value) { return int }
            if let double = Double(value) { return Int64(double) }
        }
        return nil
    }

    private static func decodeBoolIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Bool? {
        if let value = try? c.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }
}

private extension KeyedDecodingContainer where Key == AgentThreadSummary.CodingKeys {
    func decodeFirstNonEmptyString(forKeys keys: [Key]) throws -> String? {
        for key in keys {
            guard let value = try decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }
}

/// One element of `turn/start`'s `input` array. Codex's app-server
/// protocol accepts a small discriminated union of input items; we
/// support `text` for the prompt body and `localImage` for inline
/// image attachments materialized to temp files. Encoding is hand-
/// rolled because Swift's Codable derivation would emit both fields
/// for both cases.
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

struct CollaborationModePayload: Encodable {
    let mode: String
    let settings: CollaborationModeSettingsPayload
}

struct CollaborationModeSettingsPayload: Encodable {
    let model: String
    let developer_instructions: String?
    let reasoning_effort: String?
}

struct TurnStartParams: Encodable {
    let threadId: String
    let input: [TurnStartUserInput]
    let model: String?
    let effort: String?
    let serviceTier: String?
    let collaborationMode: CollaborationModePayload?
}

struct TurnStartResult: Decodable {
    let turn: TurnHandle
}

struct TurnInterruptParams: Encodable {
    let threadId: String
    let turnId: String
}

struct TurnHandle: Decodable {
    let id: String
}

struct TurnEnvelope: Decodable {
    let threadId: String
    let turn: TurnHandle
}

struct AgentMessageDelta: Decodable {
    let delta: String
    let itemId: String
    let threadId: String
    let turnId: String
}

struct ReasoningTextDelta: Decodable {
    let delta: String
    let itemId: String
    let threadId: String
    let turnId: String
}

struct ItemEnvelope: Decodable {
    let item: ItemPayload
    let threadId: String
    let turnId: String
}

struct ItemPayload: Decodable {
    let id: String
    let type: String
    let text: String?
}

struct ToolRequestUserInputResponse: Encodable {
    let answers: [String: ToolRequestUserInputAnswer]
}

struct ToolRequestUserInputAnswer: Encodable {
    let answers: [String]
}

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
        if let value = try? c.decode(Bool.self) { self = .bool(value); return }
        if let value = try? c.decode(Int.self) { self = .int(value); return }
        if let value = try? c.decode(Double.self) { self = .double(value); return }
        if let value = try? c.decode(String.self) { self = .string(value); return }
        if let value = try? c.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? c.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .int(let value): try c.encode(value)
        case .double(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
