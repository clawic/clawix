import SwiftUI
import ClawixCore

struct ChatDetailView: View {
    @Bindable var store: BridgeStore
    let chatId: String
    let onBack: () -> Void

    @State private var composerText: String = ""
    @State private var expandedReasoning: Set<String> = []

    private var chat: WireChat? { store.chat(chatId) }
    private var messages: [WireMessage] { store.messages(for: chatId) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Divider()
                    .background(Palette.borderSubtle)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(messages, id: \.id) { msg in
                                MessageBubble(
                                    message: msg,
                                    isReasoningExpanded: expandedReasoning.contains(msg.id),
                                    toggleReasoning: { toggleReasoning(messageId: msg.id) }
                                )
                                .id(msg.id)
                            }
                            Spacer().frame(height: 12)
                        }
                        .padding(.horizontal, AppLayout.screenHorizontalPadding)
                        .padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                    .fadeEdge(height: 32)
                    .onChange(of: messages.last?.id) { _, last in
                        guard let last else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
                ComposerView(text: $composerText, onSend: send)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MenuStyle.rowText)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.cardFill)
                    )
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat?.title ?? "Chat")
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                if let chat, let branch = chat.branch {
                    Text(branch)
                        .font(Typography.captionFont)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer()
            if chat?.hasActiveTurn == true {
                ActiveTurnPill()
            }
        }
        .padding(.horizontal, AppLayout.screenHorizontalPadding)
        .padding(.vertical, 10)
    }

    private func toggleReasoning(messageId: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if expandedReasoning.contains(messageId) {
                expandedReasoning.remove(messageId)
            } else {
                expandedReasoning.insert(messageId)
            }
        }
    }

    private func send() {
        let text = composerText
        composerText = ""
        store.sendPrompt(chatId: chatId, text: text)
    }
}

private struct MessageBubble: View {
    let message: WireMessage
    let isReasoningExpanded: Bool
    let toggleReasoning: () -> Void

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBlock
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.content)
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.selFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.reasoningText.isEmpty {
                ReasoningDisclosure(
                    text: message.reasoningText,
                    isExpanded: isReasoningExpanded,
                    toggle: toggleReasoning
                )
            }
            Text(message.content.isEmpty && !message.streamingFinished ? "Thinking..." : message.content)
                .font(Typography.bodyFont)
                .foregroundStyle(message.content.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)
            if !message.streamingFinished && !message.content.isEmpty {
                StreamingDots()
            }
        }
    }
}

private struct ReasoningDisclosure: View {
    let text: String
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    Text("Reasoning")
                        .font(Typography.captionFont)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                Text(text)
                    .font(Typography.secondaryFont)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                            .fill(Palette.border)
                            .frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct StreamingDots: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .fill(Palette.textTertiary)
                    .frame(width: 5, height: 5)
                    .opacity(phase == idx ? 1.0 : 0.35)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

private struct ActiveTurnPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                .frame(width: 6, height: 6)
            Text("Working")
                .font(Typography.captionFont)
                .foregroundStyle(MenuStyle.rowText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
    }
}

#Preview("Chat detail") {
    let store = BridgeStore.mock()
    return ChatDetailView(
        store: store,
        chatId: MockData.chats[0].id,
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
