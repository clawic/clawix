import SwiftUI

struct QuickAskMessageBubble: View {
    let message: ChatMessage
    let appState: AppState

    var body: some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 36)
                Text(displayText)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            assistantBody
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var assistantBody: some View {
        if message.isError {
            AssistantMarkdownText(
                text: displayText,
                weight: .regular,
                color: Color(red: 0.95, green: 0.45, blue: 0.45),
                checkpoints: [],
                streamingFinished: true
            )
            .environmentObject(appState)
            .fixedSize(horizontal: false, vertical: true)
        } else if displayText.isEmpty && !message.streamingFinished {
            ThinkingShimmer(
                text: String(
                    localized: "Thinking",
                    bundle: AppLocale.bundle,
                    locale: AppLocale.current
                )
            )
        } else {
            AssistantMarkdownText(
                text: displayText,
                weight: .light,
                color: Palette.textPrimary,
                checkpoints: message.streamCheckpoints,
                streamingFinished: message.streamingFinished
            )
            .environmentObject(appState)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayText: String {
        message.content.trimmingCharacters(in: .newlines)
    }
}

enum QuickAskScrollAnchor: Hashable {
    case bottom
}
