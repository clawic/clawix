import Foundation

/// Persistent store for QuickAsk slash commands. Ships with a fixed
/// set (`/search`, `/research`, `/imagine`, `/think`) and accepts
/// user-defined entries via framework-owned snippets for custom workflows.
struct QuickAskSlashCommand: Identifiable, Codable, Equatable {
    let id: UUID
    var trigger: String
    var description: String
    /// Body inserted in place of the trigger. When nil, the trigger
    /// itself stays in the prompt and the slash command acts like a
    /// route hint (e.g. `/search foo`); when non-nil, it expands into
    /// a full prompt template.
    var expansion: String?

    init(id: UUID = UUID(), trigger: String, description: String, expansion: String? = nil) {
        self.id = id
        self.trigger = trigger
        self.description = description
        self.expansion = expansion
    }
}

@MainActor
final class QuickAskSlashCommandsStore: ObservableObject {

    static let shared = QuickAskSlashCommandsStore()

    @Published private(set) var customCommands: [QuickAskSlashCommand] = []

    nonisolated static let snippetKind = "quickask_slash"
    nonisolated static let slugPrefix = "quickask-slash-"

    static let builtIn: [QuickAskSlashCommand] = [
        QuickAskSlashCommand(trigger: "/search",   description: "Search the web"),
        QuickAskSlashCommand(trigger: "/research", description: "Deep research turn"),
        QuickAskSlashCommand(trigger: "/imagine",  description: "Generate an image"),
        QuickAskSlashCommand(trigger: "/think",    description: "Reasoning-heavy turn")
    ]

    private init() {
        load()
    }

    var allCommands: [QuickAskSlashCommand] {
        Self.builtIn + customCommands
    }

    func suggestions(for fragment: String) -> [QuickAskSlashCommand] {
        let q = fragment.lowercased()
        return allCommands.filter { $0.trigger.lowercased().hasPrefix(q) }
    }

    func upsert(_ command: QuickAskSlashCommand) {
        if let idx = customCommands.firstIndex(where: { $0.id == command.id }) {
            customCommands[idx] = command
        } else {
            customCommands.append(command)
        }
        save()
    }

    func remove(_ id: UUID) {
        customCommands.removeAll { $0.id == id }
        try? ClawJSFrameworkRecordsClient.shared.deleteSnippet(slug: "\(Self.slugPrefix)\(id.uuidString.lowercased())")
        save()
    }

    private func load() {
        guard let records = try? ClawJSFrameworkRecordsClient.shared.listSnippets(kind: Self.snippetKind) else { return }
        customCommands = records.compactMap { record in
            let rawId = record.id.replacingOccurrences(of: "snippet-", with: "")
            guard let id = UUID(uuidString: rawId),
                  let trigger = record.metadata?["trigger"],
                  let description = record.metadata?["description"] else { return nil }
            let hasExpansion = record.metadata?["hasExpansion"] == "true"
            return QuickAskSlashCommand(
                id: id,
                trigger: trigger,
                description: description,
                expansion: hasExpansion ? record.body : nil
            )
        }
    }

    private func save() {
        for command in customCommands {
            let id = command.id.uuidString.lowercased()
            try? ClawJSFrameworkRecordsClient.shared.upsertSnippet(
                id: id,
                slug: "\(Self.slugPrefix)\(id)",
                kind: Self.snippetKind,
                title: command.trigger,
                body: command.expansion ?? command.trigger,
                shortcut: command.trigger,
                metadata: [
                    "trigger": command.trigger,
                    "description": command.description,
                    "hasExpansion": command.expansion == nil ? "false" : "true",
                ]
            )
        }
    }
}
