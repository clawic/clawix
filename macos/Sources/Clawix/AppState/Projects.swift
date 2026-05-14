import Foundation

extension AppState {
    // MARK: - Pinning

    func togglePin(chatId: UUID) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        // Explicit array reassignment ensures @Published always fires
        // (subscript-mutation alone occasionally misses observers).
        var copy = chats
        copy[idx].isPinned.toggle()
        chats = copy
        if copy[idx].isPinned {
            if !pinnedOrder.contains(chatId) {
                pinnedOrder.append(chatId)
            }
            if let threadId = copy[idx].clawixThreadId {
                pinsRepo.setPinned(threadId, atEnd: true)
                Task { @MainActor in
                    try? await ClawJSSessionsClient.local().updateSession(id: threadId, patch: ["pinned": .bool(true)])
                }
            }
        } else {
            pinnedOrder.removeAll { $0 == chatId }
            if let threadId = copy[idx].clawixThreadId {
                pinsRepo.unpin(threadId)
                Task { @MainActor in
                    try? await ClawJSSessionsClient.local().updateSession(id: threadId, patch: ["pinned": .bool(false)])
                }
            }
        }
    }

    /// Move a pinned chat to a new slot inside the pinned list. Pass the
    /// chat the moved row should land *before*, or `nil` to drop at the
    /// end. If the chat is not currently pinned (e.g. dragged in from a
    /// project) it is pinned first. Computing the destination relative
    /// to a sibling chat avoids the index-shift bug when the dragged row
    /// is above its target.
    func reorderPinned(chatId: UUID, beforeChatId: UUID?) {
        guard chatId != beforeChatId,
              let chatIdx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        if !copy[chatIdx].isPinned {
            copy[chatIdx].isPinned = true
            chats = copy
        }
        var order = pinnedOrder
        order.removeAll { $0 == chatId }
        if let beforeChatId, let idx = order.firstIndex(of: beforeChatId) {
            order.insert(chatId, at: idx)
        } else {
            order.append(chatId)
        }
        pinnedOrder = order
        let chatsById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        let orderedThreadIds = order.compactMap { chatsById[$0]?.clawixThreadId }
        pinsRepo.setOrder(orderedThreadIds)
    }

    /// Move a project to a new slot in the manual ordering used by the
    /// sidebar's "Custom" sort mode. Pass the project the moved row should
    /// land *before*, or `nil` to drop at the end. Computing relative to a
    /// sibling avoids the index-shift bug when the dragged row is above
    /// its target. Persisted via `ProjectOrdersRepository`.
    func reorderProject(projectId: UUID, beforeProjectId: UUID?) {
        guard projectId != beforeProjectId else { return }
        // Build a complete ordering of the currently-visible projects so
        // the persisted list stays a superset of the live one. Projects
        // not yet in `manualProjectOrder` keep their natural order from
        // `projects` (creation/insertion order from `mergedProjects`).
        var order = manualProjectOrder
        let knownIds = Set(order)
        let livedIds = Set(projects.map(\.id))
        // Drop entries for projects that no longer exist (deleted /
        // hidden Codex roots) so the persisted list never grows
        // unbounded across launches.
        order.removeAll { !livedIds.contains($0) }
        // Append projects we've never positioned manually, in natural
        // order, so we have a position for every live project.
        for project in projects where !knownIds.contains(project.id) {
            order.append(project.id)
        }
        order.removeAll { $0 == projectId }
        if let beforeProjectId, let idx = order.firstIndex(of: beforeProjectId) {
            order.insert(projectId, at: idx)
        } else {
            order.append(projectId)
        }
        manualProjectOrder = order
        projectOrdersRepo.setOrder(order)
    }

    // MARK: - Project assignment

    func assignChat(chatId: UUID, toProject projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        copy[idx].projectId = projectId
        chats = copy
        updateProjectOverride(for: copy[idx])
    }

    /// Drag-and-drop helper: drop a chat onto a project. Reassigns it and
    /// unpins it so it visibly leaves the pinned section and lands inside
    /// that project's body. Pass `nil` to drop into the projectless bucket.
    func moveChatToProject(chatId: UUID, projectId: UUID?) {
        guard let idx = chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = chats
        copy[idx].projectId = projectId
        let wasPinned = copy[idx].isPinned
        if wasPinned {
            copy[idx].isPinned = false
            pinnedOrder.removeAll { $0 == chatId }
        }
        chats = copy
        if wasPinned, let threadId = copy[idx].clawixThreadId {
            pinsRepo.unpin(threadId)
        }
        updateProjectOverride(for: copy[idx])
    }

    private func updateProjectOverride(for chat: Chat) {
        guard let threadId = chat.clawixThreadId else { return }
        if let projectId = chat.projectId,
           let project = projects.first(where: { $0.id == projectId }) {
            chatProjectsRepo.setOverride(threadId: threadId, projectPath: project.path)
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().updateSession(
                    id: threadId,
                    patch: ["projectPath": .string(project.path)]
                )
            }
        } else {
            chatProjectsRepo.clearOverride(threadId: threadId)
            chatProjectsRepo.markProjectless(threadId)
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().updateSession(
                    id: threadId,
                    patch: ["projectPath": .null]
                )
            }
        }
    }

    // MARK: - Project CRUD

    @discardableResult
    func createProject(name: String, path: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = (path as NSString).expandingTildeInPath
        let project = Project(
            id: StableProjectID.uuid(for: normalizedPath.isEmpty ? UUID().uuidString : normalizedPath),
            name: trimmed.isEmpty ? "Untitled" : trimmed,
            path: normalizedPath
        )
        projects.append(project)
        if !project.path.isEmpty {
            projectsRepo.upsert(project)
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().createProject(.init(
                    displayName: project.name,
                    path: project.path,
                    hidden: false,
                    archived: false,
                    sortRank: nil
                ))
            }
        }
        return project
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        if selectedProject?.id == project.id { selectedProject = project }
        if !project.path.isEmpty {
            projectsRepo.upsert(project)
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().createProject(.init(
                    displayName: project.name,
                    path: project.path,
                    hidden: false,
                    archived: false,
                    sortRank: nil
                ))
            }
        }
    }

    /// Removes a project. Chats previously assigned to it become projectless.
    func deleteProject(_ projectId: UUID) {
        projects.removeAll { $0.id == projectId }
        for idx in chats.indices where chats[idx].projectId == projectId {
            chats[idx].projectId = nil
            updateProjectOverride(for: chats[idx])
        }
        if selectedProject?.id == projectId { selectedProject = nil }
        projectsRepo.delete(id: projectId)
        Task { @MainActor in
            let client = ClawJSSessionsClient.local()
            guard let projects = try? await client.listProjects(),
                  let project = projects.first(where: { StableProjectID.uuid(for: $0.path) == projectId })
            else { return }
            try? await client.deleteProject(id: project.id)
        }
    }

    func renameProject(id: UUID, newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[idx].name = trimmed
        let projectPath = projects[idx].path
        if selectedProject?.id == id { selectedProject = projects[idx] }
        projectsRepo.rename(id: id, to: trimmed)
        if !projectPath.isEmpty {
            Task { @MainActor in
                try? await ClawJSSessionsClient.local().createProject(.init(
                    displayName: trimmed,
                    path: projectPath,
                    hidden: false,
                    archived: false,
                    sortRank: nil
                ))
            }
        }
    }

    /// Convenience: start a new chat scoped to a specific project.
    /// Selects the project in the composer pill and routes Home so the
    /// next message creates a chat associated with it.
    func startNewChat(in project: Project) {
        selectedProject = project
        currentRoute = .home
    }
}
