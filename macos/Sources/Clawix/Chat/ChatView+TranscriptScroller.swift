import AppKit
import SwiftUI
import ClawixCore

struct ChatTranscriptScrollerView: View {
    let appState: AppState
    let chatId: UUID
    let chat: Chat
    let visibleMessages: [ChatMessage]
    let hiddenLocalMessageCount: Int
    @Binding var visibleMessageLimit: Int
    @Binding var lastLocalRevealAt: Date
    @Binding var bottomId: String?
    let chatTailId: String
    let publishingReady: Bool

    private var bottomScrollBinding: Binding<String?> {
        Binding<String?>(
            get: { bottomId },
            set: { newValue in
                let normalized = newValue == chatTailId ? chatTailId : nil
                if bottomId != normalized {
                    bottomId = normalized
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 44) {
                    if appState.messagesPaginationByChat[chatId]?.loadingOlder == true {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .frame(height: 28)
                        .transition(.opacity)
                    }
                    let lastUserMessageId = lastUserMessageId(in: chat.messages)
                    let lastAssistantMessageId = lastCompletedAssistantMessageId(in: chat.messages)
                    let responseStreaming = isResponseStreaming(chat)
                    let activeFindQuery = appState.isFindBarOpen ? appState.findQuery : ""
                    ForEach(visibleMessages) { (msg: ChatMessage) in
                        ChatMessageEntryView(
                            appState: appState,
                            chat: chat,
                            message: msg,
                            lastUserMessageId: lastUserMessageId,
                            lastAssistantMessageId: lastAssistantMessageId,
                            responseStreaming: responseStreaming,
                            activeFindQuery: activeFindQuery,
                            publishingReady: publishingReady,
                            proxy: proxy
                        )
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(chatTailId)
                }
                .frame(maxWidth: chatRailMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .background(ThinScrollerInstaller(style: .clawixAlwaysVisible).allowsHitTesting(false))
            }
            .scrollPosition(id: bottomScrollBinding, anchor: .bottom)
            .modifier(ChatScrollDeclarativeAnchors())
            .modifier(ChatScrollUpSentinel(
                threshold: ChatView.loadOlderThreshold,
                onTrigger: {
                    handleScrollUpTrigger(proxy: proxy)
                }
            ))
            .onAppear {
                appState.ensureSelectedChat()
                visibleMessageLimit = ChatView.initialVisibleMessageLimit
                lastLocalRevealAt = .distantPast
                bottomId = chatTailId
            }
            .onChange(of: chatId) { _, _ in
                appState.ensureSelectedChat()
                appState.requestComposerFocus()
                visibleMessageLimit = ChatView.initialVisibleMessageLimit
                lastLocalRevealAt = .distantPast
                bottomId = chatTailId
            }
            .onChange(of: appState.currentFindIndex) { _, _ in
                scrollToCurrentFindMatch(proxy: proxy)
            }
            .onChange(of: appState.findMatches.count) { _, _ in
                scrollToCurrentFindMatch(proxy: proxy)
            }
            .task(id: prewarmKey) {
                await ChatMarkdownPrewarmer.prewarm(
                    messages: visibleMessages,
                    timelineEntryLimit: MessageRow.initialTimelineEntryLimit
                )
            }
        }
    }

    private var prewarmKey: ChatMarkdownPrewarmKey {
        ChatMarkdownPrewarmKey(
            chatId: chat.id,
            visibleMessageCount: visibleMessages.count,
            firstMessageId: visibleMessages.first?.id,
            lastMessageId: visibleMessages.last?.id,
            lastTimelineCount: visibleMessages.last?.timeline.count ?? 0
        )
    }

    private func scrollToCurrentFindMatch(proxy: ScrollViewProxy) {
        guard appState.isFindBarOpen,
              appState.findChatId == chatId,
              let match = appState.currentFindMatch else { return }
        withAnimation(.easeOut(duration: 0.20)) {
            proxy.scrollTo(match.messageId, anchor: .center)
        }
    }

    private func handleScrollUpTrigger(proxy: ScrollViewProxy) {
        if hiddenLocalMessageCount > 0 {
            let now = Date()
            guard now.timeIntervalSince(lastLocalRevealAt) >= ChatView.localRevealThrottle else {
                return
            }
            lastLocalRevealAt = now
            let anchorId = visibleMessages.first?.id
            bottomId = nil
            visibleMessageLimit = min(
                chat.messages.count,
                visibleMessageLimit + ChatView.visibleMessagePageSize
            )
            if let anchorId {
                DispatchQueue.main.async {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(anchorId, anchor: .top)
                    }
                }
            }
        } else {
            appState.requestOlderIfNeeded(chatId: chatId)
        }
    }

    private func lastUserMessageId(in messages: [ChatMessage]) -> UUID? {
        messages.last(where: { $0.role == .user })?.id
    }

    private func lastCompletedAssistantMessageId(in messages: [ChatMessage]) -> UUID? {
        messages.last { message in
            message.role == .assistant && message.streamingFinished && !message.isError
        }?.id
    }

    private func isResponseStreaming(_ chat: Chat) -> Bool {
        if let lastAssistant = chat.messages.last(where: { $0.role == .assistant }) {
            return !lastAssistant.streamingFinished
        }
        return chat.hasActiveTurn
    }
}
