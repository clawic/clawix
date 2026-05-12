import SwiftUI

/// The terminal panel mounted at the bottom of the chat content
/// column.
struct TerminalPanel: View {
    @EnvironmentObject var store: TerminalSessionStore
    @EnvironmentObject var appState: AppState
    let chatId: UUID
    var onLastTabClosed: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(chatId: chatId)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .background(Color.black)
        }
        .background(Color.black)
        .onAppear {
            store.ensureLoaded(chatId: chatId)
            ensureAtLeastOneTab()
        }
        .onChange(of: chatId) { _, newChatId in
            store.ensureLoaded(chatId: newChatId)
            ensureAtLeastOneTab(chatId: newChatId)
        }
        .onChange(of: store.tabsByChat[chatId]?.count ?? 0) { _, newCount in
            if newCount == 0 { onLastTabClosed() }
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
            .id(tab.id)
        } else {
            Color.black
        }
    }

    private func ensureAtLeastOneTab(chatId overrideId: UUID? = nil) {
        let target = overrideId ?? chatId
        if store.tabs(for: target).isEmpty {
            let cwd = appState.chat(byId: target)?.cwd ?? NSHomeDirectory()
            store.createTab(chatId: target, cwd: cwd)
        }
    }
}
