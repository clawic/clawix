import Foundation
import SwiftUI
import AppKit

/// Single source of truth for the integrated terminal panel. One
/// instance lives in the `AppState` environment and owns:
///
/// - The map `[chatId: [TerminalTab]]` (codable, persisted to GRDB).
/// - The map `[sessionId: TerminalSession]` (live; NSViews + PTYs).
/// - Lifecycle for each shell: spawn on tab/leaf creation, kill on
///   close, kill-all on app shutdown.
///
/// The store is `@MainActor` because everything it touches
/// (LocalProcessTerminalView is an NSView, GRDB DatabaseQueue is
/// MainActor-bound via `Database.shared`) is.
@MainActor
final class TerminalSessionStore: ObservableObject {
    /// Process-wide instance. `App.swift` wraps this in `@StateObject`;
    /// `AppDelegate.applicationWillTerminate` reads it back to send
    /// SIGHUP to every shell before the process exits.
    static let shared = TerminalSessionStore()

    /// Sentinel chat id for terminal tabs on the home screen.
    static let homeChatId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Tabs keyed by chat id. `@Published` so the panel rebinds when a
    /// tab is added/removed/reordered.
    @Published private(set) var tabsByChat: [UUID: [TerminalTab]] = [:]
    /// Currently active tab id per chat. Persisted only in memory: at
    /// next launch we default to the first tab in tree order.
    @Published private(set) var activeTabIdByChat: [UUID: UUID] = [:]
    /// True when one of the live terminal emulator NSViews is window
    /// first responder.
    @Published private(set) var keyboardFocused: Bool = false

    func setKeyboardFocused(_ focused: Bool) {
        guard keyboardFocused != focused else { return }
        keyboardFocused = focused
    }

    /// Live sessions keyed by leaf id.
    private var sessions: [UUID: TerminalSession] = [:]
    /// Chats whose persisted tabs we've already loaded this app
    /// session, to avoid re-spawning shells on every route change.
    private var loadedChats: Set<UUID> = []

    private let repository: TerminalTabsRepository

    init(repository: TerminalTabsRepository = TerminalTabsRepository.shared) {
        self.repository = repository
    }

    // MARK: - Loading

    /// Hydrate `chatId`'s tabs from disk if not already loaded. If the
    /// chat has no persisted tabs, leaves the panel empty (the panel
    /// auto-creates a default tab on first toggle).
    func ensureLoaded(chatId: UUID) {
        if loadedChats.contains(chatId) { return }
        loadedChats.insert(chatId)
        let stored = repository.loadTabs(chatId: chatId)
        if !stored.isEmpty {
            tabsByChat[chatId] = stored
            // Re-instantiate one TerminalSession per leaf at its
            // recorded cwd. Process is fresh — scrollback is empty.
            for tab in stored {
                for leaf in tab.layout.leaves {
                    if sessions[leaf.id] == nil {
                        sessions[leaf.id] = TerminalSession(
                            id: leaf.id,
                            chatId: chatId,
                            initialCwd: leaf.initialCwd,
                            label: leaf.label
                        )
                    }
                }
                if let active = activeTabIdByChat[chatId], stored.contains(where: { $0.id == active }) {
                    // keep
                } else if let first = stored.first {
                    activeTabIdByChat[chatId] = first.id
                }
            }
        }
    }

    // MARK: - Reads

    func tabs(for chatId: UUID) -> [TerminalTab] {
        tabsByChat[chatId] ?? []
    }

    func activeTabId(for chatId: UUID) -> UUID? {
        activeTabIdByChat[chatId]
    }

    func activeTab(for chatId: UUID) -> TerminalTab? {
        guard let activeId = activeTabIdByChat[chatId] else { return nil }
        return tabsByChat[chatId]?.first(where: { $0.id == activeId })
    }

    func session(for leafId: UUID) -> TerminalSession? {
        sessions[leafId]
    }

    // MARK: - Tab CRUD

    /// Creates a new tab seeded with `cwd`. If `cwd` is nil, falls back
    /// to `$HOME`. Returns the new tab id.
    @discardableResult
    func createTab(chatId: UUID, cwd: String?) -> UUID {
        let resolved = cwd?.isEmpty == false ? cwd! : NSHomeDirectory()
        let position = (tabsByChat[chatId]?.count ?? 0)
        let tab = TerminalTab.makeInitial(chatId: chatId, cwd: resolved, position: position)
        for leaf in tab.layout.leaves {
            sessions[leaf.id] = TerminalSession(
                id: leaf.id,
                chatId: chatId,
                initialCwd: leaf.initialCwd,
                label: leaf.label
            )
        }
        var list = tabsByChat[chatId] ?? []
        list.append(tab)
        tabsByChat[chatId] = list
        activeTabIdByChat[chatId] = tab.id
        repository.upsert(tab)
        return tab.id
    }

