import Foundation
import SwiftUI

// Domain-level facade above ClawixClient. Owns the chat ↔ thread mapping
// and translates JSON-RPC notifications into AppState mutations.
//
// All public methods run on the main actor because they read/write
// AppState. Network I/O against `clawix app-server` happens off-actor
// inside ClawixClient.

@MainActor
final class ClawixService: ObservableObject {

    enum Status: Equatable {
        case idle
        case starting
        case ready
        case error(String)
    }

    @Published var status: Status = .idle
    @Published var availableModels: [ModelEntry] = []

    weak var appState: AppState?

    private let client: ClawixClient
    private var eventLoop: Task<Void, Never>?
    private var threadByChat: [UUID: String] = [:]
    private var chatByThread: [String: UUID] = [:]
    /// Per chat: active turn id and the placeholder assistant message id
    /// we append deltas onto.
    private var activeTurnByChat: [UUID: ActiveTurn] = [:]
    /// Turn ids the user has explicitly stopped. Notifications still in
    /// flight for these turns (deltas, item starts, even turn/completed)
    /// are dropped so they cannot resurrect the assistant placeholder we
    /// just cleared. An entry is removed when its turn/completed arrives.
    private var interruptedTurnIds: Set<String> = []

    struct ModelEntry: Equatable {
        let slug: String           // e.g. "gpt-5.5"
        let display: String        // "GPT-5.5"
    }

    private struct ActiveTurn {
        let turnId: String
        var assistantMessageId: UUID?
        var reasoningMessageId: UUID?
    }

    init(binary: ClawixBinaryInfo) {
        self.client = ClawixClient(binary: binary)
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard status == .idle else { return }
        status = .starting
        do {
            try await client.start()
            startEventLoop()
            _ = try await client.send(
                method: ClawixMethod.initialize,
                params: InitializeParams(
                    clientInfo: InitializeClientInfo(name: "Clawix", title: "Clawix", version: AppVersion.marketing),
                    capabilities: InitializeCapabilities(
                        experimentalApi: true,
                        optOutNotificationMethods: nil
                    )
                )
            )
            try await client.notify(method: ClawixMethod.initialized, params: EmptyObject())
            status = .ready
            await refreshModelList()
            await refreshRateLimits()
            await appState?.loadThreadsFromRuntime()
        } catch {
            status = .error(String(describing: error))
        }
    }

    private func refreshModelList() async {
        do {
            let result = try await client.send(
                method: ClawixMethod.modelList,
                params: EmptyObject(),
                expecting: ModelListResult.self
            )
            let entries: [ModelEntry] = (result.data ?? []).compactMap { entry in
                let slug = entry.slug ?? entry.id
                guard let slug else { return nil }
                let display = entry.displayName ?? slug
                return ModelEntry(slug: slug, display: display)
            }
            if !entries.isEmpty {
                self.availableModels = entries
            }
        } catch {
            // Non-fatal; AppState keeps its hardcoded fallback.
        }
    }

    private func refreshRateLimits() async {
        do {
            let response = try await client.send(
                method: ClawixMethod.accountRateLimitsRead,
                params: EmptyObject(),
                expecting: GetAccountRateLimitsResponse.self
            )
            appState?.rateLimits = response.rateLimits
            appState?.rateLimitsByLimitId = response.rateLimitsByLimitId ?? [:]
        } catch {
            appState?.rateLimits = nil
            appState?.rateLimitsByLimitId = [:]
        }
    }

    // MARK: - User intents

    func listThreads(archived: Bool, cwd: String? = nil, limit: Int = 160, useStateDbOnly: Bool = true) async throws -> [AgentThreadSummary] {
        try await listThreadsPage(archived: archived, cwd: cwd, limit: limit, useStateDbOnly: useStateDbOnly).threads
    }

    struct ThreadListPage {
        let threads: [AgentThreadSummary]
        let nextCursor: String?
    }

