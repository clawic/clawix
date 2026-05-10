import SwiftUI

/// The terminal panel mounted at the bottom of the chat content
/// column. Contains a tab bar at top, a divider, and the active tab's
/// split tree below. Renders only when the user is on a chat route;
/// `ContentBodyWithTerminal` (in ContentView.swift) gates that.
struct TerminalPanel: View {
    @EnvironmentObject var store: TerminalSessionStore
    @EnvironmentObject var appState: AppState
    let chatId: UUID
    @State private var commandDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(chatId: chatId)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            commandBar
        }
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.popupStroke, lineWidth: 0.7)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .onAppear {
            store.ensureLoaded(chatId: chatId)
            ensureAtLeastOneTab()
        }
        .onChange(of: chatId) { _, newChatId in
            store.ensureLoaded(chatId: newChatId)
            ensureAtLeastOneTab(chatId: newChatId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tab = store.activeTab(for: chatId) {
            TerminalSplitView(
                chatId: chatId,
                tabId: tab.id,
                node: tab.layout,
                focusedLeafId: tab.focusedLeafId,
                path: []
            )
            .padding(6)
            .id(tab.id)
        } else {
            ZStack {
                Color.black
                Text("No terminals open. ⇧⌘T to start one.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
            }
        }
    }

    private func ensureAtLeastOneTab(chatId overrideId: UUID? = nil) {
        let target = overrideId ?? chatId
        if store.tabs(for: target).isEmpty {
            let cwd = appState.chat(byId: target)?.cwd ?? NSHomeDirectory()
            store.createTab(chatId: target, cwd: cwd)
        }
    }

    private var commandBar: some View {
        HStack(spacing: 6) {
            Text(">")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
            TextField("Terminal command", text: $commandDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.textPrimary)
                .accessibilityLabel("Terminal command")
                .onSubmit(runCommand)
            Button("Run", action: runCommand)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textSecondary)
                .disabled(commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color(white: 0.06))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.popupStroke)
                .frame(height: 0.5)
        }
    }

    private func runCommand() {
        let command = commandDraft
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if store.runCommandInFocusedTerminal(chatId: chatId, command: command) {
            commandDraft = ""
        }
    }
}
