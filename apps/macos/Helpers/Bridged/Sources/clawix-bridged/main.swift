import Foundation
import Combine
import ClawixCore
import ClawixEngine

@main
struct BridgedMain {
    static func main() {
        BridgedLog.write("starting schemaVersion=\(bridgeSchemaVersion)")
        let env = ProcessInfo.processInfo.environment
        if let bearer = env["CLAWIX_BRIDGED_BEARER"], !bearer.isEmpty {
            UserDefaults.standard.set(bearer, forKey: "ClawixBridge.Bearer.v1")
        }

        let port = env["CLAWIX_BRIDGED_PORT"].flatMap(UInt16.init) ?? 7778
        let defaults = env["CLAWIX_BRIDGED_DEFAULTS_SUITE"]
            .flatMap { UserDefaults(suiteName: $0) }
            ?? .standard
        let pairing = PairingService(defaults: defaults, port: port)
        let publishBonjour = env["CLAWIX_BRIDGED_DISABLE_BONJOUR"] != "1"
        let box = HostBox()

        Task { @MainActor in
            guard let binary = BackendBinary.resolve(environment: env) else {
                BridgedLog.write("backend binary not found")
                exit(78)
            }
            let host = DaemonEngineHost(binary: binary, pairing: pairing)
            let server = BridgeServer(
                host: host,
                port: port,
                pairing: pairing,
                publishBonjour: publishBonjour
            )
            server.start()
            box.host = host
            box.server = server
            BridgedLog.write("listening tcp/\(port) backend=\(binary.path.path)")
            Task { @MainActor in
                await host.bootstrap()
            }
        }

        RunLoop.current.run()
    }
}

final class HostBox: @unchecked Sendable {
    var host: AnyObject?
    var server: AnyObject?
}

enum BridgedLog {
    static func write(_ message: String) {
        let safe = redact(message)
        FileHandle.standardError.write(Data(("[clawix-bridged] \(safe)\n").utf8))
    }

    private static func redact(_ s: String) -> String {
        let patterns = [
            "(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{32,}(?![A-Za-z0-9_-])",
            NSHomeDirectory().replacingOccurrences(of: "/", with: "\\/")
        ]
        return patterns.reduce(s) { current, pattern in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return current }
            let range = NSRange(current.startIndex..., in: current)
            let replacement = pattern.hasPrefix("(?<!") ? "<redacted>" : "~"
            return re.stringByReplacingMatches(in: current, range: range, withTemplate: replacement)
        }
    }
}

struct BackendBinary {
    let path: URL

    static func resolve(environment: [String: String]) -> BackendBinary? {
        if let override = environment["CLAWIX_BRIDGED_BACKEND_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return BackendBinary(path: url)
            }
        }
        for candidate in candidatePaths() where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return BackendBinary(path: candidate)
        }
        return nil
    }

    private static func candidatePaths() -> [URL] {
        var out: [URL] = []
        if let manual = UserDefaults.standard.string(forKey: "ClawixBinaryPath"), !manual.isEmpty {
            out.append(URL(fileURLWithPath: manual))
        }
        out.append(URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"))
        let nvmRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvmRoot, includingPropertiesForKeys: nil) {
            for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                out.append(version.appendingPathComponent("bin/codex"))
            }
        }
        out.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        out.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        out.append(URL(fileURLWithPath: "/usr/bin/codex"))
        return out
    }
}

@MainActor
final class DaemonEngineHost: EngineHost {
    private let backend: BackendClient
    private let pairing: PairingService
    private let chatsSubject = CurrentValueSubject<[BridgeChatSnapshot], Never>([])
    private var chatByThread: [String: String] = [:]
    private var threadByChat: [String: String] = [:]
    private var rolloutPathByThread: [String: String] = [:]
    private var activeAssistantIdByThread: [String: String] = [:]
    private var activeTurnByThread: [String: String] = [:]

    init(binary: BackendBinary, pairing: PairingService) {
        self.backend = BackendClient(binary: binary)
        self.pairing = pairing
    }

    var bridgeChatsCurrent: [BridgeChatSnapshot] { chatsSubject.value }
    var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> {
        chatsSubject.eraseToAnyPublisher()
    }

