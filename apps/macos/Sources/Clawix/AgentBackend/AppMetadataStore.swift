import Foundation

// Persists Clawix-only metadata that Clawix itself doesn't carry:
// the user's project list, the pinned threads, and which thread belongs
// to which project. Stored as JSON at:
//   ~/Library/Application Support/Clawix/state.json
//
// Codable model on disk:
//   {
//     "version": 1,
//     "projects": [{ "id": "UUID", "title": "Foo", "path": "/abs/path" }],
//     "pinnedThreadIds": ["uuidv7-1", "uuidv7-2"],
//     "chatProjectByThread": { "uuidv7-1": "<project-uuid>" }
//   }
//
// Reads happen once on app start, writes are debounced — every mutation
// schedules a save 200ms in the future, coalescing rapid changes.

struct AppMetadata: Codable, Equatable {
    var version: Int = 2
    var projects: [Project]
    var pinnedThreadIds: [String]
    /// Local visual override: thread id -> workspace root path.
    /// This changes only local grouping; it never changes the thread cwd.
    var chatProjectPathByThread: [String: String]
    /// Local visual override for the projectless bucket.
    var projectlessThreadIds: [String]
    /// Once true, pins are owned locally. Before that, the first launch
    /// seeds them from the runtime's read-only state.
    var hasLocalPins: Bool
    /// Local roots created from this UI. Runtime roots are read-only.
    var localProjects: [Project]

    // Legacy v1 fields kept decodable so old files do not become corrupt.
    var chatProjectByThread: [String: UUID] = [:]
    var chatTitleByThread: [String: String] = [:]

    init(
        version: Int = 2,
        projects: [Project],
        pinnedThreadIds: [String],
        chatProjectPathByThread: [String: String],
        projectlessThreadIds: [String],
        hasLocalPins: Bool,
        localProjects: [Project],
        chatProjectByThread: [String: UUID] = [:],
        chatTitleByThread: [String: String] = [:]
    ) {
        self.version = version
        self.projects = projects
        self.pinnedThreadIds = pinnedThreadIds
        self.chatProjectPathByThread = chatProjectPathByThread
        self.projectlessThreadIds = projectlessThreadIds
        self.hasLocalPins = hasLocalPins
        self.localProjects = localProjects
        self.chatProjectByThread = chatProjectByThread
        self.chatTitleByThread = chatTitleByThread
    }

    enum CodingKeys: String, CodingKey {
        case version, projects, pinnedThreadIds, chatProjectPathByThread
        case projectlessThreadIds, hasLocalPins, localProjects
        case chatProjectByThread, chatTitleByThread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        self.pinnedThreadIds = try c.decodeIfPresent([String].self, forKey: .pinnedThreadIds) ?? []
        self.chatProjectPathByThread = try c.decodeIfPresent([String: String].self, forKey: .chatProjectPathByThread) ?? [:]
        self.projectlessThreadIds = try c.decodeIfPresent([String].self, forKey: .projectlessThreadIds) ?? []
        self.hasLocalPins = try c.decodeIfPresent(Bool.self, forKey: .hasLocalPins) ?? false
        self.localProjects = try c.decodeIfPresent([Project].self, forKey: .localProjects) ?? []
        self.chatProjectByThread = try c.decodeIfPresent([String: UUID].self, forKey: .chatProjectByThread) ?? [:]
        self.chatTitleByThread = try c.decodeIfPresent([String: String].self, forKey: .chatTitleByThread) ?? [:]
    }

    static let empty = AppMetadata(
        version: 2,
        projects: [],
        pinnedThreadIds: [],
        chatProjectPathByThread: [:],
        projectlessThreadIds: [],
        hasLocalPins: false,
        localProjects: []
    )
}

@MainActor
final class AppMetadataStore {

    private static var fileURL: URL {
        if let override = ProcessInfo.processInfo.environment["CLAWIX_METADATA_FILE"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return url
        }
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clawix", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        return supportDir.appendingPathComponent("state.json")
    }

    private var saveTask: Task<Void, Never>?

    func load() -> AppMetadata {
        let url = Self.fileURL
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(AppMetadata.self, from: data)
        } catch {
            // Corrupt or schema-changed: rename it aside so we don't lose it.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return .empty
        }
    }

    /// Schedule a save 200ms in the future. Repeated calls coalesce.
    func scheduleSave(_ value: AppMetadata) {
        saveTask?.cancel()
        saveTask = Task { [value] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            self.writeNow(value)
        }
    }

    /// Force a synchronous flush (used on app teardown or test assertions).
    func writeNow(_ value: AppMetadata) {
        let url = Self.fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
