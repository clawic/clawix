import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Combine)
import Combine
#else
import OpenCombine
import OpenCombineFoundation
#endif
import ClawixCore
import ClawixEngine

enum AgentRuntimeSelection: String {
    case codex
    case opencode

    static let runtimeKey = "ClawixAgentRuntime"
    static let openCodeModelKey = "ClawixOpenCodeModel"
    static let defaultOpenCodeModel = "deepseekv4/deepseek-v4-pro"

    static func resolve(environment: [String: String], defaults: UserDefaults) -> AgentRuntimeSelection {
        if let raw = environment["CLAWIX_AGENT_RUNTIME"]?.lowercased(),
           let runtime = AgentRuntimeSelection(rawValue: raw) {
            return runtime
        }
        if let raw = defaults.string(forKey: runtimeKey)?.lowercased(),
           let runtime = AgentRuntimeSelection(rawValue: raw) {
            return runtime
        }
        return .codex
    }
}

@MainActor
final class OpenCodeDaemonEngineHost: EngineHost {
    private let pairing: PairingService
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let chatsSubject = CurrentValueSubject<[BridgeChatSnapshot], Never>([])
    private let stateSubject = CurrentValueSubject<BridgeRuntimeState, Never>(.booting)
    private let rateLimitsSubject = CurrentValueSubject<WireRateLimitsPayload, Never>(.empty)
    private var client: OpenCodeClient?
    private var chatBySession: [String: String] = [:]
    private var sessionByChat: [String: String] = [:]
    private var activeAssistantIdBySession: [String: String] = [:]
    private var activePartTextById: [String: String] = [:]
    private var eventTask: Task<Void, Never>?
    private(set) var lastChatsPublishedAt: Date?

    init(pairing: PairingService, defaults: UserDefaults, environment: [String: String]) {
        self.pairing = pairing
        self.defaults = defaults
        self.environment = environment
    }

    var bridgeChatsCurrent: [BridgeChatSnapshot] { chatsSubject.value }
    var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> {
        chatsSubject.eraseToAnyPublisher()
    }

    var bridgeStateCurrent: BridgeRuntimeState { stateSubject.value }
    var bridgeStatePublisher: AnyPublisher<BridgeRuntimeState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var bridgeRateLimitsCurrent: WireRateLimitsPayload { rateLimitsSubject.value }
    var bridgeRateLimitsPublisher: AnyPublisher<WireRateLimitsPayload, Never> {
        rateLimitsSubject.eraseToAnyPublisher()
    }

    func bootstrap() async {
        BridgedLog.write("opencode bootstrap-start")
        stateSubject.send(.syncing)
        do {
            let client = try await OpenCodeClient.start(defaults: defaults, environment: environment)
            self.client = client
            startEvents(client: client)
            await reloadSessions()
            publishProviderStatus()
            stateSubject.send(.ready)
        } catch {
            let message = OpenCodeClient.shortReason(error)
            BridgedLog.write("opencode bootstrap failed \(message)")
            stateSubject.send(.error(message))
        }
    }

    func handleHydrateHistory(chatId: UUID) {
        let chatIdString = chatId.uuidString
        guard let sessionID = sessionByChat[chatIdString], let client else { return }
        BridgedLog.write("opencode hydrate chat=\(chatIdString) session=\(sessionID)")
        Task { @MainActor in
            do {
                let payload = try await client.messages(sessionID: sessionID)
                let messages = self.messages(from: payload, fallbackSessionID: sessionID)
                self.updateSnapshot(chatId: chatIdString) { snap in
                    snap.messages = messages
                    if let last = messages.last {
                        snap.chat.lastMessageAt = last.timestamp
                        snap.chat.lastMessagePreview = String(last.content.prefix(140))
                    }
                }
            } catch {
                self.appendError(chatId: chatIdString, message: OpenCodeClient.shortReason(error))
            }
        }
    }

