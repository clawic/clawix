import SwiftUI

/// Horizontal strip of terminal tabs.
struct TerminalTabBar: View {
    @EnvironmentObject var store: TerminalSessionStore
    @EnvironmentObject var appState: AppState
    let chatId: UUID

    @State private var renamingTabId: UUID?
    @State private var renameDraft: String = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(store.tabs(for: chatId).enumerated()), id: \.element.id) { idx, tab in
                    chip(for: tab, ordinal: idx + 1)
                }
                NewTerminalButton {
                    let cwd = preferredCwd()
                    store.createTab(chatId: chatId, cwd: cwd)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .scrollDisabled(false)
    }

    private func preferredCwd() -> String {
        store.activeTab(for: chatId)?.initialCwd
            ?? appState.chat(byId: chatId)?.cwd
            ?? NSHomeDirectory()
    }

    @ViewBuilder
    private func chip(for tab: TerminalTab, ordinal: Int) -> some View {
        let isActive = store.activeTabId(for: chatId) == tab.id
        let tabLabel = displayLabel(for: tab)
        TerminalTabChip(
            label: tabLabel,
            ordinal: ordinal,
            isActive: isActive,
            isRenaming: renamingTabId == tab.id,
            renameDraft: $renameDraft,
            onSelect: { store.selectTab(chatId: chatId, tabId: tab.id) },
            onClose: { store.closeTab(chatId: chatId, tabId: tab.id) },
            onBeginRename: {
                renameDraft = tab.label
                renamingTabId = tab.id
            },
            onCommitRename: {
                store.renameTab(chatId: chatId, tabId: tab.id, label: renameDraft)
                renamingTabId = nil
            },
            onCancelRename: { renamingTabId = nil }
        )
    }

    private func displayLabel(for tab: TerminalTab) -> String {
        if !tab.label.isEmpty { return tab.label }
        return TerminalTab.deriveLabel(from: tab.initialCwd)
    }
}

private struct TerminalTabChip: View {
    let label: String
    let ordinal: Int
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onSelect: () -> Void
    let onClose: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            leadingGlyph
            if isRenaming {
                TextField("", text: $renameDraft, onCommit: onCommitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Palette.textPrimary)
                    .frame(minWidth: 50, maxWidth: 160)
                    .onExitCommand(perform: onCancelRename)
            } else {
                Text(label)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .onTapGesture(count: 2, perform: onBeginRename)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chipFill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var chipFill: Color {
        if isActive { return Color.white.opacity(0.08) }
        if hovered { return Color.white.opacity(0.05) }
        return Color.white.opacity(0.04)
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if hovered {
            Button(action: onClose) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                    LucideIcon(.x, size: 7.5)
                        .foregroundColor(Color.white.opacity(0.92))
                }
                .frame(width: 14, height: 14)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close terminal")
            .accessibilityLabel(Text(verbatim: "Close terminal tab \(ordinal): \(label)"))
        } else {
            TerminalIcon(size: 13)
                .foregroundColor(Color(white: 0.85))
                .frame(width: 14, height: 14)
        }
    }
}

private struct NewTerminalButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon(.plus, size: 13)
                .foregroundColor(Color(white: hovered ? 0.95 : 0.65))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.08 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help("New terminal (Cmd-T)")
        .accessibilityLabel("New terminal")
    }
}