    func selectTab(chatId: UUID, tabId: UUID) {
        guard tabsByChat[chatId]?.contains(where: { $0.id == tabId }) == true else { return }
        activeTabIdByChat[chatId] = tabId
    }

    func closeTab(chatId: UUID, tabId: UUID) {
        guard var list = tabsByChat[chatId],
              let idx = list.firstIndex(where: { $0.id == tabId }) else { return }
        let removed = list.remove(at: idx)
        // Kill every shell in the closed tab.
        for leaf in removed.layout.leaves {
            killSession(leafId: leaf.id)
        }
        // Renumber position so consecutive saves don't drift.
        for i in list.indices { list[i].position = i }
        tabsByChat[chatId] = list
        repository.delete(tabId: tabId)
        for tab in list { repository.upsert(tab) }

        if activeTabIdByChat[chatId] == tabId {
            activeTabIdByChat[chatId] = list.first?.id
        }
    }

    func renameTab(chatId: UUID, tabId: UUID, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var list = tabsByChat[chatId],
              let idx = list.firstIndex(where: { $0.id == tabId }) else { return }
        list[idx].label = trimmed
        tabsByChat[chatId] = list
        repository.upsert(list[idx])
    }

    func reorderTabs(chatId: UUID, ordering: [UUID]) {
        guard var list = tabsByChat[chatId] else { return }
        let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        var newList: [TerminalTab] = []
        for (newPos, id) in ordering.enumerated() {
            guard var tab = byId[id] else { continue }
            tab.position = newPos
            newList.append(tab)
        }
        // Append any missing tabs (defensive) at the end.
        for tab in list where !ordering.contains(tab.id) {
            var t = tab
            t.position = newList.count
            newList.append(t)
        }
        list = newList
        tabsByChat[chatId] = list
        for tab in list { repository.upsert(tab) }
    }

    // MARK: - Splits

    /// Split the leaf with `leafId` in the given direction, spawning a
    /// fresh shell in the original leaf's cwd.
    func splitLeaf(chatId: UUID, tabId: UUID, leafId: UUID, direction: TerminalSplitNode.SplitDirection) {
        guard var list = tabsByChat[chatId],
              let idx = list.firstIndex(where: { $0.id == tabId }) else { return }
        let originalLeaves = list[idx].layout.leaves
        guard let originalLeaf = originalLeaves.first(where: { $0.id == leafId }) else { return }
        let newLeaf = TerminalSplitNode.LeafID(
            id: UUID(),
            initialCwd: originalLeaf.initialCwd,
            label: originalLeaf.label
        )
        list[idx].layout = list[idx].layout.splitting(
            beside: leafId,
            direction: direction,
            newLeaf: newLeaf
        )
        list[idx].focusedLeafId = newLeaf.id
        tabsByChat[chatId] = list
        sessions[newLeaf.id] = TerminalSession(
            id: newLeaf.id,
            chatId: chatId,
            initialCwd: newLeaf.initialCwd,
            label: newLeaf.label
        )
        repository.upsert(list[idx])
    }

    /// Close one pane. If it was the only pane, closes the whole tab.
    func closeLeaf(chatId: UUID, tabId: UUID, leafId: UUID) {
        guard var list = tabsByChat[chatId],
              let idx = list.firstIndex(where: { $0.id == tabId }) else { return }
        if let newLayout = list[idx].layout.removingLeaf(leafId) {
            list[idx].layout = newLayout
            if list[idx].focusedLeafId == leafId {
                list[idx].focusedLeafId = newLayout.firstLeafId
            }
            tabsByChat[chatId] = list
            repository.upsert(list[idx])
            killSession(leafId: leafId)
        } else {
            killSession(leafId: leafId)
            closeTab(chatId: chatId, tabId: tabId)
        }
    }

    func setFocusedLeaf(chatId: UUID, tabId: UUID, leafId: UUID) {
        guard var list = tabsByChat[chatId],
              let idx = list.firstIndex(where: { $0.id == tabId }),
              list[idx].focusedLeafId != leafId else { return }
        list[idx].focusedLeafId = leafId
        tabsByChat[chatId] = list
        repository.upsert(list[idx])
    }

