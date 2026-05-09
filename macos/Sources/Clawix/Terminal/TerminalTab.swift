import Foundation

/// One tab in the per-chat terminal panel. Codable so the entire tab
/// (including its split tree) persists to the `terminal_tabs` table; the
/// live `TerminalSession`s associated with each leaf live in the
/// `TerminalSessionStore` and are not part of this struct.
struct TerminalTab: Identifiable, Equatable, Codable {
    let id: UUID
    let chatId: UUID
    var label: String
    /// Default cwd for any new shell spawned from this tab. Each leaf
    /// stores its own `initialCwd` (it can drift if the user `cd`s to a
    /// different folder before splitting), but this is what the next
    /// fresh shell gets when there is no leaf-level override.
    var initialCwd: String
    var layout: TerminalSplitNode
    var focusedLeafId: UUID?
    var position: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        chatId: UUID,
        label: String,
        initialCwd: String,
        layout: TerminalSplitNode,
        focusedLeafId: UUID? = nil,
        position: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chatId = chatId
        self.label = label
        self.initialCwd = initialCwd
        self.layout = layout
        self.focusedLeafId = focusedLeafId ?? layout.firstLeafId
        self.position = position
        self.createdAt = createdAt
    }

    /// Convenience: build a fresh single-leaf tab seeded from a cwd.
    static func makeInitial(chatId: UUID, cwd: String, position: Int) -> TerminalTab {
        let leafId = UUID()
        let leafLabel = TerminalTab.deriveLabel(from: cwd)
        let leaf = TerminalSplitNode.LeafID(id: leafId, initialCwd: cwd, label: leafLabel)
        return TerminalTab(
            chatId: chatId,
            label: leafLabel,
            initialCwd: cwd,
            layout: .leaf(leaf),
            focusedLeafId: leafId,
            position: position
        )
    }

    /// Strips the path prefix and returns a friendly basename used as
    /// default label. Falls back to "shell" for the home dir.
    static func deriveLabel(from cwd: String) -> String {
        let expanded = (cwd as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let base = url.lastPathComponent
        if base.isEmpty || base == "/" { return "shell" }
        if expanded == NSHomeDirectory() { return "shell" }
        return base
    }
}