    func listThreadsPage(archived: Bool,
                         cwd: String? = nil,
                         cursor: String? = nil,
                         limit: Int = 160,
                         useStateDbOnly: Bool = true) async throws -> ThreadListPage {
        guard status == .ready else { return ThreadListPage(threads: [], nextCursor: nil) }
        let result = try await client.send(
            method: ClawixMethod.threadList,
            params: ThreadListParams(
                archived: archived,
                cursor: cursor,
                cwd: cwd,
                limit: limit,
                modelProviders: nil,
                searchTerm: nil,
                sortDirection: "desc",
                sortKey: "updated_at",
                sourceKinds: nil,
                useStateDbOnly: useStateDbOnly
            ),
            expecting: ThreadListResponse.self
        )
        let threads = result.data.map { thread -> AgentThreadSummary in
            var copy = thread
            copy.archived = archived
            return copy
        }
        return ThreadListPage(threads: threads, nextCursor: result.nextCursor)
    }

    func setThreadName(threadId: String, name: String) async throws {
        guard status == .ready else { return }
        _ = try await client.send(
            method: ClawixMethod.threadSetName,
            params: ThreadSetNameParams(threadId: threadId, name: name),
            expecting: ThreadSetNameResponse.self
        )
    }

    func archiveThread(threadId: String) async throws {
        guard status == .ready else { return }
        _ = try await client.send(
            method: ClawixMethod.threadArchive,
            params: ThreadArchiveParams(threadId: threadId),
            expecting: ThreadArchiveResponse.self
        )
    }

    func unarchiveThread(threadId: String) async throws {
        guard status == .ready else { return }
        _ = try await client.send(
            method: ClawixMethod.threadUnarchive,
            params: ThreadUnarchiveParams(threadId: threadId),
            expecting: ThreadUnarchiveResponse.self
        )
    }

    /// Send a prompt for an existing chat. Creates the underlying thread
    /// the first time. Returns immediately after enqueuing the turn —
    /// streaming results arrive via notifications.
    ///
    /// `imagePaths` carries optional inline image inputs already
    /// materialised on disk (see `AttachmentSpooler`). They are emitted
    /// after the text item so Codex sees the prompt body first; sending
    /// only images (empty `text`) is supported.
    func sendUserMessage(chatId: UUID, text: String, imagePaths: [String] = []) async {
        guard status == .ready else { return }

        do {
            let threadId = try await ensureThread(for: chatId)
            let modelSlug = appState?.clawixModelSlug
            let effort = appState?.clawixEffort
            let serviceTier = appState?.clawixServiceTier
            let collab = planCollaborationMode(modelSlug: modelSlug, effort: effort)
            var input: [TurnStartUserInput] = []
            if !text.isEmpty { input.append(.text(text)) }
            for path in imagePaths { input.append(.localImage(path: path)) }
            // Codex requires at least one input item; if both fields are
            // empty this is a no-op caller bug, but we still pass an
            // empty text so the runtime returns a clean error rather than
            // silently dropping the turn.
            if input.isEmpty { input.append(.text(text)) }
            let result = try await client.send(
                method: ClawixMethod.turnStart,
                params: TurnStartParams(
                    threadId: threadId,
                    input: input,
                    model: modelSlug,
                    effort: effort,
                    serviceTier: serviceTier,
                    activeSkills: nil,
                    collaborationMode: collab
                ),
                expecting: TurnStartResult.self
            )
            activeTurnByChat[chatId] = ActiveTurn(
                turnId: result.turn.id,
                assistantMessageId: nil,
                reasoningMessageId: nil
            )
            appState?.markChat(chatId: chatId, hasActiveTurn: true)
        } catch {
            appState?.appendErrorBubble(chatId: chatId, message: String(describing: error))
        }
    }

    /// Builds the `collaborationMode` payload reflecting the global plan-
    /// mode toggle. Returns nil when plan mode is off so older daemons
    /// (which don't know the field) keep their default behaviour.
    private func planCollaborationMode(modelSlug: String?, effort: String?) -> CollaborationModePayload? {
        guard let appState, appState.planMode else { return nil }
        return CollaborationModePayload(
            mode: "plan",
            settings: CollaborationModeSettingsPayload(
                model: modelSlug ?? "gpt-5.5",
                developer_instructions: nil,
                reasoning_effort: effort
            )
        )
    }