    @discardableResult
    func sendTextToFocusedTerminal(chatId: UUID, text: String) -> Bool {
        guard let tab = activeTab(for: chatId),
              let leafId = tab.focusedLeafId ?? tab.layout.firstLeafId,
              let session = sessions[leafId] else {
            return false
        }
        session.sendText(text)
        return true
    }

    @discardableResult
    func runCommandInFocusedTerminal(chatId: UUID, command: String) -> Bool {
        guard let tab = activeTab(for: chatId),
              let leafId = tab.focusedLeafId ?? tab.layout.firstLeafId,
              let session = sessions[leafId] else {
            return false
        }
        session.runCommand(command)
        return true
    }

    /// Move a whole tab into another tab as a new split next to
    /// `destLeafId`. Used for VS Code-style drag-out: the user grabs a
    /// tab chip and drops it on a pane area inside a different tab; the
    /// source tab's entire layout (including any nested splits) is
    /// grafted into the destination tab on the chosen side and the
    /// source tab disappears. Shells keep running — only the layout
    /// edges change.
    func moveTabAsSplit(chatId: UUID,
                        sourceTabId: UUID,
                        destTabId: UUID,
                        destLeafId: UUID,
                        direction: TerminalSplitNode.SplitDirection,
                        insertBefore: Bool) {
        guard sourceTabId != destTabId,
              var list = tabsByChat[chatId],
              let sourceIdx = list.firstIndex(where: { $0.id == sourceTabId }),
              let destIdx = list.firstIndex(where: { $0.id == destTabId }) else { return }
        let sourceLayout = list[sourceIdx].layout
        // Insert the source subtree first so indices stay valid after we
        // remove the source tab.
        list[destIdx].layout = list[destIdx].layout.splitting(
            beside: destLeafId,
            direction: direction,
            newSubtree: sourceLayout,
            insertBefore: insertBefore
        )
        // Focus moves to the first leaf of the dropped subtree so the
        // user keeps interacting with the shell they dragged.
        list[destIdx].focusedLeafId = sourceLayout.firstLeafId
        let sourceTabIdSnapshot = list[sourceIdx].id
        list.remove(at: sourceIdx)
        for i in list.indices { list[i].position = i }
        tabsByChat[chatId] = list
        activeTabIdByChat[chatId] = destTabId
        repository.delete(tabId: sourceTabIdSnapshot)
        for tab in list { repository.upsert(tab) }
    }

    func adjustWeights(chatId: UUID,
                       tabId: UUID,
                       splitPath: [Int],
                       adjacentIndex: Int,
                       newLeftWeight: Double) {
        guard var list = tabsByChat[chatId],
              let idx = list.firstIndex(where: { $0.id == tabId }) else { return }
        list[idx].layout = list[idx].layout.adjustingWeights(
            at: splitPath,
            adjacentIndex: adjacentIndex,
            newLeftWeight: newLeftWeight
        )
        tabsByChat[chatId] = list
        repository.upsert(list[idx])
    }

    // MARK: - Lifecycle

    /// Send SIGHUP, then SIGKILL after a grace period. The actual
    /// process teardown also closes the master fd, which lets SwiftTerm's
    /// read loop exit cleanly.
    private func killSession(leafId: UUID) {
        guard let session = sessions.removeValue(forKey: leafId) else { return }
        session.terminate()
        let view = session.terminalView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak view] in
            _ = view  // retain briefly while OS reaps the child
        }
    }

    /// Kill every shell tied to `chatId`. Tab records remain in the DB
    /// unless `dropPersisted` is true (chat hard-delete).
    func killAllForChat(_ chatId: UUID, dropPersisted: Bool = false) {
        let tabs = tabsByChat[chatId] ?? []
        for tab in tabs {
            for leaf in tab.layout.leaves {
                killSession(leafId: leaf.id)
            }
        }
        tabsByChat.removeValue(forKey: chatId)
        activeTabIdByChat.removeValue(forKey: chatId)
        loadedChats.remove(chatId)
        if dropPersisted {
            repository.deleteAllForChat(chatId)
        }
    }

    /// Called from `applicationWillTerminate`. SIGHUP everything; the
    /// process exit reaps the rest synchronously.
    func shutdown() {
        for (_, session) in sessions {
            session.terminate()
        }
        sessions.removeAll()
    }
}