    func handleSendPrompt(chatId: UUID, text: String, attachments: [WireAttachment]) {
        let chatIdString = chatId.uuidString
        BridgedLog.write("opencode send chat=\(chatIdString) textChars=\(text.count) attachments=\(attachments.count)")
        Task { @MainActor in
            do {
                guard let client else { throw OpenCodeError.notRunning }
                let sessionID = try await self.ensureSession(chatId: chatIdString, firstPrompt: text)
                let userMessageId = UUID().uuidString
                let promptText = self.promptForOpenCode(text: text, attachments: attachments)
                let preview = self.userPreview(text: text, attachments: attachments)
                self.appendMessage(chatId: chatIdString, message: WireMessage(
                    id: userMessageId,
                    role: .user,
                    content: preview,
                    streamingFinished: true,
                    timestamp: Date(),
                    attachments: attachments
                ))
                self.updateChat(chatId: chatIdString) {
                    $0.hasActiveTurn = true
                    $0.lastTurnInterrupted = false
                    $0.lastMessageAt = Date()
                    $0.lastMessagePreview = String(preview.prefix(140))
                }
                let model = self.selectedModel()
                let response = try await client.prompt(
                    sessionID: sessionID,
                    providerID: model.providerID,
                    modelID: model.modelID,
                    text: promptText
                )
                self.applyPromptResponse(response, sessionID: sessionID, chatId: chatIdString)
            } catch {
                self.appendError(chatId: chatIdString, message: OpenCodeClient.shortReason(error))
            }
        }
    }

    func handleNewChat(chatId: UUID, text: String, attachments: [WireAttachment]) {
        handleSendPrompt(chatId: chatId, text: text, attachments: attachments)
    }

    func handleInterruptTurn(chatId: UUID) {
        let chatIdString = chatId.uuidString
        guard let sessionID = sessionByChat[chatIdString], let client else { return }
        if let assistantId = activeAssistantIdBySession[sessionID] {
            let messages = existingMessages(chatId: chatIdString)
            if let msg = messages.first(where: { $0.id == assistantId }),
               msg.content.isEmpty && msg.reasoningText.isEmpty {
                updateSnapshot(chatId: chatIdString) { snap in
                    snap.messages.removeAll { $0.id == assistantId }
                }
            } else {
                updateMessage(chatId: chatIdString, messageId: assistantId) {
                    $0.streamingFinished = true
                    $0.workSummary?.endedAt = Date()
                }
            }
            activeAssistantIdBySession[sessionID] = nil
        }
        updateChat(chatId: chatIdString) {
            $0.hasActiveTurn = false
            $0.lastTurnInterrupted = true
        }
        Task { @MainActor in
            do {
                _ = try await client.abort(sessionID: sessionID)
            } catch {
                BridgedLog.write("opencode abort failed \(OpenCodeClient.shortReason(error))")
            }
        }
    }

    func handleArchiveChat(chatId: UUID, archived: Bool) {
        let chatIdString = chatId.uuidString
        guard let sessionID = sessionByChat[chatIdString], let client else { return }
        Task { @MainActor in
            do {
                let info = try await client.patchSession(sessionID: sessionID, archived: archived, title: nil)
                self.applySession(info)
            } catch {
                self.updateChat(chatId: chatIdString) { $0.isArchived = archived }
            }
        }
    }

    func handleRenameChat(chatId: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let chatIdString = chatId.uuidString
        guard let sessionID = sessionByChat[chatIdString], let client else { return }
        updateChat(chatId: chatIdString) { $0.title = trimmed }
        Task { @MainActor in
            do {
                let info = try await client.patchSession(sessionID: sessionID, archived: nil, title: trimmed)
                self.applySession(info)
            } catch {
                self.appendError(chatId: chatIdString, message: OpenCodeClient.shortReason(error))
            }
        }
    }

    func handlePairingStart() -> (qrJson: String, bearer: String)? {
        (pairing.qrPayload(), pairing.bearer)
    }

    func currentProjects() -> [WireProject] {
        var seen: Set<String> = []
        return bridgeChatsCurrent.compactMap { snapshot in
            guard let cwd = snapshot.chat.cwd, !cwd.isEmpty, !seen.contains(cwd) else { return nil }
            seen.insert(cwd)
            return WireProject(
                id: cwd,
                title: URL(fileURLWithPath: cwd).lastPathComponent,
                cwd: cwd,
                lastUsedAt: snapshot.chat.lastMessageAt
            )
        }
    }

    private func reloadSessions() async {
        guard let client else { return }
        do {
            let sessions = try await client.sessions()
            let snapshots = sessions.map(snapshot(from:))
            chatsSubject.send(snapshots)
            lastChatsPublishedAt = Date()
            BridgedLog.write("opencode session-list ok count=\(sessions.count)")
        } catch {
            stateSubject.send(.error("Couldn't load OpenCode chats: \(OpenCodeClient.shortReason(error))"))
        }
    }