    func bootstrap() async {
        do {
            try await backend.start()
            startEvents()
            _ = try await backend.send(
                method: "initialize",
                params: InitializeParams(
                    clientInfo: InitializeClientInfo(name: "Clawix Bridged", title: "Clawix", version: "1"),
                    capabilities: InitializeCapabilities(experimentalApi: true, optOutNotificationMethods: nil)
                )
            )
            try await backend.notify(method: "initialized", params: EmptyObject())
            await reloadThreads()
        } catch {
            BridgedLog.write("bootstrap failed \(error)")
        }
    }

    func handleHydrateHistory(chatId: UUID) {
        hydrate(chatId: chatId.uuidString)
    }

    func handleSendPrompt(chatId: UUID, text: String, attachments: [WireAttachment]) {
        let chatIdString = chatId.uuidString
        Task { @MainActor in
            do {
                let threadId = try await ensureThread(chatId: chatIdString, firstPrompt: text)
                let imagePaths = AttachmentSpooler.write(attachments: attachments, threadId: threadId)
                let preview = userMessagePreview(text: text, imageCount: imagePaths.count)
                appendMessage(chatId: chatIdString, message: WireMessage(
                    id: UUID().uuidString,
                    role: .user,
                    content: preview,
                    streamingFinished: true,
                    timestamp: Date()
                ))
                updateChat(chatId: chatIdString) { chat in
                    chat.hasActiveTurn = true
                    chat.lastTurnInterrupted = false
                    chat.lastMessageAt = Date()
                    chat.lastMessagePreview = String(preview.prefix(140))
                }
                var input: [TurnStartUserInput] = []
                if !text.isEmpty { input.append(.text(text)) }
                for path in imagePaths { input.append(.localImage(path: path)) }
                if input.isEmpty { input.append(.text(text)) }
                let result = try await backend.send(
                    method: "turn/start",
                    params: TurnStartParams(
                        threadId: threadId,
                        input: input,
                        model: nil,
                        effort: nil,
                        serviceTier: nil,
                        collaborationMode: nil
                    ),
                    expecting: TurnStartResult.self
                )
                activeTurnByThread[threadId] = result.turn.id
            } catch {
                appendError(chatId: chatIdString, message: "\(error)")
            }
        }
    }

    private func userMessagePreview(text: String, imageCount: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard imageCount > 0 else { return text }
        let label = imageCount == 1 ? "[image]" : "[\(imageCount) images]"
        return trimmed.isEmpty ? label : "\(label) \(text)"
    }

    func handleNewChat(chatId: UUID, text: String, attachments: [WireAttachment]) {
        // The iPhone composer treats the first prompt of a chat as a
        // `newChat` frame so the daemon can mint the thread with the
        // chat's pre-allocated UUID. The actual run path is identical
        // to a regular send: ensureThread creates the thread on demand.
        handleSendPrompt(chatId: chatId, text: text, attachments: attachments)
    }

    func handleArchiveChat(chatId: UUID, archived: Bool) {
        let chatIdString = chatId.uuidString
        guard let threadId = threadByChat[chatIdString] else { return }
        Task { @MainActor in
            do {
                if archived {
                    _ = try await backend.send(
                        method: "thread/archive",
                        params: ThreadArchiveParams(threadId: threadId),
                        expecting: EmptyResponse.self
                    )
                } else {
                    _ = try await backend.send(
                        method: "thread/unarchive",
                        params: ThreadUnarchiveParams(threadId: threadId),
                        expecting: EmptyResponse.self
                    )
                }
                updateChat(chatId: chatIdString) {
                    $0.isArchived = archived
                    if archived { $0.isPinned = false }
                }
            } catch {
                appendError(chatId: chatIdString, message: "\(error)")
            }
        }
    }

    func handlePairingStart() -> (qrJson: String, bearer: String)? {
        return (pairing.qrPayload(), pairing.bearer)
    }

    private func reloadThreads() async {
        do {
            let response = try await backend.send(
                method: "thread/list",
                params: ThreadListParams(
                    archived: false,
                    cursor: nil,
                    cwd: nil,
                    limit: 160,
                    modelProviders: nil,
                    searchTerm: nil,
                    sortDirection: "desc",
                    sortKey: "updated_at",
                    sourceKinds: nil,
                    useStateDbOnly: true
                ),
                expecting: ThreadListResponse.self
            )
            let snapshots = response.data.map(snapshot(from:))
            chatsSubject.send(snapshots)
        } catch {
            BridgedLog.write("thread/list failed \(error)")
        }
    }

