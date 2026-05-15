import Foundation

extension AppState {
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard let deepLink = ClawixDeepLink.parse(url) else { return false }
        switch deepLink {
        case .session(let token):
            return openSessionDeepLink(token)
        case .authCallback:
            return true
        }
    }

    @discardableResult
    func openSessionDeepLink(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let id = UUID(uuidString: trimmed),
           let chat = chat(byId: id) {
            currentRoute = .chat(chat.id)
            ensureSelectedChat()
            return true
        }

        let folded = trimmed.lowercased()
        if let chat = (chats + archivedChats).first(where: { $0.clawixThreadId?.lowercased() == folded }) {
            currentRoute = .chat(chat.id)
            ensureSelectedChat()
            return true
        }

        if let chat = restoreSnapshotChat(matching: trimmed) {
            currentRoute = .chat(chat.id)
            ensureSelectedChat()
            return true
        }

        return false
    }

    private func restoreSnapshotChat(matching token: String) -> Chat? {
        let row = snapshotRepo.load(chatUuid: token) ?? snapshotRepo.load(threadId: token)
        guard let row, let id = UUID(uuidString: row.chatUuid) else { return nil }

        if let chat = chat(byId: id) { return chat }
        if let chat = (chats + archivedChats).first(where: { $0.clawixThreadId?.caseInsensitiveCompare(row.threadId) == .orderedSame }) {
            return chat
        }

        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let archived = row.archived != 0
        let chat = Chat(
            id: id,
            title: row.title,
            messages: [],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
            clawixThreadId: row.threadId,
            rolloutPath: nil,
            historyHydrated: false,
            hasActiveTurn: false,
            projectId: row.projectPath.flatMap { projectByPath[$0]?.id },
            isArchived: archived,
            isPinned: !archived && pinsRepo.isPinned(row.threadId),
            hasUnreadCompletion: false,
            cwd: row.cwd,
            hasGitRepo: false,
            branch: nil,
            availableBranches: [],
            uncommittedFiles: nil
        )

        if archived {
            archivedChats.insert(chat, at: 0)
        } else {
            chats.insert(chat, at: 0)
        }
        return chat
    }

    func handleNewChatIntent() {
        currentRoute = .home
        composer.text = ""
    }

    func handleSendMessageIntent(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentRoute = .home
        composer.text = trimmed
        // Defer the actual submit so SwiftUI has settled the route
        // change before sendMessage() reads it.
        DispatchQueue.main.async { [weak self] in
            self?.sendMessage()
        }
    }

    func handleAppDidBecomeActive() {
        guard SyncSettings.autoReloadOnFocus else { return }
        guard let clawix, case .ready = clawix.status else { return }
        if let last = lastAutoReloadAt, Date().timeIntervalSince(last) < 1.0 { return }
        lastAutoReloadAt = Date()
        Task { @MainActor in
            await self.loadThreadsFromRuntime()
        }
    }
}