    private func snapshot(from session: [String: Any]) -> BridgeChatSnapshot {
        let sessionID = string(session["id"]) ?? UUID().uuidString
        let chatId = chatBySession[sessionID] ?? UUID().uuidString
        chatBySession[sessionID] = chatId
        sessionByChat[chatId] = sessionID
        let time = dict(session["time"])
        let created = date(time?["created"]) ?? Date()
        let updated = date(time?["updated"]) ?? created
        let archived = time?["archived"] != nil
        let title = nonEmpty(string(session["title"])) ?? nonEmpty(string(session["slug"])) ?? "OpenCode chat"
        let cwd = string(session["directory"])
        return BridgeChatSnapshot(
            chat: WireChat(
                id: chatId,
                title: title,
                createdAt: created,
                isArchived: archived,
                hasActiveTurn: activeAssistantIdBySession[sessionID] != nil,
                lastMessageAt: updated,
                lastMessagePreview: nil,
                cwd: cwd,
                threadId: sessionID
            ),
            messages: existingMessages(chatId: chatId)
        )
    }

    private func ensureSession(chatId: String, firstPrompt: String) async throws -> String {
        if let existing = sessionByChat[chatId] { return existing }
        guard let client else { throw OpenCodeError.notRunning }
        let title = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = try await client.createSession(
            title: title.isEmpty ? "OpenCode chat" : String(title.prefix(60)),
            permission: permissionRules()
        )
        let sessionID = string(info["id"]) ?? UUID().uuidString
        chatBySession[sessionID] = chatId
        sessionByChat[chatId] = sessionID
        let cwd = string(info["directory"]) ?? FileManager.default.homeDirectoryForCurrentUser.path
        ensureSnapshot(chatId: chatId, firstPrompt: firstPrompt, cwd: cwd, sessionID: sessionID)
        return sessionID
    }

    private func ensureSnapshot(chatId: String, firstPrompt: String, cwd: String?, sessionID: String) {
        guard !bridgeChatsCurrent.contains(where: { $0.id == chatId }) else { return }
        let trimmed = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var snapshots = bridgeChatsCurrent
        snapshots.insert(BridgeChatSnapshot(
            chat: WireChat(
                id: chatId,
                title: trimmed.isEmpty ? "OpenCode chat" : String(trimmed.prefix(60)),
                createdAt: Date(),
                isArchived: false,
                hasActiveTurn: false,
                lastMessageAt: Date(),
                lastMessagePreview: String(trimmed.prefix(140)),
                cwd: cwd,
                threadId: sessionID
            ),
            messages: []
        ), at: 0)
        chatsSubject.send(snapshots)
    }

    private func startEvents(client: OpenCodeClient) {
        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self] in
            do {
                for try await event in try await client.events() {
                    self?.handle(event)
                }
            } catch {
                BridgedLog.write("opencode event stream ended \(OpenCodeClient.shortReason(error))")
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        let type = string(event["type"]) ?? string(dict(event["payload"])?["type"]) ?? ""
        let properties = dict(event["properties"]) ?? dict(dict(event["payload"])?["properties"]) ?? [:]
        switch type {
        case "session.created", "session.updated":
            if let info = dict(properties["info"]) {
                applySession(info)
            }
        case "message.updated":
            guard let sessionID = string(properties["sessionID"]),
                  let info = dict(properties["info"]),
                  let chatId = chatBySession[sessionID]
            else { return }
            applyMessageInfo(info, sessionID: sessionID, chatId: chatId)
        case "message.part.delta":
            guard let sessionID = string(properties["sessionID"]),
                  let chatId = chatBySession[sessionID],
                  let messageID = string(properties["messageID"]),
                  let partID = string(properties["partID"]),
                  let delta = string(properties["delta"])
            else { return }
            let assistantId = ensureAssistant(chatId: chatId, sessionID: sessionID, messageID: messageID)
            let field = string(properties["field"]) ?? "text"
            updateMessage(chatId: chatId, messageId: assistantId) {
                if field == "text" {
                    $0.content += delta
                } else {
                    $0.reasoningText += delta
                }
                $0.streamingFinished = false
            }
            activePartTextById[partID, default: ""] += delta
        case "message.part.updated":
            guard let sessionID = string(properties["sessionID"]),
                  let part = dict(properties["part"]),
                  let chatId = chatBySession[sessionID]
            else { return }
            applyPart(part, sessionID: sessionID, chatId: chatId)
        case "permission.asked":
            guard let sessionID = string(properties["sessionID"]),
                  let requestID = string(properties["id"]),
                  let chatId = chatBySession[sessionID]
            else { return }
            let permission = string(properties["permission"]) ?? "permission"
            appendError(chatId: chatId, message: "OpenCode requested \(permission). Approval UI is available through OpenCode; Clawix rejected this request to avoid silent escalation.")
            Task { [client = self.client] in
                _ = try? await client?.replyPermission(requestID: requestID, reply: "reject")
            }
        default:
            break
        }
    }