    private func snapshot(from thread: AgentThreadSummary) -> BridgeChatSnapshot {
        let chatId = chatByThread[thread.id] ?? UUID().uuidString
        chatByThread[thread.id] = chatId
        threadByChat[chatId] = thread.id
        if let path = thread.path { rolloutPathByThread[thread.id] = path }
        return BridgeChatSnapshot(
            chat: WireChat(
                id: chatId,
                title: title(for: thread),
                createdAt: thread.updatedDate,
                isArchived: thread.archived ?? false,
                hasActiveTurn: activeTurnByThread[thread.id] != nil,
                lastMessageAt: thread.updatedDate,
                lastMessagePreview: thread.preview,
                cwd: thread.cwd
            ),
            messages: existingMessages(chatId: chatId)
        )
    }

    private func title(for thread: AgentThreadSummary) -> String {
        if let name = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let preview = thread.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "Conversation" : String(preview.prefix(60))
    }

    private func ensureThread(chatId: String, firstPrompt: String) async throws -> String {
        if let threadId = threadByChat[chatId] {
            return threadId
        }
        let result = try await backend.send(
            method: "thread/start",
            params: ThreadStartParams(
                cwd: FileManager.default.homeDirectoryForCurrentUser.path,
                model: nil,
                approvalPolicy: nil,
                sandbox: nil,
                personality: nil,
                serviceTier: nil,
                collaborationMode: nil
            ),
            expecting: ThreadStartResult.self
        )
        let threadId = result.thread.id
        chatByThread[threadId] = chatId
        threadByChat[chatId] = threadId
        ensureSnapshot(chatId: chatId, firstPrompt: firstPrompt, cwd: result.thread.cwd)
        updateSnapshot(chatId: chatId) { snap in
            let trimmed = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            snap.chat.title = trimmed.isEmpty ? "Conversation" : String(trimmed.prefix(60))
            snap.chat.cwd = result.thread.cwd
        }
        return threadId
    }

    private func ensureSnapshot(chatId: String, firstPrompt: String, cwd: String?) {
        guard !bridgeChatsCurrent.contains(where: { $0.id == chatId }) else { return }
        let trimmed = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var snapshots = bridgeChatsCurrent
        snapshots.insert(
            BridgeChatSnapshot(
                chat: WireChat(
                    id: chatId,
                    title: trimmed.isEmpty ? "Conversation" : String(trimmed.prefix(60)),
                    createdAt: Date(),
                    isArchived: false,
                    hasActiveTurn: false,
                    lastMessageAt: Date(),
                    lastMessagePreview: String(trimmed.prefix(140)),
                    cwd: cwd
                ),
                messages: []
            ),
            at: 0
        )
        chatsSubject.send(snapshots)
    }

    private func hydrate(chatId: String) {
        guard let threadId = threadByChat[chatId],
              let path = rolloutPathByThread[threadId]
        else { return }
        let result = RolloutHistory.read(path: URL(fileURLWithPath: path))
        guard !result.messages.isEmpty || result.lastTurnInterrupted else { return }
        updateSnapshot(chatId: chatId) { snap in
            snap.messages = result.messages
            snap.chat.lastTurnInterrupted = result.lastTurnInterrupted
            if let last = result.messages.last {
                snap.chat.lastMessageAt = last.timestamp
                snap.chat.lastMessagePreview = String(last.content.prefix(140))
            }
        }
    }

    private func startEvents() {
        let stream = backend.events
        Task { @MainActor in
            for await event in stream {
                handle(event)
            }
        }
    }

    private func handle(_ event: BackendEvent) {
        switch event {
        case let .request(id, method, _):
            if method == "item/tool/requestUserInput" {
                try? backend.resolve(id: id, result: ToolRequestUserInputResponse(answers: [:]))
            }
        case let .notification(method, params):
            handleNotification(method: method, params: params)
        }
    }

