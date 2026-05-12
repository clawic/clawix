import SwiftUI

/// Horizontal strip of terminal tabs. Mirrors VS Code / OpenCode shape:
/// chip per tab with its label and a close `×`, plus a `+` button at
/// the trailing edge to spawn a fresh shell. Double-click on a chip
/// renames the tab inline.
struct TerminalTabBar: View {
    @EnvironmentObject var store: TerminalSessionStore
    @EnvironmentObject var appState: AppState
    let chatId: UUID

    @State private var renamingTabId: UUID?
    @State private var renameDraft: String = ""

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(store.tabs(for: chatId).enumerated()), id: \.element.id) { idx, tab in
                        chip(for: tab, ordinal: idx + 1)
                    }
                }
                .padding(.horizontal, 8)
            }
            Button {
                let cwd = appState.chat(byId: chatId)?.cwd ?? NSHomeDirectory()
                store.createTab(chatId: chatId, cwd: cwd)
            } label: {
                LucideIcon(.plus, size: 11)
                    .foregroundColor(Color(white: 0.65))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.001))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("New terminal (⇧⌘T)")
            .accessibilityLabel("New terminal")
        }
        .frame(height: 30)
        .background(Color(white: 0.07))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.popupStroke)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func chip(for tab: TerminalTab, ordinal: Int) -> some View {
        let isActive = store.activeTabId(for: chatId) == tab.id
        let tabLabel = tab.label.isEmpty ? "shell" : tab.label
        HStack(spacing: 6) {
            if renamingTabId == tab.id {
                TextField("", text: $renameDraft, onCommit: {
                    store.renameTab(chatId: chatId, tabId: tab.id, label: renameDraft)
                    renamingTabId = nil
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(Palette.textPrimary)
                .frame(minWidth: 60, maxWidth: 140)
                .onExitCommand { renamingTabId = nil }
            } else {
                Text(tabLabel)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(isActive ? Palette.textPrimary : Color(white: 0.65))
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        renameDraft = tab.label
                        renamingTabId = tab.id
                    }
            }
            Button {
                store.closeTab(chatId: chatId, tabId: tab.id)
            } label: {
                LucideIcon(.x, size: 9)
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Close tab")
            .accessibilityLabel(Text(verbatim: "Close terminal tab \(ordinal): \(tabLabel)"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color(white: 0.16) : Color.clear)
        )
        .overlay(alignment: .top) {
            if isActive {
                Rectangle()
                    .fill(Palette.pastelBlue.opacity(0.85))
                    .frame(height: 1.2)
                    .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTab(chatId: chatId, tabId: tab.id)
        }
    }
}