    private func applySession(_ info: [String: Any]) {
        let snapshot = snapshot(from: info)
        var snapshots = bridgeChatsCurrent
        if let idx = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            var merged = MutableSnapshot(snapshot)
            merged.messages = snapshots[idx].messages
            snapshots[idx] = merged.snapshot
        } else {
            snapshots.insert(snapshot, at: 0)
        }
        chatsSubject.send(snapshots)
    }

    private func applyPromptResponse(_ response: Any, sessionID: String, chatId: String) {
        if let entries = response as? [[String: Any]], !entries.isEmpty {
            let messages = messages(from: entries, fallbackSessionID: sessionID)
            if !messages.isEmpty {
                updateSnapshot(chatId: chatId) { snap in
                    snap.messages = merge(existing: snap.messages, incoming: messages)
                    snap.chat.hasActiveTurn = false
                    if let last = snap.messages.last {
                        snap.chat.lastMessageAt = last.timestamp
                        snap.chat.lastMessagePreview = String(last.content.prefix(140))
                    }
                }
            }
        }
    }

    private func applyMessageInfo(_ info: [String: Any], sessionID: String, chatId: String) {
        guard string(info["role"]) == "assistant" else { return }
        let messageID = string(info["id"]) ?? UUID().uuidString
        let assistantId = ensureAssistant(chatId: chatId, sessionID: sessionID, messageID: messageID)
        if dict(info["time"])?["completed"] != nil || info["finish"] != nil || info["error"] != nil {
            updateMessage(chatId: chatId, messageId: assistantId) {
                $0.streamingFinished = true
                $0.workSummary?.endedAt = Date()
                if let error = info["error"] {
                    $0.isError = true
                    $0.content = OpenCodeClient.shortReason(OpenCodeError.api("\(error)"))
                }
            }
            activeAssistantIdBySession[sessionID] = nil
            updateChat(chatId: chatId) {
                $0.hasActiveTurn = false
                $0.lastTurnInterrupted = false
            }
        }
    }

    private func applyPart(_ part: [String: Any], sessionID: String, chatId: String) {
        let messageID = string(part["messageID"]) ?? UUID().uuidString
        let assistantId = ensureAssistant(chatId: chatId, sessionID: sessionID, messageID: messageID)
        switch string(part["type"]) {
        case "text":
            if let text = string(part["text"]) {
                updateMessage(chatId: chatId, messageId: assistantId) {
                    $0.content = text
                    $0.streamingFinished = false
                }
            }
        case "reasoning":
            if let text = string(part["text"]) {
                updateMessage(chatId: chatId, messageId: assistantId) {
                    $0.reasoningText = text
                    $0.streamingFinished = false
                }
            }
        case "tool":
            updateTool(part, chatId: chatId, messageId: assistantId)
        case "patch":
            updatePatch(part, chatId: chatId, messageId: assistantId)
        default:
            break
        }
    }

    @discardableResult
    private func ensureAssistant(chatId: String, sessionID: String, messageID: String? = nil) -> String {
        if let id = activeAssistantIdBySession[sessionID] { return id }
        let id = messageID ?? UUID().uuidString
        activeAssistantIdBySession[sessionID] = id
        appendMessage(chatId: chatId, message: WireMessage(
            id: id,
            role: .assistant,
            content: "",
            streamingFinished: false,
            timestamp: Date(),
            workSummary: WireWorkSummary(startedAt: Date(), endedAt: nil, items: [])
        ))
        updateChat(chatId: chatId) { $0.hasActiveTurn = true }
        return id
    }

    private func updateTool(_ part: [String: Any], chatId: String, messageId: String) {
        let state = dict(part["state"])
        let statusRaw = string(state?["status"]) ?? "running"
        let status: WireWorkItemStatus = statusRaw == "completed" ? .completed : (statusRaw == "error" ? .failed : .inProgress)
        let tool = string(part["tool"]) ?? "tool"
        let title = string(state?["title"]) ?? tool
        let item = WireWorkItem(
            id: string(part["id"]) ?? UUID().uuidString,
            kind: tool == "bash" ? "command" : "dynamicTool",
            status: status,
            commandText: tool == "bash" ? title : nil,
            dynamicToolName: tool == "bash" ? nil : title
        )
        upsertWorkItem(item, chatId: chatId, messageId: messageId)
    }

    private func updatePatch(_ part: [String: Any], chatId: String, messageId: String) {
        let item = WireWorkItem(
            id: string(part["id"]) ?? UUID().uuidString,
            kind: "fileChange",
            status: .completed,
            paths: array(part["files"])?.compactMap { string($0) }
        )
        upsertWorkItem(item, chatId: chatId, messageId: messageId)
    }

    private func upsertWorkItem(_ item: WireWorkItem, chatId: String, messageId: String) {
        updateMessage(chatId: chatId, messageId: messageId) { message in
            var summary = message.workSummary ?? WireWorkSummary(startedAt: Date(), endedAt: nil, items: [])
            if let idx = summary.items.firstIndex(where: { $0.id == item.id }) {
                summary.items[idx] = item
            } else {
                summary.items.append(item)
            }
            message.workSummary = summary
            message.timeline = [.tools(id: "opencode-tools-\(messageId)", items: summary.items)]
        }
    }

    private func messages(from payload: Any, fallbackSessionID: String) -> [WireMessage] {
        guard let entries = payload as? [[String: Any]] else { return [] }
        return entries.compactMap { entry -> WireMessage? in
            let info = dict(entry["info"]) ?? entry
            let role = string(info["role"])
            let parts = array(entry["parts"])?.compactMap { dict($0) } ?? []
            let timestamp = date(dict(info["time"])?["created"]) ?? Date()
            if role == "user" {
                let text = parts.compactMap { part -> String? in
                    guard string(part["type"]) == "text" else { return nil }
                    return string(part["text"])
                }.joined(separator: "\n\n")
                return WireMessage(
                    id: string(info["id"]) ?? UUID().uuidString,
                    role: .user,
                    content: text,
                    streamingFinished: true,
                    timestamp: timestamp
                )
            }
            if role == "assistant" {
                var text = ""
                var reasoning = ""
                var items: [WireWorkItem] = []
                for part in parts {
                    switch string(part["type"]) {
                    case "text":
                        text += string(part["text"]) ?? ""
                    case "reasoning":
                        reasoning += string(part["text"]) ?? ""
                    case "tool":
                        let state = dict(part["state"])
                        let raw = string(state?["status"]) ?? "completed"
                        let status: WireWorkItemStatus = raw == "error" ? .failed : (raw == "completed" ? .completed : .inProgress)
                        let tool = string(part["tool"]) ?? "tool"
                        items.append(WireWorkItem(
                            id: string(part["id"]) ?? UUID().uuidString,
                            kind: tool == "bash" ? "command" : "dynamicTool",
                            status: status,
                            commandText: tool == "bash" ? (string(state?["title"]) ?? tool) : nil,
                            dynamicToolName: tool == "bash" ? nil : tool
                        ))
                    case "patch":
                        items.append(WireWorkItem(
                            id: string(part["id"]) ?? UUID().uuidString,
                            kind: "fileChange",
                            status: .completed,
                            paths: array(part["files"])?.compactMap { string($0) }
                        ))
                    default:
                        break
                    }
                }
                let completed = dict(info["time"])?["completed"] != nil
                return WireMessage(
                    id: string(info["id"]) ?? UUID().uuidString,
                    role: .assistant,
                    content: text,
                    reasoningText: reasoning,
                    streamingFinished: completed,
                    isError: info["error"] != nil,
                    timestamp: timestamp,
                    timeline: items.isEmpty ? [] : [.tools(id: "opencode-tools-\(fallbackSessionID)", items: items)],
                    workSummary: items.isEmpty ? nil : WireWorkSummary(startedAt: timestamp, endedAt: completed ? Date() : nil, items: items)
                )
            }
            return nil
        }
    }

    private func selectedModel() -> (providerID: String, modelID: String) {
        let raw = environment["CLAWIX_OPENCODE_MODEL"]
            ?? defaults.string(forKey: AgentRuntimeSelection.openCodeModelKey)
            ?? AgentRuntimeSelection.defaultOpenCodeModel
        let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 { return (parts[0], parts[1]) }
        return ("deepseekv4", "deepseek-v4-pro")
    }

    private func permissionRules() -> [[String: String]]? {
        let raw = defaults.string(forKey: "ClawixPermissionMode") ?? environment["CLAWIX_PERMISSION_MODE"] ?? "defaultPermissions"
        switch raw {
        case "fullAccess":
            return [["permission": "*", "pattern": "*", "action": "allow"]]
        case "autoReview":
            return [
                ["permission": "read", "pattern": "*", "action": "allow"],
                ["permission": "list", "pattern": "*", "action": "allow"],
                ["permission": "glob", "pattern": "*", "action": "allow"],
                ["permission": "grep", "pattern": "*", "action": "allow"],
                ["permission": "edit", "pattern": "*", "action": "ask"],
                ["permission": "bash", "pattern": "*", "action": "ask"]
            ]
        default:
            return nil
        }
    }

    private func publishProviderStatus() {
        let model = selectedModel()
        rateLimitsSubject.send(WireRateLimitsPayload(
            snapshot: WireRateLimitSnapshot(
                primary: nil,
                secondary: nil,
                credits: nil,
                limitId: "opencode_\(model.providerID)_\(model.modelID)",
                limitName: "\(model.providerID)/\(model.modelID) · usage unavailable"
            ),
            byLimitId: [:]
        ))
    }

    private func promptForOpenCode(text: String, attachments: [WireAttachment]) -> String {
        let imageCount = attachments.filter { $0.kind == .image }.count
        guard imageCount > 0 else { return text }
        let names = attachments.filter { $0.kind == .image }.map { $0.filename ?? $0.id }.joined(separator: ", ")
        let fallback = "Attached images are preserved in Clawix UI, but the selected OpenCode model does not accept image input. Use this textual attachment context instead: \(names)."
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : "\(fallback)\n\n\(text)"
    }

    private func userPreview(text: String, attachments: [WireAttachment]) -> String {
        let imageCount = attachments.filter { $0.kind == .image }.count
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard imageCount > 0 else { return text }
        let label = imageCount == 1 ? "[image fallback]" : "[\(imageCount) image fallbacks]"
        return trimmed.isEmpty ? label : "\(label) \(text)"
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

private final class OpenCodeClient {
    private let baseURL: URL
    private let process: Process?

    private init(baseURL: URL, process: Process?) {
        self.baseURL = baseURL
        self.process = process
    }

    static func start(defaults: UserDefaults, environment: [String: String]) async throws -> OpenCodeClient {
        if let raw = environment["CLAWIX_OPENCODE_BASE_URL"], let url = URL(string: raw) {
            return OpenCodeClient(baseURL: url, process: nil)
        }
        let port = UInt16(environment["CLAWIX_OPENCODE_PORT"] ?? "") ?? 18473
        let binary = environment["CLAWIX_OPENCODE_PATH"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "/opt/homebrew/bin/opencode"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw OpenCodeError.api("opencode binary not found")
        }
        let proc = Process()
        let secretsProxy = environment["CLAWIX_SECRETS_PROXY_PATH"].flatMap { $0.isEmpty ? nil : $0 }
        let deepseekSecretName = environment["CLAWIX_DEEPSEEK_SECRET_NAME"].flatMap { $0.isEmpty ? nil : $0 }
        if let secretsProxy,
           let deepseekSecretName,
           FileManager.default.isExecutableFile(atPath: secretsProxy),
           environment["DEEPSEEK_API_KEY"] == nil {
            proc.executableURL = URL(fileURLWithPath: secretsProxy)
            proc.arguments = [
                "exec",
                "--host", "api.deepseek.com",
                "--env", "DEEPSEEK_API_KEY={{\(deepseekSecretName)}}",
                "--",
                binary, "serve", "--hostname", "127.0.0.1", "--port", "\(port)"
            ]
        } else {
            proc.executableURL = URL(fileURLWithPath: binary)
            proc.arguments = ["serve", "--hostname", "127.0.0.1", "--port", "\(port)"]
        }
        if (defaults.string(forKey: "ClawixPermissionMode") ?? "") == "fullAccess" {
            proc.arguments?.append("--dangerously-skip-permissions")
        }
        proc.environment = environment
        let error = Pipe()
        proc.standardError = error
        error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            BridgedLog.write("opencode stderr \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        try proc.run()
        let client = OpenCodeClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            process: proc
        )
        try await client.waitUntilReady()
        return client
    }

    deinit {
        process?.terminate()
    }

    func sessions() async throws -> [[String: Any]] {
        let raw = try await request(path: "/session")
        return raw as? [[String: Any]] ?? []
    }

    func messages(sessionID: String) async throws -> [[String: Any]] {
        let raw = try await request(path: "/session/\(sessionID.urlPathEscaped)/message")
        return raw as? [[String: Any]] ?? []
    }

    func createSession(title: String, permission: [[String: String]]?) async throws -> [String: Any] {
        var body: [String: Any] = ["title": title]
        if let permission { body["permission"] = permission }
        let raw = try await request(
            path: "/session",
            method: "POST",
            query: ["directory": FileManager.default.homeDirectoryForCurrentUser.path],
            body: body
        )
        guard let session = raw as? [String: Any] else { throw OpenCodeError.invalidResponse }
        return session
    }

    func prompt(sessionID: String, providerID: String, modelID: String, text: String) async throws -> Any {
        try await request(
            path: "/session/\(sessionID.urlPathEscaped)/message",
            method: "POST",
            body: [
                "model": ["providerID": providerID, "modelID": modelID],
                "parts": [["type": "text", "text": text]]
            ]
        )
    }

    func abort(sessionID: String) async throws -> Any {
        try await request(path: "/session/\(sessionID.urlPathEscaped)/abort", method: "POST", body: [:])
    }

    func patchSession(sessionID: String, archived: Bool?, title: String?) async throws -> [String: Any] {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        if let archived {
            body["time"] = ["archived": archived ? Int(Date().timeIntervalSince1970 * 1000) : NSNull() as Any]
        }
        let raw = try await request(path: "/session/\(sessionID.urlPathEscaped)", method: "PATCH", body: body)
        guard let session = raw as? [String: Any] else { throw OpenCodeError.invalidResponse }
        return session
    }

    func replyPermission(requestID: String, reply: String) async throws -> Any {
        try await request(
            path: "/permission/\(requestID.urlPathEscaped)/reply",
            method: "POST",
            body: ["reply": reply]
        )
    }

    func events() async throws -> AsyncThrowingStream<[String: Any], Error> {
        let url = baseURL.appendingPathComponent("global/event")
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard raw != "[DONE]", let data = raw.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        continuation.yield(json)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            do {
                _ = try await request(path: "/config")
                return
            } catch {
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        throw OpenCodeError.api("OpenCode did not start")
    }

    private func request(path: String, method: String = "GET", query: [String: String] = [:], body: Any? = nil) async throws -> Any {
        var components = URLComponents(url: baseURL.appendingPathComponent(String(path.drop(while: { $0 == "/" }))), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw OpenCodeError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenCodeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenCode HTTP \(http.statusCode)"
            throw OpenCodeError.api(message)
        }
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func shortReason(_ error: Error) -> String {
        let raw = "\(error)".replacingOccurrences(of: "\n", with: " ")
        if raw.localizedCaseInsensitiveContains("DEEPSEEK_API_KEY") {
            return "DeepSeek key missing"
        }
        return String(raw.prefix(180))
    }
}

private enum OpenCodeError: Error, CustomStringConvertible {
    case notRunning
    case invalidURL
    case invalidResponse
    case api(String)

    var description: String {
        switch self {
        case .notRunning: return "OpenCode is not running"
        case .invalidURL: return "Invalid OpenCode URL"
        case .invalidResponse: return "Invalid OpenCode response"
        case .api(let message): return message
        }
    }
}

private extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}

private func dict(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func array(_ value: Any?) -> [Any]? {
    value as? [Any]
}

private func string(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? CustomStringConvertible { return value.description }
    return nil
}

private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func date(_ value: Any?) -> Date? {
    if let value = value as? Double {
        return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
    if let value = value as? Int {
        let double = Double(value)
        return Date(timeIntervalSince1970: double > 10_000_000_000 ? double / 1000 : double)
    }
    return nil
}

private func merge(existing: [WireMessage], incoming: [WireMessage]) -> [WireMessage] {
    var output = existing
    for message in incoming {
        if let idx = output.firstIndex(where: { $0.id == message.id }) {
            output[idx] = message
        } else {
            output.append(message)
        }
    }
    return output
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