    private func handleNotification(method: String, params: JSONValue?) {
        switch method {
        case "turn/started":
            guard let payload = try? params?.decode(TurnEnvelope.self),
                  let chatId = chatByThread[payload.threadId]
            else { return }
            activeTurnByThread[payload.threadId] = payload.turn.id
            ensureAssistant(chatId: chatId, threadId: payload.threadId)
            updateChat(chatId: chatId) { $0.hasActiveTurn = true }
        case "item/agentMessage/delta":
            guard let payload = try? params?.decode(AgentMessageDelta.self),
                  let chatId = chatByThread[payload.threadId]
            else { return }
            let assistantId = ensureAssistant(chatId: chatId, threadId: payload.threadId)
            updateMessage(chatId: chatId, messageId: assistantId) { msg in
                msg.content += payload.delta
                msg.streamingFinished = false
            }
        case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
            guard let payload = try? params?.decode(ReasoningTextDelta.self),
                  let chatId = chatByThread[payload.threadId]
            else { return }
            let assistantId = ensureAssistant(chatId: chatId, threadId: payload.threadId)
            updateMessage(chatId: chatId, messageId: assistantId) { msg in
                msg.reasoningText += payload.delta
                msg.streamingFinished = false
            }
        case "item/completed":
            guard let payload = try? params?.decode(ItemEnvelope.self),
                  payload.item.type == "agentMessage",
                  let chatId = chatByThread[payload.threadId],
                  let assistantId = activeAssistantIdByThread[payload.threadId]
            else { return }
            updateMessage(chatId: chatId, messageId: assistantId) { msg in
                if let text = payload.item.text, !text.isEmpty {
                    msg.content = text
                }
                msg.streamingFinished = true
            }
        case "turn/completed":
            guard let payload = try? params?.decode(TurnEnvelope.self),
                  let chatId = chatByThread[payload.threadId]
            else { return }
            activeTurnByThread[payload.threadId] = nil
            activeAssistantIdByThread[payload.threadId] = nil
            updateChat(chatId: chatId) {
                $0.hasActiveTurn = false
                $0.lastTurnInterrupted = false
            }
        default:
            break
        }
    }

    @discardableResult
    private func ensureAssistant(chatId: String, threadId: String) -> String {
        if let id = activeAssistantIdByThread[threadId] { return id }
        let id = UUID().uuidString
        activeAssistantIdByThread[threadId] = id
        appendMessage(chatId: chatId, message: WireMessage(
            id: id,
            role: .assistant,
            content: "",
            streamingFinished: false,
            timestamp: Date()
        ))
        return id
    }

    private func appendError(chatId: String, message: String) {
        appendMessage(chatId: chatId, message: WireMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: message,
            streamingFinished: true,
            isError: true,
            timestamp: Date()
        ))
        updateChat(chatId: chatId) { $0.hasActiveTurn = false }
    }

    private func existingMessages(chatId: String) -> [WireMessage] {
        bridgeChatsCurrent.first(where: { $0.id == chatId })?.messages ?? []
    }

    private func appendMessage(chatId: String, message: WireMessage) {
        updateSnapshot(chatId: chatId) { snap in
            snap.messages.append(message)
            snap.chat.lastMessageAt = message.timestamp
            snap.chat.lastMessagePreview = String(message.content.prefix(140))
        }
    }

    private func updateMessage(chatId: String, messageId: String, mutate: (inout WireMessage) -> Void) {
        updateSnapshot(chatId: chatId) { snap in
            guard let idx = snap.messages.firstIndex(where: { $0.id == messageId }) else { return }
            mutate(&snap.messages[idx])
            let msg = snap.messages[idx]
            snap.chat.lastMessageAt = msg.timestamp
            snap.chat.lastMessagePreview = String(msg.content.prefix(140))
        }
    }

    private func updateChat(chatId: String, mutate: (inout WireChat) -> Void) {
        updateSnapshot(chatId: chatId) { mutate(&$0.chat) }
    }

    private func updateSnapshot(chatId: String, mutate: (inout MutableSnapshot) -> Void) {
        var snapshots = bridgeChatsCurrent
        guard let index = snapshots.firstIndex(where: { $0.id == chatId }) else { return }
        var mutable = MutableSnapshot(snapshots[index])
        mutate(&mutable)
        snapshots[index] = mutable.snapshot
        chatsSubject.send(snapshots)
    }
}

private struct MutableSnapshot {
    var chat: WireChat
    var messages: [WireMessage]

    init(_ snapshot: BridgeChatSnapshot) {
        self.chat = snapshot.chat
        self.messages = snapshot.messages
    }