    /// Resolve a pending `item/tool/requestUserInput` request with the
    /// user's answers. Empty arrays mean "skipped/dismissed" — the
    /// daemon unblocks the turn either way.
    func respondToPlanQuestion(rpcId: ClawixRPCID, answers: [String: [String]]) async {
        let body = ToolRequestUserInputResponse(
            answers: answers.mapValues { ToolRequestUserInputAnswer(answers: $0) }
        )
        try? await client.resolveServerRequest(id: rpcId, result: body)
    }

    func interruptCurrentTurn(chatId: UUID) async {
        guard let active = activeTurnByChat[chatId],
              let threadId = threadByChat[chatId] else { return }
        // Mark the turn as interrupted BEFORE awaiting the network call so
        // any deltas/items already queued in the event loop for this turn
        // are dropped instead of recreating the assistant placeholder
        // AppState just removed.
        interruptedTurnIds.insert(active.turnId)
        activeTurnByChat[chatId] = nil
        appState?.markChat(chatId: chatId, hasActiveTurn: false)
        // If a plan-mode question was outstanding for this chat, dismiss
        // it on the wire so the daemon doesn't hang and our UI clears.
        await dismissPendingPlanQuestionIfAny(chatId: chatId)
        _ = try? await client.send(
            method: ClawixMethod.turnInterrupt,
            params: TurnInterruptParams(threadId: threadId, turnId: active.turnId)
        )
    }

    private func dismissPendingPlanQuestionIfAny(chatId: UUID) async {
        guard let pending = appState?.pendingPlanQuestions[chatId] else { return }
        appState?.pendingPlanQuestions[chatId] = nil
        let empty: [String: [String]] = Dictionary(
            uniqueKeysWithValues: pending.questions.map { ($0.id, [String]()) }
        )
        await respondToPlanQuestion(rpcId: pending.rpcId, answers: empty)
    }

    /// Edit a previous user message: rollback the thread up to and
    /// including that user message's turn, then re-issue `turn/start`
    /// with the new prompt. AppState is responsible for trimming the
    /// local message list before calling this so the UI shows the
    /// edited bubble alone while the new turn streams in.
    func editAndResubmit(chatId: UUID, numTurnsToDrop: Int, newText: String) async {
        guard status == .ready, numTurnsToDrop > 0 else { return }
        guard let threadId = threadByChat[chatId] else {
            // No backend thread yet, nothing to roll back. Treat as a
            // plain new turn.
            await sendUserMessage(chatId: chatId, text: newText)
            return
        }

        if let active = activeTurnByChat[chatId] {
            interruptedTurnIds.insert(active.turnId)
            activeTurnByChat[chatId] = nil
            appState?.markChat(chatId: chatId, hasActiveTurn: false)
            _ = try? await client.send(
                method: ClawixMethod.turnInterrupt,
                params: TurnInterruptParams(threadId: threadId, turnId: active.turnId)
            )
        }

        do {
            _ = try await client.send(
                method: ClawixMethod.threadRollback,
                params: ThreadRollbackParams(threadId: threadId, numTurns: numTurnsToDrop),
                expecting: ThreadRollbackResult.self
            )
        } catch {
            appState?.appendErrorBubble(chatId: chatId, message: String(describing: error))
            return
        }

        await sendUserMessage(chatId: chatId, text: newText)
    }

    /// Fork the parent thread into a new server-side thread and bind it
    /// to `newChatId`. Returns the new thread id on success. The runtime
    /// copies the parent's rollout into the new session and stamps it
    /// with `forked_from_id` so the forked chat resumes with full
    /// context on the next `turn/start`.
    func forkThread(parentThreadId: String, newChatId: UUID) async throws -> String {
        guard status == .ready else {
            throw NSError(
                domain: "ClawixService.fork",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Backend not ready"]
            )
        }
        let result = try await client.send(
            method: ClawixMethod.threadFork,
            params: ThreadForkParams(threadId: parentThreadId, excludeTurns: true),
            expecting: ThreadForkResult.self
        )
        let newThreadId = result.thread.id
        threadByChat[newChatId] = newThreadId
        chatByThread[newThreadId] = newChatId
        appState?.attachThreadId(newThreadId, to: newChatId)
        return newThreadId
    }

