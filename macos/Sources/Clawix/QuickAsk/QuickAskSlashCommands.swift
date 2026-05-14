import Foundation

/// Persistent store for QuickAsk slash commands. Ships with a fixed
/// set (`/search`, `/research`, `/imagine`, `/think`) and accepts
/// user-defined entries via `UserDefaults` for custom workflows.
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

    nonisolated static let defaultsKey = "quickAsk.slashCommandsCustom"

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
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([QuickAskSlashCommand].self, from: data) {
            customCommands = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(customCommands) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
