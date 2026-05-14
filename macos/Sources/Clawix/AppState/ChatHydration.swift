import Foundation
import SwiftUI
import ClawixCore

extension AppState {
    // MARK: - Clawix bridge helpers

    /// CWD reported to thread/start. Falls back to $HOME so Clawix never
    /// refuses to start. Order: current chat's project > selectedProject > $HOME.
    var threadCwd: String {
        if case let .chat(id) = currentRoute,
           let chat = chats.first(where: { $0.id == id }),
           let pid = chat.projectId,
           let proj = projects.first(where: { $0.id == pid }) {
            let expanded = (proj.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        if let project = selectedProject {
            let expanded = (project.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Maps the dropdown label ("5.5", "5.4 Mini", …) to a Clawix slug.
    var clawixModelSlug: String? {
        guard selectedAgentRuntime == .codex else { return nil }
        let raw = selectedModel.lowercased().replacingOccurrences(of: " ", with: "-")
        return "gpt-\(raw)"
    }

    var clawixEffort: String? {
        selectedIntelligence.clawixEffort
    }

    /// "fast" → priority queue (1.5× faster, higher usage).
    /// `nil` → default tier. The schema also accepts "flex" but the
    /// composer does not expose it today.
    var clawixServiceTier: String? {
        switch selectedSpeed {
        case .standard: return nil
        case .fast:     return "fast"
        }
    }

    /// Resolve the active skills set for a chat at the moment we're
    /// about to dispatch a `thread/start` or `turn/start`. Walks the
    /// global → project → chat hierarchy via `SkillsStore.resolveActive`
    /// and converts the result to the wire shape (`ActiveSkill`). Nil
    /// when the store hasn't been initialised yet (e.g. during preview
    /// rendering or extremely early bootstrap).
    func skillsActiveSnapshot(for chatId: UUID) -> [ActiveSkill]? {
        guard let store = skillsStore else { return nil }
        let projectId = chat(byId: chatId)?.projectId?.uuidString
        let states = store.resolveActive(projectId: projectId, chatId: chatId)
        guard !states.isEmpty else { return nil }
        return states.map { $0.toWire() }
    }

    func ensureSelectedChat(triggerHistoryHydration: Bool = true) {
        guard case let .chat(id) = currentRoute,
              let chat = chat(byId: id) else { return }
        if triggerHistoryHydration && shouldHydrateHistory(chat) {
            hydrateHistoryIfNeeded(chatId: id)
        }
    }

    private func shouldHydrateHistory(_ chat: Chat) -> Bool {
        if !chat.historyHydrated { return true }
        return chat.messages.isEmpty && (chat.rolloutPath != nil || chat.clawixThreadId != nil)
    }

    /// Find a chat by id across both the active and archived lists. The
    /// sidebar's archived section opens chats via the same `.chat(id)`
    /// route, so any view that resolves the current chat must accept ids
    /// from either bucket.
    func chat(byId id: UUID) -> Chat? {
        if let chat = chats.first(where: { $0.id == id }) { return chat }
        return archivedChats.first(where: { $0.id == id })
    }

    /// Apply `mutate` to whichever array currently holds the chat. No-op
    /// if the id is unknown. Used by hydration paths that need to write
    /// back into the chat regardless of its archived state.
    private func mutateChat(id: UUID, _ mutate: (inout Chat) -> Void) {
        if let idx = chats.firstIndex(where: { $0.id == id }) {
            mutate(&chats[idx])
        } else if let idx = archivedChats.firstIndex(where: { $0.id == id }) {
            mutate(&archivedChats[idx])
        }
    }

    func hydrateHistoryIfNeeded(chatId: UUID, blocking: Bool = false) {
        guard let chat = chat(byId: chatId), shouldHydrateHistory(chat) else { return }
        if FeatureFlags.shared.isVisible(.git), !chat.hasGitRepo, let cwd = chat.cwd {
            if blocking {
                applyGitSnapshot(GitInspector.inspect(cwd: cwd), chatId: chatId)
            } else {
                scheduleGitInspection(chatId: chatId, cwd: cwd)
            }
        }
        if let threadId = chat.clawixThreadId {
            hydrateHistoryFromClawJSSessions(threadId: threadId, chatId: chatId, blocking: blocking)
        } else if let path = chat.rolloutPath {
            // Mac UI path (`blocking == false`): read off the main
            // actor AND only the trailing window of the JSONL so a
            // multi-hundred-MB rollout doesn't stall hydration. The
            // chat opens at the latest turn, the user almost never
            // scrolls hundreds of turns up immediately, and the
            // snapshot has already painted the sidebar; capping the
            // parse cost keeps "click chat → first paint" sub-second
            // regardless of total file size. iOS-bridge path
            // (`blocking == true`): the bridge composes its response
            // inline and needs the full history before it returns,
            // so keep the synchronous full read.
            if blocking {
                applyRolloutResult(RolloutReader.readWithStatus(path: path), chatId: chatId)
            } else {
                Task.detached(priority: .userInitiated) { [weak self] in
                    let result = RolloutReader.readTailWithStatus(path: path)
                    let messages = rolloutChatMessages(from: result)
                    await MainActor.run { [weak self] in
                        self?.applyRolloutMessages(
                            messages,
                            lastTurnInterrupted: result.lastTurnInterrupted,
                            chatId: chatId
                        )
                    }
                }
            }
        }
        if let threadId = chat.clawixThreadId, let clawix {
            Task { @MainActor in
                await clawix.attach(chatId: chat.id, threadId: threadId)
            }
        }
    }

    private func scheduleGitInspection(chatId: UUID, cwd: String) {
        guard gitInspectionTasks[chatId] == nil else { return }
        gitInspectionTasks[chatId] = Task.detached(priority: .utility) { [weak self] in
            let git = GitInspector.inspect(cwd: cwd)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gitInspectionTasks[chatId] = nil
                guard self.chat(byId: chatId)?.cwd == cwd else { return }
                self.applyGitSnapshot(git, chatId: chatId)
            }
        }
    }

    private func applyGitSnapshot(_ git: GitSnapshot, chatId: UUID) {
        mutateChat(id: chatId) { c in
            c.hasGitRepo = git.hasRepo
            c.branch = git.branch
            c.availableBranches = git.branches
            c.uncommittedFiles = git.uncommittedFiles
        }
    }

    private func applyRolloutResult(_ result: RolloutReader.ReadResult, chatId: UUID) {
        applyRolloutMessages(
            rolloutChatMessages(from: result),
            lastTurnInterrupted: result.lastTurnInterrupted,
            chatId: chatId
        )
    }

    private func hydrateHistoryFromClawJSSessions(threadId: String, chatId: UUID, blocking: Bool) {
        let client = ClawJSSessionsClient.local()
        if blocking {
            // The bridge entry point is synchronous. Do not fall back to
            // scanning Codex rollouts here; the daemon/session sidecar is the
            // boundary. The async UI path below will hydrate the chat when it
            // can reach the service.
            return
        }
        Task { @MainActor [weak self] in
            do {
                let records = try await client.listMessages(sessionId: threadId)
                let messages = records.map(Self.chatMessage(fromClawJSSessionMessage:))
                self?.applyRolloutMessages(
                    messages,
                    lastTurnInterrupted: false,
                    chatId: chatId
                )
            } catch {
                self?.appendRuntimeStatusError("Could not load ClawJS session history: \(error.localizedDescription)")
            }
        }
    }

    private static func chatMessage(fromClawJSSessionMessage record: ClawJSSessionsClient.MessageRecord) -> ChatMessage {
        let seconds = record.timestamp > 10_000_000_000 ? Double(record.timestamp) / 1000.0 : Double(record.timestamp)
        return ChatMessage(
            role: record.role == "user" ? .user : .assistant,
            content: record.contentText,
            reasoningText: "",
            streamingFinished: record.streamingState != "streaming",
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    private func applyRolloutMessages(
        _ messages: [ChatMessage],
        lastTurnInterrupted: Bool,
        chatId: UUID
    ) {
        mutateChat(id: chatId) { c in
            c.messages = messages
            c.lastTurnInterrupted = lastTurnInterrupted
            c.historyHydrated = true
        }
    }


    /// Bridge entry point. Hydrates a chat's history from its rollout
    /// file the first time the iPhone opens it, mirroring what the Mac
    /// UI does the moment a chat row is clicked. Without this the
    /// iPhone gets `messagesSnapshot([])` for every `notLoaded` thread
    /// and the user only sees the "no messages loaded" empty state.
    /// Idempotent: subsequent calls for the same chat are no-ops.
    func hydrateHistoryFromBridge(chatId: UUID) {
        guard chat(byId: chatId) != nil else { return }
        // Bridge response composes inline; the iPhone needs messages
        // before this returns. Keeps the legacy synchronous rollout
        // read for that one call site.
        hydrateHistoryIfNeeded(chatId: chatId, blocking: true)
    }

    func applyDaemonChats(_ wireChats: [WireChat]) {
        cachedWireChats = wireChats
        // Refresh `projects` from the latest backendState before
        // resolving each wire chat's project: the daemon may have
        // delivered a snapshot that references workspace roots Codex
        // has just learned about, and `chat(from:wire,old:)` reads
        // through the in-memory `projects` array.
        projects = mergedProjects()
        let oldById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        let oldArchivedById = Dictionary(uniqueKeysWithValues: archivedChats.map { ($0.id, $0) })
        // Wire chats from the daemon mint their own UUIDs each
        // process restart, so matching `old` only by UUID misses
        // every persisted chat. Add a thread-id index so we recover
        // any per-chat metadata (messages, hasGitRepo, branch, etc.)
        // the GUI had cached against the previous daemon UUID.
        let oldByThreadId = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })
        let oldArchivedByThreadId = Dictionary(uniqueKeysWithValues: archivedChats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat) }
        })
        func resolveOld(for wire: WireChat) -> Chat? {
            if let id = UUID(uuidString: wire.id) {
                if let hit = oldById[id] ?? oldArchivedById[id] { return hit }
            }
            if let tid = wire.threadId {
                return oldByThreadId[tid] ?? oldArchivedByThreadId[tid]
            }
            return nil
        }
        var nextChats: [Chat] = wireChats.compactMap { wire in
            guard !wire.isArchived else { return nil }
            return chat(from: wire, old: resolveOld(for: wire))
        }
        var nextArchived: [Chat] = wireChats.compactMap { wire in
            guard wire.isArchived else { return nil }
            return chat(from: wire, old: resolveOld(for: wire))
        }
        if case let .chat(id) = currentRoute,
           let selected = chat(byId: id),
           let threadId = selected.clawixThreadId,
           !wireChats.contains(where: { $0.threadId?.caseInsensitiveCompare(threadId) == .orderedSame }) {
            if selected.isArchived {
                if !nextArchived.contains(where: { $0.id == selected.id || $0.clawixThreadId == selected.clawixThreadId }) {
                    nextArchived.insert(selected, at: 0)
                }
            } else if !nextChats.contains(where: { $0.id == selected.id || $0.clawixThreadId == selected.clawixThreadId }) {
                nextChats.insert(selected, at: 0)
            }
        }
        // Fast path: the daemon resends the same chat snapshot on every
        // streaming delta. When nothing actually changed, skip the
        // assignment (which would trigger `objectWillChange` and fan
        // out a full sidebar re-render) and skip the pinnedOrder
        // recompute too (pins haven't moved if the chat list is
        // identical).
        if chats == nextChats && archivedChats == nextArchived { return }
        // Identity-only diff: same ids in the same order, only some
        // slot's contents differ. Mutate those slots in place so each
        // updated row publishes a single change instead of triggering
        // an animated insert/remove transition on every row of the
        // sidebar via `withAnimation` over a wholesale array copy.
        let sameIdentity = chats.count == nextChats.count
            && zip(chats, nextChats).allSatisfy { $0.id == $1.id }
            && archivedChats.count == nextArchived.count
            && zip(archivedChats, nextArchived).allSatisfy { $0.id == $1.id }
        if sameIdentity {
            for idx in nextChats.indices where chats[idx] != nextChats[idx] {
                chats[idx] = nextChats[idx]
            }
            for idx in nextArchived.indices where archivedChats[idx] != nextArchived[idx] {
                archivedChats[idx] = nextArchived[idx]
            }
        } else {
            // Structural diff (insert / remove / reorder). Animate so
            // rows slide in/out via the accordion's per-row transition.
            withAnimation(.easeOut(duration: 0.20)) {
                chats = nextChats
                archivedChats = nextArchived
            }
        }
        // Recompute `pinnedOrder` against the freshly applied chats:
        // either honour the user's local pin order (if they've taken
        // control) or fall back to Codex's global state. Without
        // this the Pinned section would render unsorted because the
        // daemon's wire chats have brand-new UUIDs every reconnect.
        let pinIds = pinsRepo.orderedThreadIds()
        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
    }

    func applyDaemonChat(_ wire: WireChat) {
        guard let id = UUID(uuidString: wire.id) else { return }
        if let idx = cachedWireChats.firstIndex(where: { $0.id == wire.id }) {
            cachedWireChats[idx] = wire
        } else {
            cachedWireChats.append(wire)
        }
        withAnimation(.easeOut(duration: 0.20)) {
            if wire.isArchived {
                let old = chats.first(where: { $0.id == id }) ?? archivedChats.first(where: { $0.id == id })
                chats.removeAll { $0.id == id }
                let chat = chat(from: wire, old: old)
                if let idx = archivedChats.firstIndex(where: { $0.id == id }) {
                    archivedChats[idx] = chat
                } else {
                    archivedChats.insert(chat, at: 0)
                }
                return
            }
            if let archivedIndex = archivedChats.firstIndex(where: { $0.id == id }) {
                let chat = chat(from: wire, old: archivedChats[archivedIndex])
                archivedChats.remove(at: archivedIndex)
                chats.insert(chat, at: 0)
                return
            }
            if let idx = chats.firstIndex(where: { $0.id == id }) {
                chats[idx] = chat(from: wire, old: chats[idx])
            } else {
                chats.insert(chat(from: wire, old: nil), at: 0)
            }
        }
    }

    func applyDaemonMessages(chatId: String, messages: [WireMessage], hasMore: Bool? = nil) {
        cachedWireMessagesByChat[chatId] = messages
        guard let id = UUID(uuidString: chatId) else { return }
        // Reset pagination state regardless of where the chat lives:
        // the snapshot is the new baseline. Treat absent metadata as
        // "no older history known" so legacy daemons keep their old
        // eager behaviour.
        messagesPaginationByChat[id] = ChatPagination(
            oldestKnownId: messages.first?.id,
            hasMore: hasMore ?? false,
            loadingOlder: false
        )
        guard let idx = chats.firstIndex(where: { $0.id == id }) else { return }
        // Wholesale rehydrate from the daemon: drop any buffered text
        // delta that would otherwise pile on top of the canonical body.
        dropPendingAssistantText(chatId: id)
        if messages.isEmpty,
           chats[idx].forkedFromChatId != nil,
           !chats[idx].messages.isEmpty {
            chats[idx].historyHydrated = true
            return
        }
        if messages.isEmpty,
           !chats[idx].messages.isEmpty,
           (chats[idx].rolloutPath != nil || chats[idx].clawixThreadId != nil) {
            chats[idx].historyHydrated = true
            return
        }
        // The daemon's `RolloutHistory` reader is intentionally minimal
        // and never populates `timeline` / `workSummary`, so a fresh
        // `messagesSnapshot` would wipe both fields off any local message
        // that already had them (e.g. hydrated from cache or seeded by an
        // earlier `RolloutReader` pass on this Mac). Carry them forward
        // by id so the chat row's "Worked for Xs" header doesn't flash
        // and disappear when the daemon snapshot lands.
        let oldById = Dictionary(uniqueKeysWithValues: chats[idx].messages.map { ($0.id, $0) })
        chats[idx].messages = messages.compactMap { wire in
            chatMessage(from: wire, fallbackingTo: UUID(uuidString: wire.id).flatMap { oldById[$0] })
        }
        optimisticUserMessageIdsByChat[id] = nil
        chats[idx].historyHydrated = true
    }

    func trackOptimisticUserMessage(chatId: UUID, messageId: UUID) {
        optimisticUserMessageIdsByChat[chatId, default: []].insert(messageId)
    }

    func appendDaemonMessage(chatId: String, message: WireMessage) {
        // Mirror first so the snapshot persist sees the same shape the
        // chat detail does, regardless of whether the chat exists in
        // the local model yet (newChat path lands a `messageAppended`
        // before `chatUpdated`).
        if let mIdx = cachedWireMessagesByChat[chatId]?.firstIndex(where: { $0.id == message.id }) {
            cachedWireMessagesByChat[chatId]?[mIdx] = message
        } else {
            cachedWireMessagesByChat[chatId, default: []].append(message)
        }
        guard let id = UUID(uuidString: chatId),
              let idx = chats.firstIndex(where: { $0.id == id })
        else { return }
        // Same fallback as `applyDaemonMessages`: preserve any local
        // `workSummary` / `timeline` the daemon's wire form drops on the
        // floor, keyed by message id.
        let existing = UUID(uuidString: message.id).flatMap { mid in
            chats[idx].messages.first(where: { $0.id == mid })
        }
        guard let msg = chatMessage(from: message, fallbackingTo: existing) else { return }
        // The daemon's wire message is authoritative; any locally
        // buffered delta would double-append on top of it.
        dropPendingAssistantText(chatId: id)
        if msg.role == .user,
           let replacementIdx = optimisticUserReplacementIndex(chatId: id, remote: msg, messages: chats[idx].messages) {
            let localId = chats[idx].messages[replacementIdx].id
            chats[idx].messages[replacementIdx] = msg
            optimisticUserMessageIdsByChat[id]?.remove(localId)
            if optimisticUserMessageIdsByChat[id]?.isEmpty == true {
                optimisticUserMessageIdsByChat[id] = nil
            }
            return
        }
        if let existingIdx = chats[idx].messages.firstIndex(where: { $0.id == msg.id }) {
            chats[idx].messages[existingIdx] = msg
        } else {
            chats[idx].messages.append(msg)
        }
    }

    private func optimisticUserReplacementIndex(
        chatId: UUID,
        remote: ChatMessage,
        messages: [ChatMessage]
    ) -> Int? {
        guard let pending = optimisticUserMessageIdsByChat[chatId], !pending.isEmpty else { return nil }
        if let exact = messages.firstIndex(where: {
            pending.contains($0.id) && $0.role == .user && $0.content == remote.content
        }) {
            return exact
        }
        return messages.firstIndex(where: {
            pending.contains($0.id) && $0.role == .user
        })
    }


    /// Daemon-bridge mode counterpart of `ClawixService.refreshRateLimits`:
    /// the GUI's own backend never bootstraps when the LaunchAgent owns
    /// Codex, so the daemon ships its `account/rateLimits/read` view
    /// over the bridge and we land it on the same `@Published` fields
    /// the sidebar / Settings → Usage page already render off.
    func applyDaemonRateLimits(
        snapshot: WireRateLimitSnapshot?,
        byLimitId: [String: WireRateLimitSnapshot]
    ) {
        rateLimits = snapshot.map(rateLimitSnapshot(from:))
        var mapped: [String: RateLimitSnapshot] = [:]
        for (key, value) in byLimitId {
            mapped[key] = rateLimitSnapshot(from: value)
        }
        rateLimitsByLimitId = mapped
    }

    private func rateLimitSnapshot(from wire: WireRateLimitSnapshot) -> RateLimitSnapshot {
        RateLimitSnapshot(
            primary: wire.primary.map { RateLimitWindow(
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                windowDurationMins: $0.windowDurationMins
            )},
            secondary: wire.secondary.map { RateLimitWindow(
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                windowDurationMins: $0.windowDurationMins
            )},
            credits: wire.credits.map { CreditsSnapshot(
                hasCredits: $0.hasCredits,
                unlimited: $0.unlimited,
                balance: $0.balance
            )},
            limitId: wire.limitId,
            limitName: wire.limitName
        )
    }

    func applyDaemonStreaming(
        chatId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    ) {
        guard let id = UUID(uuidString: chatId),
              let msgId = UUID(uuidString: messageId),
              let cIdx = chats.firstIndex(where: { $0.id == id })
        else { return }
        // Same reasoning as `appendDaemonMessage`: the daemon-supplied
        // content replaces ours wholesale, so any pending tick of
        // local deltas would double up on top of the canonical body.
        dropPendingAssistantText(chatId: id)
        if let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == msgId }) {
            chats[cIdx].messages[mIdx].content = content
            chats[cIdx].messages[mIdx].reasoningText = reasoningText
            chats[cIdx].messages[mIdx].streamingFinished = finished
        } else {
            chats[cIdx].messages.append(ChatMessage(
                id: msgId,
                role: .assistant,
                content: content,
                reasoningText: reasoningText,
                streamingFinished: finished
            ))
        }
        chats[cIdx].hasActiveTurn = !finished
    }

    /// Apply a server-delivered page of older messages. Prepended to
    /// the chat's transcript, deduped by id. Updates the pagination
    /// cursor + clears the in-flight flag so the scroll-up sentinel
    /// can fire again. Mirrors `BridgeStore.applyMessagesPage`.
    func applyDaemonMessagesPage(chatId: String, messages: [WireMessage], hasMore: Bool) {
        guard let id = UUID(uuidString: chatId) else { return }
        var pag = messagesPaginationByChat[id] ?? ChatPagination(oldestKnownId: nil, hasMore: hasMore, loadingOlder: false)
        pag.loadingOlder = false
        pag.hasMore = hasMore
        messagesPaginationByChat[id] = pag
        guard !messages.isEmpty else { return }
        let existing = cachedWireMessagesByChat[chatId] ?? []
        let existingWireIds = Set(existing.map(\.id))
        let prependWire = messages.filter { !existingWireIds.contains($0.id) }
        guard !prependWire.isEmpty else { return }
        cachedWireMessagesByChat[chatId] = prependWire + existing
        mutateChat(id: id) { c in
            let existingChatIds = Set(c.messages.map(\.id))
            let toInsert = prependWire.compactMap { chatMessage(from: $0) }
                .filter { !existingChatIds.contains($0.id) }
            guard !toInsert.isEmpty else { return }
            c.messages.insert(contentsOf: toInsert, at: 0)
        }
        messagesPaginationByChat[id]?.oldestKnownId = cachedWireMessagesByChat[chatId]?.first?.id
    }

    /// Ask the daemon for the next page of older messages if we have a
    /// cursor, the daemon told us there are more, and we don't already
    /// have a page in flight. Called by the chat transcript's scroll-
    /// up sentinel; the guards short-circuit cheaply because the
    /// callback can fire on every onScrollGeometryChange tick.
    func requestOlderIfNeeded(chatId: UUID) {
        guard let pag = messagesPaginationByChat[chatId],
              pag.hasMore,
              !pag.loadingOlder,
              let cursor = pag.oldestKnownId else { return }
        messagesPaginationByChat[chatId]?.loadingOlder = true
        guard let client = daemonBridgeClient,
              client.loadOlderMessages(chatId: chatId, beforeMessageId: cursor)
        else {
            // No daemon attached: clear the flag so a future sentinel
            // firing can retry once the bridge connects.
            messagesPaginationByChat[chatId]?.loadingOlder = false
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self,
                  var pag = self.messagesPaginationByChat[chatId],
                  pag.loadingOlder,
                  pag.oldestKnownId == cursor
            else { return }
            pag.loadingOlder = false
            self.messagesPaginationByChat[chatId] = pag
        }
    }

    /// Restore the on-disk snapshot if one exists. Called once at
    /// startup right after `applySnapshotForFirstPaint()` so the chat
    /// detail renders the last-known transcript immediately while the
    /// daemon's `messagesSnapshot` is still in flight. Bridge frames
    /// shortly overwrite this with the canonical truth.
    func loadCachedSnapshot() {
        guard let payload = SnapshotCache.load() else { return }
        cachedWireChats = payload.chats
        cachedWireMessagesByChat = payload.messagesBySession
        if chats.isEmpty && archivedChats.isEmpty {
            // Fresh install / no SQLite: populate `chats` from the
            // snapshot. No animation; the user is staring at a launch
            // screen, not at a list mutating under their cursor.
            let active: [Chat] = payload.chats.compactMap { wire in
                guard !wire.isArchived else { return nil }
                var c = chat(from: wire, old: nil)
                if let cached = payload.messagesBySession[wire.id] {
                    c.messages = cached.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
                return c
            }
            let arch: [Chat] = payload.chats.compactMap { wire in
                guard wire.isArchived else { return nil }
                var c = chat(from: wire, old: nil)
                if let cached = payload.messagesBySession[wire.id] {
                    c.messages = cached.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
                return c
            }
            chats = active
            archivedChats = arch
        } else {
            // SQLite already populated `chats`. Just hydrate messages
            // for those that match a snapshot entry; leave the rest
            // alone so the daemon can fill them in or the rollout
            // fallback can.
            for (chatIdString, msgs) in payload.messagesBySession {
                guard let id = UUID(uuidString: chatIdString) else { continue }
                mutateChat(id: id) { c in
                    guard c.messages.isEmpty else { return }
                    c.messages = msgs.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
            }
        }
        // Seed pagination cursors so a scroll-up sentinel firing
        // before the daemon (re)delivers `messagesSnapshot` still has
        // an `oldestKnownId` to send. `hasMore` defaults to `false`
        // because we don't know yet; the daemon will refresh on
        // `messagesSnapshot`.
        for (chatIdString, msgs) in payload.messagesBySession {
            guard let id = UUID(uuidString: chatIdString) else { continue }
            messagesPaginationByChat[id] = ChatPagination(
                oldestKnownId: msgs.first?.id,
                hasMore: false,
                loadingOlder: false
            )
        }
    }

    /// Schedule a persist of the wire mirror after 500ms of quiet.
    /// Streaming chunks and rapid chat updates collapse into a single
    /// write; the IO runs on a background queue so the main thread is
    /// never blocked. Safe to call from any of the bridge inbound
    /// paths after a mutation.
    func persistSnapshotDebounced() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let chatsSnap = self.cachedWireChats
            let messagesSnap = self.cachedWireMessagesByChat
            await Task.detached(priority: .background) {
                SnapshotCache.save(chats: chatsSnap, messages: messagesSnap)
            }.value
        }
    }

    private func chat(from wire: WireChat, old: Chat?) -> Chat {
        // Wire chats from the daemon don't share UUIDs with our
        // persisted snapshot, so `old` is usually nil and the chat
        // arrives without `clawixThreadId` / `projectId`. The new
        // `wire.threadId` field (and the daemon's pin-aware
        // `wire.isPinned`) lets us reconstruct both: stamp the thread
        // id, then resolve the project via the same `rootPath`
        // logic `chatFromThread` uses for runtime-sourced summaries.
        let threadId = wire.threadId ?? old?.clawixThreadId
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let resolvedRoot = rootPath(
            threadId: threadId,
            cwd: wire.cwd ?? old?.cwd,
            projectByPath: projectByPath
        )
        let resolvedProjectId: UUID? = resolvedRoot.flatMap { projectByPath[$0]?.id } ?? old?.projectId
        return Chat(
            id: old?.id ?? UUID(uuidString: wire.id) ?? UUID(),
            title: wire.title,
            messages: old?.messages ?? [],
            createdAt: wire.lastMessageAt ?? wire.createdAt,
            clawixThreadId: threadId,
            rolloutPath: old?.rolloutPath,
            historyHydrated: old?.historyHydrated ?? false,
            hasActiveTurn: wire.hasActiveTurn,
            projectId: resolvedProjectId,
            isArchived: wire.isArchived,
            isPinned: wire.isPinned,
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: wire.cwd,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: wire.branch ?? old?.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles,
            forkedFromChatId: old?.forkedFromChatId,
            forkedFromTitle: old?.forkedFromTitle,
            forkBannerAfterMessageId: old?.forkBannerAfterMessageId,
            lastTurnInterrupted: wire.lastTurnInterrupted
        )
    }

    func chatMessage(from wire: WireMessage, fallbackingTo old: ChatMessage? = nil) -> ChatMessage? {
        guard let id = UUID(uuidString: wire.id) else { return nil }
        // Daemon-bridge mode: the helper's `RolloutHistory` reader does
        // not populate `timeline` / `workSummary` / `attachments` on the
        // wire. When this assistant message already exists locally with
        // those fields filled in (cache hydrate, earlier full-fidelity
        // rollout pass, live streaming via ClawixService), preserve them
        // so the chat row's "Worked for Xs" header and inline file/image
        // cards survive the snapshot replay.
        let timeline = wire.timeline.compactMap(timelineEntry(from:))
        let resolvedTimeline = timeline.isEmpty ? (old?.timeline ?? []) : timeline
        let resolvedSummary = wire.workSummary.map(workSummary(from:)) ?? old?.workSummary
        let resolvedAttachments = wire.attachments.isEmpty ? (old?.attachments ?? []) : wire.attachments
        return ChatMessage(
            id: id,
            role: wire.role == .user ? .user : .assistant,
            content: wire.content,
            reasoningText: wire.reasoningText,
            streamingFinished: wire.streamingFinished,
            isError: wire.isError,
            timestamp: wire.timestamp,
            workSummary: resolvedSummary,
            timeline: resolvedTimeline,
            audioRef: wire.audioRef,
            attachments: resolvedAttachments
        )
    }

    private func workSummary(from wire: WireWorkSummary) -> WorkSummary {
        WorkSummary(
            startedAt: wire.startedAt,
            endedAt: wire.endedAt,
            items: wire.items.compactMap(workItem(from:))
        )
    }

    private func timelineEntry(from wire: WireTimelineEntry) -> AssistantTimelineEntry? {
        switch wire {
        case .reasoning(let id, let text):
            return UUID(uuidString: id).map { .reasoning(id: $0, text: text) }
        case .message(let id, let text):
            return UUID(uuidString: id).map { .message(id: $0, text: text) }
        case .tools(let id, let items):
            guard let uuid = UUID(uuidString: id) else { return nil }
            return .tools(id: uuid, items: items.compactMap(workItem(from:)))
        }
    }

    private func workItem(from wire: WireWorkItem) -> WorkItem? {
        let status: WorkItemStatus
        switch wire.status {
        case .inProgress: status = .inProgress
        case .completed: status = .completed
        case .failed: status = .failed
        }
        let kind: WorkItemKind
        switch wire.kind {
        case "command":
            kind = .command(text: wire.commandText, actions: (wire.commandActions ?? []).map { CommandActionKind(rawValue: $0) ?? .unknown })
        case "fileChange":
            kind = .fileChange(paths: wire.paths ?? [])
        case "webSearch":
            kind = .webSearch
        case "mcpTool":
            // The browser-use plugin reports through the synthetic
            // `node_repl` MCP server. The daemon doesn't yet ship a
            // dedicated wire kind, so we relabel here so the live
            // streaming pill reads `Used Node Repl` instead of the raw
            // server/tool dump. Once we reload the chat from the rollout,
            // RolloutReader's classifier upgrades the browser calls to
            // `.jsCall(.browser)` so the timeline picks up the proper
            // `Used the browser` pill.
            let server = wire.mcpServer ?? ""
            let tool = wire.mcpTool ?? ""
            if server == "node_repl" {
                kind = tool == "js_reset"
                    ? .jsReset
                    : .jsCall(title: nil, flavor: .repl)
            } else {
                kind = .mcpTool(server: server, tool: tool)
            }
        case "dynamicTool":
            kind = .dynamicTool(name: wire.dynamicToolName ?? "")
        case "imageGeneration":
            kind = .imageGeneration
        case "imageView":
            kind = .imageView
        default:
            return nil
        }
        return WorkItem(
            id: wire.id,
            kind: kind,
            status: status,
            generatedImagePath: wire.generatedImagePath
        )
    }
}
