import Foundation

struct ClawJSAppStateSidebarSnapshot: Encodable, Sendable {
    let threadId: String
    let chatUuid: String
    let title: String
    let cwd: String?
    let projectPath: String?
    let updatedAt: String
    let archived: Bool
    let pinned: Bool
}

struct ClawJSAppStateSnapshot: Decodable, Sendable {
    struct Project: Decodable, Sendable {
        let id: String
        let name: String
        let path: String
        let sortOrder: Int64?
    }

    struct PinnedThread: Decodable, Sendable {
        let threadId: String
        let sortOrder: Int64
        let pinnedAt: String?
    }

    struct Title: Decodable, Sendable {
        let threadId: String
        let title: String
        let source: String
        let updatedAt: String?
    }

    struct Archive: Decodable, Sendable {
        let threadId: String
        let archivedAt: String?
    }

    struct Sidebar: Decodable, Sendable {
        let threadId: String
        let chatUuid: String
        let title: String
        let cwd: String?
        let projectPath: String?
        let updatedAt: String?
        let archived: Int
        let pinned: Int
    }

    struct TerminalTab: Decodable, Sendable {
        let id: String
        let title: String
        let cwd: String?
        let sortOrder: Int
        let createdAt: String?
        let metadata: [String: String]?
    }

    let projects: [Project]
    let pinnedThreads: [PinnedThread]
    let titles: [Title]
    let archives: [Archive]
    let sidebar: [Sidebar]
    let terminalTabs: [TerminalTab]
}

@MainActor
enum ClawJSAppStateClient {
    static func upsertProject(id: String, name: String, path: String, sortOrder: Int64? = nil) {
        var args = ["app-state", "project", "upsert", id, "--name", name, "--path", path, "--json"]
        if let sortOrder {
            args += ["--sort-order", String(sortOrder)]
        }
        runBestEffort(args)
    }

    static func deleteProject(id: String) {
        runBestEffort(["app-state", "project", "delete", id, "--json"])
    }

    static func setProjectOrder(_ projectIds: [String]) {
        guard let data = try? JSONEncoder().encode(projectIds),
              let json = String(data: data, encoding: .utf8) else { return }
        runBestEffort(["app-state", "project", "order", "--ids", json, "--json"])
    }

    static func upsertPin(threadId: String, sortOrder: Int64) {
        runBestEffort(["app-state", "pin", "upsert", threadId, "--sort-order", String(sortOrder), "--json"])
    }

    static func deletePin(threadId: String) {
        runBestEffort(["app-state", "pin", "delete", threadId, "--json"])
    }

    static func setPinOrder(_ threadIds: [String]) {
        guard let data = try? JSONEncoder().encode(threadIds),
              let json = String(data: data, encoding: .utf8) else { return }
        runBestEffort(["app-state", "pin", "order", "--ids", json, "--json"])
    }

    static func upsertTitle(threadId: String, title: String, source: String) {
        runBestEffort(["app-state", "title", "upsert", threadId, "--title", title, "--source", source, "--json"])
    }

    static func archive(threadId: String) {
        runBestEffort(["app-state", "archive", "set", threadId, "--json"])
    }

    static func unarchive(threadId: String) {
        runBestEffort(["app-state", "archive", "delete", threadId, "--json"])
    }

    static func upsertSidebarSnapshot(
        threadId: String,
        chatUuid: String,
        title: String,
        cwd: String?,
        projectPath: String?,
        updatedAt: Int64,
        archived: Bool,
        pinned: Bool
    ) {
        var args = [
            "app-state", "sidebar", "upsert", threadId,
            "--chat-uuid", chatUuid,
            "--title", title,
            "--updated-at", isoString(seconds: updatedAt),
            "--archived", archived ? "1" : "0",
            "--pinned", pinned ? "1" : "0",
            "--json",
        ]
        if let cwd, !cwd.isEmpty {
            args += ["--cwd", cwd]
        }
        if let projectPath, !projectPath.isEmpty {
            args += ["--project-path", projectPath]
        }
        runBestEffort(args)
    }

    static func replaceSidebarSnapshots(_ snapshots: [ClawJSAppStateSidebarSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots),
              let json = String(data: data, encoding: .utf8) else { return }
        runBestEffort(["app-state", "sidebar", "replace", "--items", json, "--json"])
    }

    static func upsertTerminalTab(
        id: String,
        title: String,
        cwd: String,
        sortOrder: Int,
        metadata: [String: String] = [:]
    ) {
        let metadataJson = (try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)) ?? "{}"
        runBestEffort([
            "app-state", "terminal", "upsert", id,
            "--title", title,
            "--cwd", cwd,
            "--sort-order", String(sortOrder),
            "--metadata", metadataJson,
            "--json",
        ])
    }

    static func deleteTerminalTab(id: String) {
        runBestEffort(["app-state", "terminal", "delete", id, "--json"])
    }

    static func snapshot() async throws -> ClawJSAppStateSnapshot {
        guard ClawJSRuntime.isAvailable else {
            throw CocoaError(.executableNotLoadable)
        }
        let nodeURL = ClawJSRuntime.nodeBinaryURL
        let cliScriptPath = ClawJSRuntime.cliScriptURL.path
        let workspaceURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()
        let data = try await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = nodeURL
            process.arguments = [cliScriptPath, "app-state", "snapshot", "--json"]
            process.currentDirectoryURL = workspaceURL
            process.environment = environment
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let errorText = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? "claw app-state snapshot failed"
                throw NSError(
                    domain: "ClawJSAppStateClient",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText]
                )
            }
            return output
        }.value
        return try JSONDecoder().decode(ClawJSAppStateSnapshot.self, from: data)
    }

    private static func runBestEffort(_ args: [String]) {
        guard ClawJSRuntime.isAvailable else { return }
        let nodeURL = ClawJSRuntime.nodeBinaryURL
        let cliScriptPath = ClawJSRuntime.cliScriptURL.path
        let workspaceURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()
        Task.detached {
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [cliScriptPath] + args
            process.currentDirectoryURL = workspaceURL
            process.environment = environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Local SQLite remains a disposable cache. Failed mirroring is
                // retried by the next user mutation or app-state refresh.
            }
        }
    }

    private static func isoString(seconds: Int64) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}
