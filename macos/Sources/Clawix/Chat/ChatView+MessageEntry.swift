import AppKit
import SwiftUI
import ClawixCore

struct ChatMessageEntryView: View {
    let appState: AppState
    let chat: Chat
    let message: ChatMessage
    let lastUserMessageId: UUID?
    let lastAssistantMessageId: UUID?
    let responseStreaming: Bool
    let activeFindQuery: String
    let publishingReady: Bool
    let proxy: ScrollViewProxy

    var body: some View {
        MessageRow(
            chatId: chat.id,
            message: message,
            isLastUserMessage: message.id == lastUserMessageId,
            isLastAssistantMessage: message.id == lastAssistantMessageId,
            responseStreaming: responseStreaming,
            findQuery: activeFindQuery,
            onTimelineExpanded: { expandedId in
                // Pin the bottom of the expanded bubble so inserted content grows upward.
                DispatchQueue.main.async {
                    proxy.scrollTo(expandedId, anchor: .bottom)
                }
            },
            onUserBubbleExpanded: { expandedId in
                DispatchQueue.main.async {
                    proxy.scrollTo(expandedId, anchor: .bottom)
                }
            },
            onEditUserMessage: { newContent in
                appState.editUserMessage(
                    chatId: chat.id,
                    messageId: message.id,
                    newContent: newContent
                )
            },
            onForkConversation: {
                appState.forkConversation(
                    chatId: chat.id,
                    atMessageId: message.id,
                    sourceSnapshot: chat
                )
            },
            onOpenImage: { url in
                appState.imagePreviewURL = url
            },
            onPushToPublishing: { body in
                appState.navigate(to: .publishingComposer(prefillBody: body, prefillScheduleAt: nil))
            },
            publishingReady: publishingReady
        )
        .equatable()
        .id(message.id)
        .transaction { transaction in
            transaction.animation = nil
        }

        if message.id == chat.forkBannerAfterMessageId,
           let parentChatId = chat.forkedFromChatId {
            ForkedFromBanner(parentChatId: parentChatId)
                .padding(.top, -20)
        }
    }
}
