import Foundation

extension AppState {
    // MARK: - Branch switching (footer pill)

    /// Update the chat's current branch in-memory. The app does not
    /// shell out to `git checkout`; it only reflects the user's choice in
    /// the chrome.
    func switchBranch(chatId: UUID, to branch: String) {
        guard FeatureFlags.shared.isVisible(.git) else { return }
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].branch = branch
        if !chats[idx].availableBranches.contains(branch) {
            chats[idx].availableBranches.insert(branch, at: 0)
        }
        chats[idx].uncommittedFiles = nil
    }

    /// Append a new branch to the chat's known list and switch to it.
    /// Mirrors the "Create and switch to a new branch..." flow.
    func createBranch(chatId: UUID, name: String) {
        guard FeatureFlags.shared.isVisible(.git) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        if !chats[idx].availableBranches.contains(trimmed) {
            chats[idx].availableBranches.insert(trimmed, at: 0)
        }
        chats[idx].branch = trimmed
        chats[idx].uncommittedFiles = nil
    }

    func updateTokenUsage(chatId: UUID, usage: ThreadTokenUsage) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].contextUsage = ContextUsage(
            usedTokens: usage.last.totalTokens,
            contextWindow: usage.modelContextWindow
        )
    }

    /// Context usage for whichever chat the user is currently looking at.
    /// nil when not in a chat route or before the first token-usage event.
    var currentContextUsage: ContextUsage? {
        guard case let .chat(id) = currentRoute,
              let chat = chats.first(where: { $0.id == id })
        else { return nil }
        return chat.contextUsage
    }

    // MARK: - Work summary updates (per assistant message)

    /// Initialize `workSummary` on the given assistant message if it
    /// doesn't have one yet. No-op if the start time is already set.
    func beginWorkSummary(chatId: UUID, messageId: UUID, startedAt: Date) {
        mutateMessage(chatId: chatId, messageId: messageId) { msg in
            if msg.workSummary == nil {
                msg.workSummary = WorkSummary(startedAt: startedAt, endedAt: nil, items: [])
            }
        }
    }

    /// Insert or update one tool item (commandExecution, fileChange, …)
    /// on the given assistant message. Lazily creates the WorkSummary if
    /// the start event was missed.
    func upsertWorkItem(chatId: UUID, messageId: UUID, item: WorkItem) {
        // Drain any pending agent-message deltas FIRST so any text the
        // model emitted before this tool call lands in the timeline ahead
        // of the new `.tools` entry. Otherwise the buffered preamble
        // (flushed on the next runloop tick) would render after the tool.
        flushPendingAssistantTextDeltas(chatId: chatId)
        mutateMessage(chatId: chatId, messageId: messageId) { msg in
            if msg.workSummary == nil {
                msg.workSummary = WorkSummary(startedAt: Date(), endedAt: nil, items: [])
            }
            if let i = msg.workSummary!.items.firstIndex(where: { $0.id == item.id }) {
                msg.workSummary!.items[i] = item
            } else {
                msg.workSummary!.items.append(item)
            }

            // Mirror the upsert into the chronological timeline so the
            // chat row can render command rows interleaved with reasoning.
            // First try to update an existing entry that already holds
            // this item id (handles started→completed transitions).
            for tIdx in msg.timeline.indices {
                if case .tools(let gid, var items) = msg.timeline[tIdx],
                   let itemIdx = items.firstIndex(where: { $0.id == item.id }) {
                    items[itemIdx] = item
                    msg.timeline[tIdx] = .tools(id: gid, items: items)
                    return
                }
            }
            // New item: extend the trailing tools group only if the last
            // item there is the same family (commands merge, fileChanges
            // merge, everything else opens a fresh row). Matches the
            // rollout reader so live-streamed chats render identically to
            // hydrated history.
            let canMerge: Bool = {
                guard case .tools(_, let items) = msg.timeline.last,
                      let last = items.last else { return false }
                return TimelineFamily.from(last.kind).matches(item.kind)
            }()
            if canMerge, case .tools(let gid, let items) = msg.timeline.last {
                msg.timeline[msg.timeline.count - 1] =
                    .tools(id: gid, items: items + [item])
            } else {
                msg.timeline.append(.tools(id: UUID(), items: [item]))
            }
        }
    }

    /// Mark the WorkSummary as finished (turn/completed). Records the end
    /// time so the live counter freezes.
    func completeWorkSummary(chatId: UUID, messageId: UUID, endedAt: Date) {
        mutateMessage(chatId: chatId, messageId: messageId) { msg in
            if msg.workSummary == nil {
                msg.workSummary = WorkSummary(startedAt: endedAt, endedAt: endedAt, items: [])
            } else {
                msg.workSummary!.endedAt = endedAt
            }
        }
    }

    private func mutateMessage(chatId: UUID, messageId: UUID, _ body: (inout ChatMessage) -> Void) {
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        body(&chats[cIdx].messages[mIdx])
    }

    /// Edit a previous user message and restart the conversation from
    /// that point. Mirrors how Clawix CLI's `thread/rollback` works:
    /// every turn after (and including) this user message is dropped
    /// both locally and on the backend thread, then a fresh `turn/start`
    /// is issued with the new prompt.
    func editUserMessage(chatId: UUID, messageId: UUID, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let cIdx = chats.firstIndex(where: { $0.id == chatId }),
              let mIdx = chats[cIdx].messages.firstIndex(where: { $0.id == messageId }),
              chats[cIdx].messages[mIdx].role == .user
        else { return }

        // A "turn" starts on each user message and runs until the next
        // user message. Number of turns to drop on the backend equals
        // the count of user messages from this index to the end.
        let tail = chats[cIdx].messages[mIdx...]
        let numTurns = tail.reduce(into: 0) { acc, msg in
            if msg.role == .user { acc += 1 }
        }

        // Truncate locally and re-append the edited user bubble so the
        // UI matches the new conversation state immediately. Any text
        // deltas still buffered for this chat belong to the assistant
        // turn we're about to drop, so discard them.
        dropPendingAssistantText(chatId: chatId)
        chats[cIdx].messages.removeSubrange(mIdx...)
        let edited = ChatMessage(role: .user, content: trimmed, timestamp: Date())
        chats[cIdx].messages.append(edited)

        if let clawix {
            Task { @MainActor in
                await clawix.editAndResubmit(
                    chatId: chatId,
                    numTurnsToDrop: numTurns,
                    newText: trimmed
                )
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    /// Fork an existing chat into a new sibling conversation. Mirrors
    /// Codex Desktop's "Forked from conversation" affordance: the new
    /// chat starts as a verbatim copy of the parent's transcript up to
    /// (and including) the chosen anchor, plus a banner that links back
    /// to the parent. When the runtime is available we also call
    /// `thread/fork` so the server-side rollout carries the same prefix
    /// and the next turn resumes with full context.
    @discardableResult
    func forkConversation(
        chatId: UUID,
        atMessageId anchorMessageId: UUID? = nil,
        sourceSnapshot: Chat? = nil
    ) -> UUID? {
        guard let srcIdx = chats.firstIndex(where: { $0.id == chatId }) else { return nil }
        var source = chats[srcIdx]
        let snapshotMessages = sourceSnapshot.flatMap { $0.id == chatId ? $0.messages : nil } ?? []
        if source.messages.isEmpty, !snapshotMessages.isEmpty {
            source.messages = snapshotMessages
            source.historyHydrated = sourceSnapshot?.historyHydrated ?? source.historyHydrated
            if source.rolloutPath == nil {
                source.rolloutPath = sourceSnapshot?.rolloutPath
            }
        }
        let sourceMessages = forkableMessages(for: source, fallbackMessages: snapshotMessages)
        guard !sourceMessages.isEmpty else { return nil }

        let cutIndex: Int
        if let anchorMessageId,
           let mIdx = sourceMessages.firstIndex(where: { $0.id == anchorMessageId }) {
            cutIndex = mIdx
        } else {
            cutIndex = sourceMessages.count - 1
        }
        guard cutIndex >= 0 else { return nil }

        // Deep-copy each message with a fresh UUID so the transcript in
        // the forked chat is decoupled from the parent. Streaming state
        // is reset because the copied turns are by definition completed
        // history at fork time.
        let copied: [ChatMessage] = sourceMessages[0...cutIndex].map { msg in
            ChatMessage(
                id: UUID(),
                role: msg.role,
                content: msg.content,
                reasoningText: msg.reasoningText,
                streamingFinished: true,
                isError: msg.isError,
                timestamp: msg.timestamp,
                workSummary: msg.workSummary,
                timeline: msg.timeline,
                streamCheckpoints: msg.streamCheckpoints,
                streamPendingTail: "",
                reasoningCheckpoints: msg.reasoningCheckpoints,
                reasoningPendingTails: [:],
                audioRef: msg.audioRef,
                attachments: msg.attachments
            )
        }
        guard let bannerAfterId = copied.last?.id else { return nil }

        let newChat = Chat(
            id: UUID(),
            title: source.title,
            messages: copied,
            createdAt: Date(),
            clawixThreadId: nil,
            rolloutPath: nil,
            historyHydrated: true,
            hasActiveTurn: false,
            projectId: source.projectId,
            isArchived: false,
            isPinned: false,
            hasUnreadCompletion: false,
            cwd: source.cwd,
            hasGitRepo: source.hasGitRepo,
            branch: source.branch,
            availableBranches: source.availableBranches,
            uncommittedFiles: source.uncommittedFiles,
            forkedFromChatId: source.id,
            forkedFromTitle: source.title,
            forkBannerAfterMessageId: bannerAfterId
        )

        chats.insert(newChat, at: 0)
        currentRoute = .chat(newChat.id)
        requestComposerFocus()

        // Fire the runtime-side fork in the background so the new chat
        // resumes with the parent's full context the next time the user
        // sends a message. Failures are non-fatal — the forked chat
        // still works, it just starts a fresh thread on first send.
        if let parentThreadId = source.clawixThreadId,
           let clawix,
           case .ready = clawix.status {
            Task { @MainActor in
                do {
                    _ = try await clawix.forkThread(
                        parentThreadId: parentThreadId,
                        newChatId: newChat.id
                    )
                } catch {
                    // Swallow: the chat is usable even without the
                    // server-side fork. A future send will lazily
                    // create a fresh thread via ensureThread.
                }
            }
        }

        return newChat.id
    }

    private func forkableMessages(for source: Chat, fallbackMessages: [ChatMessage] = []) -> [ChatMessage] {
        if !source.messages.isEmpty {
            return source.messages
        }

        if !fallbackMessages.isEmpty {
            return fallbackMessages
        }

        if let cached = cachedWireMessagesByChat[source.id.uuidString], !cached.isEmpty {
            return cached.compactMap { chatMessage(from: $0) }
        }

        if let path = source.rolloutPath {
            return rolloutChatMessages(from: RolloutReader.readTailWithStatus(path: path))
        }

        return []
    }

    /// Silent variant of `forkConversation` that powers "Open in side
    /// chat". Spawns a sibling conversation that inherits the parent's
    /// full context server-side (via `clawix.forkThread`), but starts
    /// with an empty visible transcript and no fork banner so the
    /// experience reads as a fresh chat. The new chat is pinned to the
    /// parent's right sidebar as a `SidebarItem.chat` tab and is
    /// flagged `isSideChat` so the main sidebar list filters it out.
    /// Returns the new chat's id.
    @discardableResult
    func openInSideChat(parentChatId: UUID) -> UUID? {
        guard let srcIdx = chats.firstIndex(where: { $0.id == parentChatId }) else { return nil }
        let source = chats[srcIdx]

        let newChat = Chat(
            id: UUID(),
            title: "",
            messages: [],
            createdAt: Date(),
            clawixThreadId: nil,
            rolloutPath: nil,
            historyHydrated: true,
            hasActiveTurn: false,
            projectId: source.projectId,
            isArchived: false,
            isPinned: false,
            hasUnreadCompletion: false,
            cwd: source.cwd,
            hasGitRepo: source.hasGitRepo,
            branch: source.branch,
            availableBranches: source.availableBranches,
            uncommittedFiles: source.uncommittedFiles,
            forkedFromChatId: source.id,
            forkedFromTitle: source.title,
            // No banner: the side-chat UX is "looks like a fresh chat,
            // but the daemon side carries the parent's context".
            forkBannerAfterMessageId: nil,
            isSideChat: true
        )
        chats.insert(newChat, at: 0)

        // Mount the side chat as a tab in the parent's right sidebar.
        // We mutate the parent's `ChatSidebarState` directly (rather
        // than going through `currentSidebar`) so this works whether or
        // not the user is currently viewing the parent route.
        var sidebar = chatSidebars[parentChatId] ?? .empty
        sidebar.items.append(.chat(.init(id: newChat.id)))
        sidebar.activeItemId = newChat.id
        sidebar.isOpen = true
        chatSidebars[parentChatId] = sidebar
        persistChatSidebars()

        // Mirror the runtime fork so the side chat's first prompt
        // resumes inside the parent's full thread context. Failures
        // are non-fatal — if the runtime is down the side chat still
        // works as a fresh thread.
        if let parentThreadId = source.clawixThreadId,
           let clawix,
           case .ready = clawix.status {
            Task { @MainActor in
                do {
                    _ = try await clawix.forkThread(
                        parentThreadId: parentThreadId,
                        newChatId: newChat.id
                    )
                } catch {
                    // Swallow: see forkConversation for rationale.
                }
            }
        }

        return newChat.id
    }

    /// Send variant for a side-chat composer. Mirrors `sendMessage()`
    /// but drives an explicit chat id and an explicit, view-owned
    /// composer state — necessary because the side chat lives in the
    /// right sidebar and uses its own `ComposerState`, independent of
    /// `appState.composer` (the global one tied to the main route).
    func sendMessage(forChatId chatId: UUID, composer: ComposerState) {
        let trimmed = composer.text.trimmingCharacters(in: .whitespaces)
        let attachments = composer.attachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let mentions = attachments.map { "@\($0.url.path)" }.joined(separator: " ")
        let combined: String
        if trimmed.isEmpty {
            combined = mentions
        } else if mentions.isEmpty {
            combined = trimmed
        } else {
            combined = mentions + "\n\n" + trimmed
        }

        let userMsg = ChatMessage(role: .user, content: combined, timestamp: Date())
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[idx].messages.append(userMsg)
        chats[idx].lastTurnInterrupted = false
        // Side chats start with an empty title so the tab pill reads
        // "Side chat" until the user types. On the first message we
        // promote the prompt to the title — same convention as the
        // home-route new-chat branch in `sendMessage()`.
        if chats[idx].title.isEmpty {
            let titleSeed = trimmed.isEmpty
                ? (attachments.first?.filename ?? "Side chat")
                : trimmed
            chats[idx].title = String(titleSeed.prefix(40))
        }

        composer.text = ""
        composer.attachments = []

        if let daemonBridgeClient {
            // Same as `sendMessage()`: keep the BridgeBus subscription
            // explicit because we don't switch `currentRoute` here
            // (the user is still on the parent chat route).
            trackOptimisticUserMessage(chatId: chatId, messageId: userMsg.id)
            daemonBridgeClient.openSession(chatId)
            daemonBridgeClient.sendPrompt(
                chatId: chatId,
                text: combined,
                attachments: wireAttachments(from: attachments)
            )
        } else if let clawix {
            Task { @MainActor in
                await clawix.sendUserMessage(chatId: chatId, text: combined)
                self.clawixBackendStatus = clawix.status
            }
        }
    }

    func appendErrorBubble(chatId: UUID, message: String) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        let bubble = ChatMessage(
            role: .assistant,
            content: "Error: \(message)",
            isError: true,
            timestamp: Date()
        )
        chats[idx].messages.append(bubble)
    }

    // MARK: - Titles

    /// Resolve the visible title for a session id. Layered sources:
    /// titlesRepo (manual user renames + generated overrides + runtime
    /// session index) > truncated first message > localized fallback.
    /// Manual renames win over runtime/generated through the latest
    /// updated_at fold inside the repository.
    private func resolveTitle(forSessionId id: String, firstMessage: String) -> String {
        if let stored = titlesRepo.title(for: id) {
            return stored
        }
        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Conversation" }
        return String(trimmed.prefix(60))
    }

    /// Persist a freshly-generated title and refresh the matching chat
    /// row. Called from TitleGenerator on the main actor.
    func applyGeneratedTitle(sessionId: String, title: String) {
        applyRuntimeTitle(threadId: sessionId, title: title)
    }

    /// Hook called by ClawixService when a turn completes. If the chat
    /// still has a fallback-style title, fire title generation now that
    /// we have at least one user + one assistant message in memory.
    func maybeGenerateTitleAfterTurn(chatId: UUID) {
        titledChatIds.insert(chatId)
    }

    // MARK: - Rename

    func renameChat(chatId: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        guard let threadId = chats[idx].clawixThreadId else {
            var copy = chats
            copy[idx].title = trimmed
            chats = copy
            return
        }
        guard let clawix,
              case .ready = clawix.status else {
            appendErrorBubble(chatId: chatId, message: "Renaming requires the runtime to be available.")
            return
        }
        var copy = chats
        copy[idx].title = trimmed
        chats = copy
        titlesRepo.upsertManual(threadId: threadId, title: trimmed)

        guard SyncSettings.syncRenamesWithCodex else { return }
        Task { @MainActor in
            do {
                try await clawix.setThreadName(threadId: threadId, name: trimmed)
            } catch {
                self.appendErrorBubble(chatId: chatId, message: "Could not rename on the runtime: \(error)")
            }
        }
    }

    func applyRuntimeTitle(threadId: String, title: String) {
        guard let idx = chats.firstIndex(where: { $0.clawixThreadId == threadId }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = chats
        copy[idx].title = trimmed
        chats = copy
    }

    func archiveChat(chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        if let daemonBridgeClient {
            archiveLocally(chatIndex: idx)
            daemonBridgeClient.archiveChat(chatId)
            return
        }
        let threadId = chats[idx].clawixThreadId

        // Dummy / in-memory chat (no runtime thread): just move it locally so
        // the archived UI is exercisable without a backend.
        guard let threadId else {
            archiveLocally(chatIndex: idx)
            return
        }

        // Local DB is the source of truth. Mark archived first; the runtime
        // call is an optional mirror gated by SyncSettings.
        archivesRepo.archive(threadId)
        markThreadArchived(threadId: threadId, archived: true)
        Task { @MainActor in
            try? await ClawJSSessionsClient.local().updateSession(
                id: threadId,
                patch: ["archived": .bool(true), "pinned": .bool(false)]
            )
        }

        guard SyncSettings.syncArchiveWithCodex else { return }
        guard let clawix, case .ready = clawix.status else {
            // Sync requested but runtime not available: roll back local state
            // so the user is not silently divergent from Codex.
            archivesRepo.unarchive(threadId)
            markThreadArchived(threadId: threadId, archived: false)
            appendErrorBubble(chatId: chatId, message: "Archiving requires the runtime to be available.")
            return
        }
        Task { @MainActor in
            do {
                try await clawix.archiveThread(threadId: threadId)
            } catch {
                self.archivesRepo.unarchive(threadId)
                self.markThreadArchived(threadId: threadId, archived: false)
                self.appendErrorBubble(chatId: chatId, message: "Could not archive on the runtime: \(error)")
            }
        }
    }

    private func archiveLocally(chatIndex idx: Int) {
        var chat = chats[idx]
        chat.isArchived = true
        chat.isPinned = false
        chat.hasUnreadCompletion = false
        pinnedOrder.removeAll { $0 == chat.id }
        if case let .chat(id) = currentRoute, id == chat.id {
            currentRoute = .home
        }
        chats.remove(at: idx)
        archivedChats.insert(chat, at: 0)
        if archivedChats.count > Self.archivedSidebarLimit {
            archivedChats = Array(archivedChats.prefix(Self.archivedSidebarLimit))
        }
    }

    func markThreadArchived(threadId: String, archived: Bool) {
        if archived {
            guard let idx = chats.firstIndex(where: { $0.clawixThreadId == threadId }) else { return }
            var chat = chats[idx]
            chat.isArchived = true
            chat.isPinned = false
            chat.hasUnreadCompletion = false
            pinnedOrder.removeAll { $0 == chat.id }
            if case let .chat(id) = currentRoute, id == chat.id {
                currentRoute = .home
            }
            chats.remove(at: idx)
            archivedChats.removeAll { $0.clawixThreadId == threadId }
            archivedChats.insert(chat, at: 0)
            if archivedChats.count > Self.archivedSidebarLimit {
                archivedChats = Array(archivedChats.prefix(Self.archivedSidebarLimit))
            }
        } else {
            if let idx = archivedChats.firstIndex(where: { $0.clawixThreadId == threadId }) {
                var chat = archivedChats[idx]
                chat.isArchived = false
                archivedChats.remove(at: idx)
                if !chats.contains(where: { $0.clawixThreadId == threadId }) {
                    chats.insert(chat, at: 0)
                }
            } else if let idx = chats.firstIndex(where: { $0.clawixThreadId == threadId }) {
                chats[idx].isArchived = false
            }
        }
    }

    /// Lazy fetch of archived threads for the sidebar's archived section.
    /// First expand triggers the network round-trip; subsequent toggles
    /// reuse the cached list unless `force` is set.
    func loadArchivedChats(force: Bool = false) async {
        // Fixture / showcase mode is the source of truth for the
        // archived list — `applyThreads` already populates
        // `archivedChats` from the seeded JSON. Hitting the runtime here
        // would wipe that curated set with the (empty) real backend.
        if AgentThreadStore.fixtureThreads() != nil { return }
        guard let clawix, case .ready = clawix.status else { return }
        if archivedLoading { return }
        if archivedLoaded && !force { return }
        archivedLoading = true
        defer { archivedLoading = false }
        do {
            let threads = try await clawix.listThreads(
                archived: true,
                limit: Self.archivedSidebarLimit,
                useStateDbOnly: true
            )
            let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
            let oldByThread = Dictionary(uniqueKeysWithValues: archivedChats.compactMap { chat in
                chat.clawixThreadId.map { ($0, chat) }
            })
            archivedChats = threads
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { thread in
                    chatFromThread(thread,
                                   old: oldByThread[thread.id],
                                   projectByPath: projectByPath,
                                   pinnedSet: [])
                }
            archivedLoaded = true
        } catch {
            // Non-fatal: the section will render empty + retryable next expand.
            archivedLoaded = false
        }
    }

    func unarchiveChat(chatId: UUID) {
        guard let idx = archivedChats.firstIndex(where: { $0.id == chatId }) else { return }
        if let daemonBridgeClient {
            var moved = archivedChats[idx]
            moved.isArchived = false
            archivedChats.remove(at: idx)
            chats.insert(moved, at: 0)
            daemonBridgeClient.unarchiveChat(chatId)
            return
        }
        let threadId = archivedChats[idx].clawixThreadId
        var moved = archivedChats[idx]
        moved.isArchived = false
        archivedChats.remove(at: idx)

        // Dummy / in-memory chat: pop it back into the active list and stop.
        guard let threadId else {
            chats.insert(moved, at: 0)
            return
        }

        // Local DB is the source of truth.
        archivesRepo.unarchive(threadId)
        if !chats.contains(where: { $0.clawixThreadId == threadId }) {
            chats.insert(moved, at: 0)
        }
        Task { @MainActor in
            try? await ClawJSSessionsClient.local().updateSession(
                id: threadId,
                patch: ["archived": .bool(false), "sidebarVisible": .bool(true)]
            )
        }

        guard SyncSettings.syncArchiveWithCodex else { return }
        guard let clawix, case .ready = clawix.status else {
            // Sync requested but runtime not available: roll back local state.
            archivesRepo.archive(threadId)
            chats.removeAll { $0.id == chatId }
            moved.isArchived = true
            archivedChats.insert(moved, at: min(idx, archivedChats.count))
            return
        }
        Task { @MainActor in
            do {
                try await clawix.unarchiveThread(threadId: threadId)
                await self.loadThreadsFromRuntime()
            } catch {
                self.archivesRepo.archive(threadId)
                self.chats.removeAll { $0.id == chatId }
                moved.isArchived = true
                self.archivedChats.insert(moved, at: min(idx, self.archivedChats.count))
                self.appendErrorBubble(chatId: chatId, message: "Could not unarchive on the runtime: \(error)")
            }
        }
    }
}
