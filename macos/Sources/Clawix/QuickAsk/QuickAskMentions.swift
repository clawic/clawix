import Foundation

/// One entry in the QuickAsk `@` dropdown. Either a file path inside
/// the active project (resolved to an absolute path so the daemon
/// can dereference it as a `@<path>` mention) or a custom prompt the
/// user has saved as an "agent" template.
enum QuickAskMentionItem: Identifiable, Equatable {
    case file(QuickAskMentionFile)
    case prompt(QuickAskMentionPrompt)

    var id: UUID {
        switch self {
        case .file(let f): return f.id
        case .prompt(let p): return p.id
        }
    }

    var displayName: String {
        switch self {
        case .file(let f): return f.relativePath
        case .prompt(let p): return p.name
        }
    }

    var description: String {
        switch self {
        case .file(let f): return f.absolutePath
        case .prompt(let p): return p.description
        }
    }
}

struct QuickAskMentionFile: Identifiable, Equatable {
    let id: UUID
    let relativePath: String
    let absolutePath: String

    init(id: UUID = UUID(), relativePath: String, absolutePath: String) {
        self.id = id
        self.relativePath = relativePath
        self.absolutePath = absolutePath
    }
}

struct QuickAskMentionPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var body: String

    init(id: UUID = UUID(), name: String, description: String, body: String) {
        self.id = id
        self.name = name
        self.description = description
        self.body = body
    }
}

@MainActor
final class QuickAskMentionsStore: ObservableObject {

    static let shared = QuickAskMentionsStore()

    @Published private(set) var customPrompts: [QuickAskMentionPrompt] = []

    private let defaultsKey = "quickAsk.mentionPromptsCustom"

    private init() {
        load()
    }

    func suggestions(
        fragment: String,
        projectRoot: URL?,
        limit: Int = 8
    ) -> [QuickAskMentionItem] {
        let q = fragment.trimmingCharacters(in: .whitespaces).lowercased()

        let promptHits: [QuickAskMentionItem] = customPrompts
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .map { .prompt($0) }

        var fileHits: [QuickAskMentionItem] = []
        if let root = projectRoot {
            fileHits = walkFiles(at: root, query: q, limit: max(0, limit - promptHits.count))
                .map(QuickAskMentionItem.file)
        }

        return Array((promptHits + fileHits).prefix(limit))
    }

    func upsert(_ prompt: QuickAskMentionPrompt) {
        if let idx = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[idx] = prompt
        } else {
            customPrompts.append(prompt)
        }
        save()
    }

    func remove(_ id: UUID) {
        customPrompts.removeAll { $0.id == id }
        save()
    }

    private func walkFiles(at root: URL, query: String, limit: Int) -> [QuickAskMentionFile] {
        guard limit > 0 else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var matches: [QuickAskMentionFile] = []
        let prefix = root.path
        // Cap traversal at a moderate budget so a giant repo doesn't
        // freeze the dropdown. The user can always type more
        // characters to narrow the search.
        var visited = 0
        let visitCap = 4000

        for case let url as URL in enumerator {
            visited += 1
            if visited > visitCap { break }
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else { continue }
            let absolute = url.path
            let relative: String = {
                if absolute.hasPrefix(prefix) {
                    return String(absolute.dropFirst(prefix.count + 1))
                }
                return absolute
            }()
            if !query.isEmpty, !relative.lowercased().contains(query) { continue }
            matches.append(QuickAskMentionFile(
                relativePath: relative,
                absolutePath: absolute
            ))
            if matches.count >= limit { break }
        }
        return matches
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([QuickAskMentionPrompt].self, from: data) {
            customPrompts = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(customPrompts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
