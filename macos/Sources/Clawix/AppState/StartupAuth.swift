import Foundation

extension AppState {
    /// First-launch seed for the local_archives table. Pulls the runtime's
    /// archived list once and reconciles it into our DB so that
    /// `Chat.isArchived` (which now reads from the repo) matches the
    /// runtime's view from the very first sidebar render. Subsequent
    /// launches see the meta flag and skip.
    func seedArchivesIfNeeded() async {
        guard SyncSettings.syncArchiveWithCodex else { return }
        if metaRepo.boolValue(forKey: "archives_seeded") { return }
        guard let clawix, case .ready = clawix.status else { return }
        do {
            let archived = try await clawix.listThreads(
                archived: true,
                limit: 1000,
                useStateDbOnly: true
            )
            archivesRepo.bulkArchive(archived.map(\.id))
            metaRepo.setBool(true, forKey: "archives_seeded")
        } catch {
            // Non-fatal: next launch retries.
        }
    }

    // MARK: - Auth helpers

    /// Triggers runtime login. No-op if the binary couldn't be resolved.
    func startBackendLogin() {
        guard let binary = clawixBinary else {
            auth.refresh()
            return
        }
        auth.startLogin(binary: binary)
    }

    /// Triggers runtime logout. Optimistic: the auth coordinator clears
    /// its info immediately so the login screen appears without a flash.
    func performBackendLogout() {
        guard let binary = clawixBinary else {
            auth.refresh()
            return
        }
        auth.logout(binary: binary)
    }

    func loadMockData() {
        chats = []

        let now = Date()
        archivedChats = [
            Chat(title: "Refactor authentication module",
                 createdAt: now.addingTimeInterval(-60 * 60 * 26),
                 isArchived: true),
            Chat(title: "Investigate flaky CI on macOS",
                 createdAt: now.addingTimeInterval(-60 * 60 * 24 * 3),
                 isArchived: true),
            Chat(title: "Spike: streaming JSON parser",
                 createdAt: now.addingTimeInterval(-60 * 60 * 24 * 8),
                 isArchived: true),
            Chat(title: "Cleanup unused fixtures",
                 createdAt: now.addingTimeInterval(-60 * 60 * 24 * 17),
                 isArchived: true)
        ]

        plugins = [
            Plugin(id: UUID(), name: "GitHub",
                   description: "Integration with GitHub repositories",
                   isEnabled: true, iconName: "globe"),
            Plugin(id: UUID(), name: "Terminal",
                   description: "Access to the system terminal",
                   isEnabled: true, iconName: "terminal"),
            Plugin(id: UUID(), name: "Web search",
                   description: "Search the web for information",
                   isEnabled: false, iconName: "magnifyingglass.circle")
        ]

        automations = [
            Automation(id: UUID(), name: "PR review",
                       description: "Review pull requests automatically",
                       isEnabled: true, trigger: "When a PR is opened"),
            Automation(id: UUID(), name: "Auto-run tests",
                       description: "Run tests on every save",
                       isEnabled: false, trigger: "On file save")
        ]

        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        selectedProject = nil

        pinnedItems = []
    }
}
