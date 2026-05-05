import SwiftUI
import ClawixCore
#if canImport(UIKit)
import UIKit
#endif

// ChatGPT-iOS-styled chat surface, rebuilt on iOS 26 Liquid Glass.
// Architecture:
//   - pure black canvas filling the window
//   - transcript scrolls edge-to-edge underneath the floating chrome
//   - top bar: two glass clusters in `GlassEffectContainer`s so they
//     morph as a unit when system animations run (rotation, dynamic
//     type, working pill appearing)
//   - composer: a tall floating glass capsule anchored to the bottom
//     safe area, with the transcript fading behind it
//   - user messages render as light squircle bubbles, assistant
//     responses as bare text directly on black
// `glassEffect(in:)` is the iOS 26 API; the deployment target was
// bumped to 26.0 to use it without availability noise everywhere.

struct ChatDetailView: View {
    @Bindable var store: BridgeStore
    let chatId: String
    let onBack: () -> Void
    var onOpenFile: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var composerText: String = ""
    @State private var expandedReasoning: Set<String> = []

    private var chat: WireChat? { store.chat(chatId) }
    private var messages: [WireMessage] { store.messages(for: chatId) }
    // Defensive cap: a chat with thousands of messages would spend
    // seconds laying out the LazyVStack on first scroll-to-bottom and
    // can lock the main thread during that window. Render only the
    // tail; "load older" can come later.
    private var renderedMessages: [WireMessage] {
        let cap = 250
        if messages.count <= cap { return messages }
        return Array(messages.suffix(cap))
    }
    private var hasLoaded: Bool { store.hasLoadedMessages(chatId) }

    var body: some View {
        transcript
            .background(Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
    }

    // MARK: Transcript

    private var transcript: some View {
        // Messaging-app inversion: the ScrollView is flipped on Y so
        // its layout origin lives at the visual bottom. Messages are
        // iterated newest-first and each one is flipped back so it
        // reads correctly. Result: the latest message is the first
        // item the LazyVStack lays out and it lands anchored to the
        // bottom on first paint, with zero scrollTo or anchor dance.
        // New messages prepended to the reversed array appear at the
        // visual bottom; if the user has scrolled up to read older
        // history, their content stays put.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Color.clear.frame(height: 8)
                // Gate on `hasLoaded`: while the snapshot is in flight
                // the transcript is empty (just the spacers). When the
                // snapshot lands the messages appear in a single frame,
                // already anchored to the visual bottom thanks to the
                // Y-flip. NO opacity fade and NO animation: any
                // animation here interpolates the LazyVStack's height
                // growing from ~38px to thousands, which under the
                // bottom-anchored flipped scroll reads as content
                // scrolling up from below. The user wants zero motion.
                if hasLoaded {
                    ForEach(Array(renderedMessages.reversed()), id: \.id) { msg in
                        MessageView(
                            message: msg,
                            isReasoningExpanded: expandedReasoning.contains(msg.id),
                            toggleReasoning: { toggleReasoning(messageId: msg.id) },
                            onOpenFile: onOpenFile
                        )
                        .scaleEffect(x: 1, y: -1)
                        .id(msg.id)
                    }
                }
                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, AppLayout.screenHorizontalPadding)
            // Disable any inherited implicit animation around the
            // hasLoaded -> content transition. Pinning the transaction
            // animation to nil here guarantees the snapshot arrives in
            // place without a height tween.
            .transaction { $0.animation = nil }
        }
        .scaleEffect(x: 1, y: -1)
        .scrollIndicators(.hidden)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            GlassIconButton(systemName: "chevron.left", action: handleBack)
            titlePill

            Spacer()

            if chat?.hasActiveTurn == true {
                workingPill
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            GlassIconButton(systemName: "ellipsis", action: {})
        }
        .animation(.easeOut(duration: 0.18), value: chat?.hasActiveTurn)
    }

    private func handleBack() {
        // Belt-and-braces: call the explicit pop callback first, then
        // ask SwiftUI's environment to dismiss as a fallback. Either
        // path works on iOS 26; calling both is harmless because the
        // second one is a no-op once the view is popping.
        onBack()
        dismiss()
    }

    private var titlePill: some View {
        Text(chat?.title ?? "Chat")
            .font(BodyFont.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 18)
            .frame(height: AppLayout.topBarPillHeight)
            .glassCapsule()
    }

    private var workingPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.30, green: 0.78, blue: 0.45))
                .frame(width: 7, height: 7)
            Text("Working")
                .font(BodyFont.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassCapsule()
    }

    // MARK: Bottom chrome

    private var bottomChrome: some View {
        ComposerView(text: $composerText, onSend: send)
            .padding(.bottom, 6)
            .background(
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
    }

    // MARK: Actions

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

// MARK: - Message rendering

private struct MessageView: View {
    let message: WireMessage
    let isReasoningExpanded: Bool
    let toggleReasoning: () -> Void
    var onOpenFile: (String) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantBlock
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.userBubbleText)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: AppLayout.userBubbleRadius, style: .continuous)
                        .fill(Palette.userBubbleFill)
                )
        }
    }

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Full-Mac parity: timeline interleaves reasoning chunks
            // with tool-group rows, plus the elapsed-time disclosure
            // header summarizing the whole turn. Skipped when neither
            // is present (short answers stay flat).
            if !message.timeline.isEmpty || message.workSummary != nil {
                AssistantTimelineView(
                    timeline: message.timeline,
                    workSummary: message.workSummary,
                    isStreaming: !message.streamingFinished
                )
            } else if !message.reasoningText.isEmpty {
                // Legacy path: rollouts that didn't carry a structured
                // timeline still surface their reasoning as a
                // collapsible block.
                ReasoningDisclosure(
                    text: message.reasoningText,
                    isExpanded: isReasoningExpanded,
                    toggle: toggleReasoning
                )
            }

            if !message.content.isEmpty {
                AssistantMarkdownView(text: message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !message.streamingFinished && message.timeline.isEmpty {
                Text("Thinking...")
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ChangedFilePills(timeline: message.timeline, onOpen: onOpenFile)

            if !message.streamingFinished && !message.content.isEmpty {
                StreamingDots()
            }
            if message.streamingFinished && !message.content.isEmpty {
                MessageActions(content: message.content)
                    .padding(.top, 2)
            }
        }
    }
}

private struct MessageActions: View {
    let content: String
    @State private var copied: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            copyButton
        }
    }

    private var copyButton: some View {
        Button(action: copy) {
            ZStack {
                if copied {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    CopyIconView(color: Palette.textTertiary, lineWidth: 0.85)
                        .frame(width: 14, height: 14)
                        .transition(.opacity)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #endif
        withAnimation(.easeOut(duration: 0.18)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.18)) { copied = false }
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
                        .font(BodyFont.system(size: 11, weight: .semibold))
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

#Preview("Chat detail") {
    let store = BridgeStore.mock()
    return ChatDetailView(
        store: store,
        chatId: MockData.chats[0].id,
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