    /// Bind an existing chat to a server thread when the sidebar opens a
    /// runtime-indexed conversation.
    func attach(chatId: UUID, threadId: String) async {
        threadByChat[chatId] = threadId
        chatByThread[threadId] = chatId
        guard status == .ready else { return }
        _ = try? await client.send(
            method: ClawixMethod.threadResume,
            params: ThreadResumeParams(threadId: threadId)
        )
    }

    // MARK: - Internal: thread bootstrap

    private func ensureThread(for chatId: UUID) async throws -> String {
        if let id = threadByChat[chatId] { return id }
        let cwd = appState?.threadCwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let modelSlug = appState?.clawixModelSlug
        let serviceTier = appState?.clawixServiceTier
        let permissionMode = appState?.permissionMode ?? .defaultPermissions
        let result = try await client.send(
            method: ClawixMethod.threadStart,
            params: ThreadStartParams(
                cwd: cwd,
                model: modelSlug,
                approvalPolicy: permissionMode.codexApprovalPolicy,
                sandbox: permissionMode.codexSandbox,
                personality: appState?.personality.rawValue,
                serviceTier: serviceTier,
                activeSkills: nil,
                collaborationMode: nil
            ),
            expecting: ThreadStartResult.self
        )
        let threadId = result.thread.id
        threadByChat[chatId] = threadId
        chatByThread[threadId] = chatId
        appState?.attachThreadId(threadId, to: chatId)
        return threadId
    }

    // MARK: - Event loop

    private func startEventLoop() {
        eventLoop?.cancel()
        let stream = client.events
        eventLoop = Task { [weak self] in
            for await event in stream {
                await self?.handle(event: event)
            }
        }
    }

    private func handle(event: ClawixServerEvent) async {
        switch event {
        case let .request(id, method, params):
            await handleServerRequest(id: id, method: method, params: params)
        case let .notification(method, params):
            handleNotification(method: method, params: params)
        }
    }

    /// Server-initiated requests (other than approvals, which the
    /// transport layer auto-declines). Currently we only care about
    /// `item/tool/requestUserInput` — that's how plan-mode questions
    /// arrive.
    private func handleServerRequest(id: ClawixRPCID, method: String, params: JSONValue?) async {
        guard method == ClawixMethod.rToolUserInput else { return }
        guard let payload = try? params?.decode(ToolRequestUserInputParams.self),
              !interruptedTurnIds.contains(payload.turnId),
              let chatId = chatByThread[payload.threadId]
        else {
            // Decode failure or stale request: unblock the daemon with an
            // empty answers map so it doesn't hang forever.
            try? await client.resolveServerRequest(
                id: id,
                result: ToolRequestUserInputResponse(answers: [:])
            )
            return
        }
        let pending = PendingPlanQuestion(
            rpcId: id,
            chatId: chatId,
            threadId: payload.threadId,
            turnId: payload.turnId,
            itemId: payload.itemId,
            questions: payload.questions
        )
        appState?.registerPendingPlanQuestion(pending)
    }

