import Foundation
import AppKit
import KeyboardShortcuts

/// Wires the terminal-panel keyboard shortcuts (toggle, new tab, etc.)
/// to runtime actions. Registered once from
/// `AppDelegate.applicationDidFinishLaunching`. Mirrors the pattern of
/// `DictationShortcutsInstaller`.
///
/// The toggle handler only flips the registered terminal-panel-open preference
/// flag. Whether the panel actually renders is decided downstream by
/// `ContentBodyWithTerminal`, which gates on the current route — so
/// pressing the shortcut on a non-chat screen does nothing visible
/// (this is fine; the user can navigate to a chat and the panel will
/// already be marked open).
@MainActor
enum TerminalShortcutsInstaller {
    private static var installed = false

    static func installIfNeeded(store: TerminalSessionStore, resolveChatId: @escaping () -> UUID?) {
        if installed { return }
        installed = true

        KeyboardShortcuts.onKeyDown(for: .terminalToggle) {
            let key = "TerminalPanelOpen"
            let current = SidebarPrefs.store.bool(forKey: key)
            SidebarPrefs.store.set(!current, forKey: key)
        }

        KeyboardShortcuts.onKeyDown(for: .terminalNewTab) {
            guard !NSApp.isActive else { return }
            guard let chatId = resolveChatId() else { return }
            let cwd = TerminalShortcutsInstaller.cwdForChat(chatId, store: store)
            store.createTab(chatId: chatId, cwd: cwd)
            // Auto-open the panel if it was closed.
            SidebarPrefs.store.set(true, forKey: "TerminalPanelOpen")
        }

        KeyboardShortcuts.onKeyDown(for: .terminalCloseTab) {
            guard !NSApp.isActive else { return }
            guard let chatId = resolveChatId(),
                  let active = store.activeTabId(for: chatId) else { return }
            store.closeTab(chatId: chatId, tabId: active)
        }

        KeyboardShortcuts.onKeyDown(for: .terminalNextTab) {
            guard let chatId = resolveChatId() else { return }
            let tabs = store.tabs(for: chatId)
            guard !tabs.isEmpty,
                  let active = store.activeTabId(for: chatId),
                  let idx = tabs.firstIndex(where: { $0.id == active }) else { return }
            let next = tabs[(idx + 1) % tabs.count]
            store.selectTab(chatId: chatId, tabId: next.id)
        }

        KeyboardShortcuts.onKeyDown(for: .terminalPreviousTab) {
            guard let chatId = resolveChatId() else { return }
            let tabs = store.tabs(for: chatId)
            guard !tabs.isEmpty,
                  let active = store.activeTabId(for: chatId),
                  let idx = tabs.firstIndex(where: { $0.id == active }) else { return }
            let prev = tabs[(idx - 1 + tabs.count) % tabs.count]
            store.selectTab(chatId: chatId, tabId: prev.id)
        }

        KeyboardShortcuts.onKeyDown(for: .terminalSplitVertical) {
            TerminalShortcutsInstaller.split(direction: .horizontal,
                                             store: store,
                                             resolveChatId: resolveChatId)
        }

        KeyboardShortcuts.onKeyDown(for: .terminalSplitHorizontal) {
            TerminalShortcutsInstaller.split(direction: .vertical,
                                             store: store,
                                             resolveChatId: resolveChatId)
        }
    }

    private static func split(direction: TerminalSplitNode.SplitDirection,
                              store: TerminalSessionStore,
                              resolveChatId: () -> UUID?) {
        guard let chatId = resolveChatId(),
              let tab = store.activeTab(for: chatId),
              let leaf = tab.focusedLeafId ?? tab.layout.firstLeafId else { return }
        store.splitLeaf(chatId: chatId, tabId: tab.id, leafId: leaf, direction: direction)
    }

    private static func cwdForChat(_ chatId: UUID, store: TerminalSessionStore) -> String {
        // Prefer the cwd of the current active tab if any; otherwise
        // fall back to $HOME. AppState's per-chat cwd is queried in
        // `TerminalPanel.ensureAtLeastOneTab` for the first-time path,
        // so the keyboard-shortcut path can just inherit from existing
        // tabs.
        if let active = store.activeTab(for: chatId) {
            return active.initialCwd
        }
        return NSHomeDirectory()
    }
}