    var snapshot: BridgeChatSnapshot {
        BridgeChatSnapshot(chat: chat, messages: messages)
    }
}

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

    func send<P: Encodable>(method: String, params: P) async throws -> JSONValue? {
        guard process != nil else { throw BackendError.notRunning }
        let id = nextId
        nextId += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(BackendRequest(id: id, method: method, params: params))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    func send<P: Encodable, R: Decodable>(method: String, params: P, expecting: R.Type) async throws -> R {
        guard let raw = try await send(method: method, params: params) else {
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
                BridgedLog.write("backend stderr \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
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

    var description: String {
        switch self {
        case .notRunning: return "backend not running"
        case .invalidResponse: return "invalid backend response"
        case .rpc(let message): return message
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
    let experimentalApi: Bool?
    let optOutNotificationMethods: [String]?
}

struct InitializeParams: Encodable {
    let clientInfo: InitializeClientInfo
    let capabilities: InitializeCapabilities?
}

struct EmptyObject: Encodable {}
struct EmptyResponse: Decodable {}

struct ThreadStartParams: Encodable {
    let cwd: String?
    let model: String?
    let approvalPolicy: String?
    let sandbox: String?
    let personality: String?
    let serviceTier: String?
    let collaborationMode: CollaborationModePayload?
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

    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
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

enum RolloutHistory {
    static func read(path: URL, now: Date = Date()) -> (messages: [WireMessage], lastTurnInterrupted: Bool) {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return ([], false)
        }
        var messages: [WireMessage] = []
        var lastEventAt: Date?
        var sawAgentWork = false
        var sawClose = true
        let iso = ISO8601DateFormatter()
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let ts = obj["timestamp"] as? String {
                lastEventAt = iso.date(from: ts)
            }
            guard obj["type"] as? String == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  let type = payload["type"] as? String
            else { continue }
            switch type {
            case "user_message":
                if let message = payload["message"] as? String {
                    messages.append(WireMessage(
                        id: UUID().uuidString,
                        role: .user,
                        content: message,
                        streamingFinished: true,
                        timestamp: lastEventAt ?? now
                    ))
                    sawClose = true
                }
            case "agent_message":
                let message = (payload["message"] as? String) ?? (payload["text"] as? String) ?? ""
                messages.append(WireMessage(
                    id: UUID().uuidString,
                    role: .assistant,
                    content: message,
                    streamingFinished: true,
                    timestamp: lastEventAt ?? now
                ))
                sawAgentWork = true
                sawClose = false
            case "final_answer", "turn_completed":
                sawClose = true
            default:
                break
            }
        }
        let interrupted = sawAgentWork
            && !sawClose
            && lastEventAt.map { now.timeIntervalSince($0) > 30 } == true
        return (messages, interrupted)
    }
}

// MARK: - Inline image attachments

/// Materializes inline image attachments coming off the bridge as on-disk
/// files Codex can pick up via 'localImage' user input items. Files live
/// in a per-thread subdir of `NSTemporaryDirectory()/clawix-attachments`
/// so they are easy to spot, easy to delete, and grouped together if
/// debugging is needed. We never delete them eagerly: the thread may be
/// resumed minutes later and the rollout still references the path. The
/// system reaps `NSTemporaryDirectory()` on its own schedule, which is
/// good enough for a chat companion.
enum AttachmentSpooler {
    static func write(attachments: [WireAttachment], threadId: String) -> [String] {
        guard !attachments.isEmpty else { return [] }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawix-attachments", isDirectory: true)
            .appendingPathComponent(threadId, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            BridgedLog.write("attachment dir failed \(error)")
            return []
        }
        var paths: [String] = []
        for attachment in attachments {
            guard let data = Data(base64Encoded: attachment.dataBase64) else {
                BridgedLog.write("attachment decode failed id=\(attachment.id)")
                continue
            }
            let ext = preferredExtension(filename: attachment.filename, mimeType: attachment.mimeType)
            let url = root.appendingPathComponent("\(attachment.id).\(ext)")
            do {
                try data.write(to: url, options: .atomic)
                paths.append(url.path)
            } catch {
                BridgedLog.write("attachment write failed \(error)")
            }
        }
        return paths
    }

    private static func preferredExtension(filename: String?, mimeType: String) -> String {
        if let filename, let dotRange = filename.range(of: ".", options: .backwards) {
            let candidate = String(filename[dotRange.upperBound...]).lowercased()
            if !candidate.isEmpty, candidate.count <= 5 { return candidate }
        }
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/webp": return "webp"
        case "image/gif":  return "gif"
        default: return "jpg"
        }
    }
}