    private func handleNotification(method: String, params: JSONValue?) {
        switch method {
        case ClawixMethod.nTurnStarted:
            if let payload = try? params?.decode(TurnEnvelope.self),
               !interruptedTurnIds.contains(payload.turn.id),
               let chatId = chatByThread[payload.threadId] {
                // Eagerly create the assistant placeholder so the
                // elapsed-time header can render the live counter even
                // before the first agent/reasoning delta (which can be
                // many seconds later when tools run first).
                ensureAssistantPlaceholder(chatId: chatId, turnId: payload.turn.id)
                if let mid = activeTurnByChat[chatId]?.assistantMessageId {
                    appState?.beginWorkSummary(chatId: chatId, messageId: mid, startedAt: Date())
                }
            }

        case ClawixMethod.nAgentMsgDelta:
            if let payload = try? params?.decode(AgentMessageDelta.self),
               !interruptedTurnIds.contains(payload.turnId),
               let chatId = chatByThread[payload.threadId] {
                ensureAssistantPlaceholder(chatId: chatId, turnId: payload.turnId)
                appState?.appendAssistantDelta(chatId: chatId, delta: payload.delta)
            }

        case ClawixMethod.nReasoningDelta, ClawixMethod.nReasoningSumDelta:
            if let payload = try? params?.decode(ReasoningTextDelta.self),
               !interruptedTurnIds.contains(payload.turnId),
               let chatId = chatByThread[payload.threadId] {
                ensureAssistantPlaceholder(chatId: chatId, turnId: payload.turnId)
                appState?.appendReasoningDelta(chatId: chatId, delta: payload.delta)
            }

        case ClawixMethod.nItemStarted:
            handleItem(params: params, completed: false)

        case ClawixMethod.nItemCompleted:
            handleItem(params: params, completed: true)

        case ClawixMethod.nTurnCompleted:
            if let payload = try? params?.decode(TurnEnvelope.self),
               let chatId = chatByThread[payload.threadId] {
                let turnId = payload.turn.id
                if interruptedTurnIds.remove(turnId) != nil {
                    // User-stopped turn finished server-side. State
                    // already cleared on interrupt; nothing to do.
                } else {
                    if let mid = activeTurnByChat[chatId]?.assistantMessageId {
                        appState?.completeWorkSummary(chatId: chatId, messageId: mid, endedAt: Date())
                    }
                    // Flip `streamingFinished` here, NOT on agentMessage
                    // item completion: the model may emit an intermediate
                    // agentMessage (a preamble) before tool calls and a
                    // separate final answer afterwards, so item-level
                    // completion isn't a reliable end-of-turn signal.
                    // Pass `finalText: nil` so we trust the accumulated
                    // deltas instead of replacing `content` with just the
                    // last segment (which would erase the preamble).
                    appState?.markAssistantCompleted(chatId: chatId, finalText: nil)
                    activeTurnByChat.removeValue(forKey: chatId)
                    appState?.markChat(chatId: chatId, hasActiveTurn: false)
                    // The turn finished without consuming the question
                    // (user closed, daemon errored). Drop it so the
                    // sidebar pill and chat card disappear.
                    appState?.pendingPlanQuestions[chatId] = nil
                    appState?.maybeGenerateTitleAfterTurn(chatId: chatId)
                }
            }

        case ClawixMethod.nThreadStarted:
            // Server-emitted echo; nothing to do, we already know.
            break

        case ClawixMethod.nThreadTokenUsage:
            if let payload = try? params?.decode(ThreadTokenUsageEnvelope.self),
               let chatId = chatByThread[payload.threadId] {
                appState?.updateTokenUsage(chatId: chatId, usage: payload.tokenUsage)
            }

        case ClawixMethod.nAccountRateLimitsUpdated:
            if let payload = try? params?.decode(AccountRateLimitsUpdatedNotification.self) {
                appState?.rateLimits = payload.rateLimits
                if let buckets = payload.rateLimitsByLimitId {
                    appState?.rateLimitsByLimitId = buckets
                }
            }

        case ClawixMethod.nThreadArchived:
            if let payload = try? params?.decode(ThreadIdNotification.self) {
                appState?.markThreadArchived(threadId: payload.threadId, archived: true)
            }

        case ClawixMethod.nThreadUnarchived:
            if let payload = try? params?.decode(ThreadIdNotification.self) {
                appState?.markThreadArchived(threadId: payload.threadId, archived: false)
            }

        case ClawixMethod.nThreadNameUpdated:
            if let payload = try? params?.decode(ThreadNameUpdatedNotification.self),
               let name = payload.threadName {
                appState?.applyRuntimeTitle(threadId: payload.threadId, title: name)
            }

        case ClawixMethod.nError:
            // Surface a generic error; specific parsing is out of v1 scope.
            break

        default:
            break
        }
    }

    /// Shared item/started + item/completed handler. Two responsibilities:
    ///   1. agentMessage items: when completed, finalize the assistant text.
    ///   2. tool items (commandExecution, fileChange, webSearch,
    ///      mcpToolCall, dynamicToolCall, imageGeneration, imageView):
    ///      register/refresh a WorkItem entry on the assistant message so
    ///      the elapsed-time disclosure has something to show.
    private func handleItem(params: JSONValue?, completed: Bool) {
        guard let payload = try? params?.decode(ItemEnvelope.self),
              !interruptedTurnIds.contains(payload.turnId),
              let chatId = chatByThread[payload.threadId]
        else { return }

        if payload.item.type == "agentMessage" {
            // Don't flip `streamingFinished` here. A turn can include an
            // intermediate agentMessage (preamble like "Voy a listar
            // ...") before any tool runs, plus a separate final-answer
            // agentMessage. If we flipped on item-completed, the timeline
            // would collapse mid-turn and the preamble would be wiped by
            // the canonical-text replacement when the second item lands.
            // The end-of-turn flip lives in `nTurnCompleted` instead.
            return
        }

        guard let kind = workItemKind(from: payload.item) else { return }
        ensureAssistantPlaceholder(chatId: chatId, turnId: payload.turnId)
        guard let messageId = activeTurnByChat[chatId]?.assistantMessageId else { return }
        let status: WorkItemStatus = mapWorkStatus(payload.item.status, completed: completed)
        // For `imageGeneration` items, build the deterministic on-disk
        // path Codex uses
        // (`~/.codex/generated_images/<threadId>/<callId>.png`) so the
        // bridge can serve the bytes without waiting for the rollout
        // to be re-read on the next chat open. The path may not exist
        // yet during `inProgress`; the iPhone retries on snapshot.
        var generatedImagePath: String? = nil
        if case .imageGeneration = kind {
            generatedImagePath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("generated_images", isDirectory: true)
                .appendingPathComponent(payload.threadId, isDirectory: true)
                .appendingPathComponent("\(payload.item.id).png")
                .path
        }
        let item = WorkItem(
            id: payload.item.id,
            kind: kind,
            status: status,
            generatedImagePath: generatedImagePath
        )
        appState?.upsertWorkItem(chatId: chatId, messageId: messageId, item: item)
    }

    private func workItemKind(from item: ItemPayload) -> WorkItemKind? {
        switch item.type {
        case "commandExecution":
            let actions = (item.commandActions ?? []).map { p -> CommandActionKind in
                CommandActionKind(rawValue: p.type) ?? .unknown
            }
            return .command(text: item.command, actions: actions)
        case "fileChange":
            return .fileChange(paths: (item.changes ?? []).map(\.path))
        case "webSearch":
            return .webSearch
        case "mcpToolCall":
            return .mcpTool(server: item.server ?? "", tool: item.tool ?? "")
        case "dynamicToolCall":
            return .dynamicTool(name: item.tool ?? "")
        case "imageGeneration":
            return .imageGeneration
        case "imageView":
            return .imageView
        default:
            return nil
        }
    }

    private func mapWorkStatus(_ raw: String?, completed: Bool) -> WorkItemStatus {
        switch raw {
        case "completed": return .completed
        case "failed", "declined": return .failed
        case "inProgress": return .inProgress
        default: return completed ? .completed : .inProgress
        }
    }

    private func ensureAssistantPlaceholder(chatId: UUID, turnId: String) {
        if activeTurnByChat[chatId]?.turnId != turnId {
            activeTurnByChat[chatId] = ActiveTurn(
                turnId: turnId,
                assistantMessageId: nil,
                reasoningMessageId: nil
            )
        }
        if activeTurnByChat[chatId]?.assistantMessageId == nil {
            let id = appState?.appendAssistantPlaceholder(chatId: chatId)
            activeTurnByChat[chatId]?.assistantMessageId = id
        }
    }
}

private struct EmptyObject: Encodable {}
