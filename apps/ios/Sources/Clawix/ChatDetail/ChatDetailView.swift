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
    var onOpenProject: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var composerText: String = ""
    @State private var composerAttachments: [ComposerAttachment] = []
    @State private var composerResetToken: Int = 0
    @State private var expandedReasoning: Set<String> = []
    @State private var showProjectPicker: Bool = false
    // Ids that have already been laid out at least once. Initial
    // snapshot fills this on first hasLoaded; new messages appended
    // afterwards are NOT in here on creation, so they animate in.
    @State private var alreadySeenMessageIds: Set<String> = []
    // Flips to true once the initial snapshot has been processed.
    // Until then, every row renders without an entrance animation
    // so the snapshot doesn't slide in as if the user typed it.
    @State private var didCaptureInitialSnapshot: Bool = false
    // Captured on first render: true for a newly-created conversation
    // because the FAB seeds `messagesByChat[id] = []` before this view
    // mounts, so it is already loaded and empty. Existing chats start
    // with `hasLoaded == false`, keeping autofocus limited to fresh
    // conversations.
    @State private var isFreshChat: Bool? = nil
    // Floating "scroll to bottom" affordance state. Toggled from the
    // ScrollView's geometry: shown when the user has scrolled away from
    // the tail by more than ~40pt, hidden as soon as they return.
    @State private var showScrollToBottom: Bool = false
    // Measured height of the bottom chrome (composer + its padding) so
    // the floating bubble can sit just above it without depending on a
    // hardcoded offset that drifts when the composer grows multiline.
    @State private var bottomChromeHeight: CGFloat = 0
    // Recording state. nil = composer mode; non-nil = the recording
    // overlay is up. The phase distinguishes "live capture" from the
    // post-stop transcribing animation that the mic flow runs before
    // dropping the recognised text back into the composer.
    @State private var recording: ActiveRecording? = nil
    // Token to ignore stale transcribe completions if the user
    // cancels/restarts mid-flight.
    @State private var transcriptionToken: Int = 0
    // Drives the live audio capture + on-device transcription. Owned
    // by the chat so the levels survive across the recording/paused
    // transitions and we can stop/cancel from any of the overlay
    // callbacks without re-creating the recorder.
    @StateObject private var voiceRecorder = VoiceRecorder()

    private var chat: WireChat? { store.chat(chatId) }
    private var messages: [WireMessage] { store.messages(for: chatId) }
    // Project for the open conversation, derived from the chat `cwd`.
    // nil means the title pill falls back to the chat title and does
    // not open the project picker.
    private var derivedProject: DerivedProject? {
        guard let cwd = chat?.cwd, !cwd.isEmpty else { return nil }
        return DerivedProject.from(chats: store.chats.filter { !$0.isArchived })
            .first(where: { $0.cwd == cwd })
    }
    private var allProjects: [DerivedProject] {
        DerivedProject.from(chats: store.chats.filter { !$0.isArchived })
    }
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
            .onAppear {
                if isFreshChat == nil {
                    isFreshChat = hasLoaded && messages.isEmpty
                }
            }
            .topBarBlurFade(height: 135)
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
            .sheet(isPresented: $showProjectPicker) {
                ProjectPickerSheet(
                    projects: allProjects,
                    currentCwd: chat?.cwd ?? "",
                    onSelect: { selected in
                        showProjectPicker = false
                        guard selected.cwd != chat?.cwd else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onOpenProject(selected.cwd)
                        }
                    },
                    onDismiss: { showProjectPicker = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.background)
                .preferredColorScheme(.dark)
            }
    }

    // MARK: Transcript

    private var transcript: some View {
        // Top-anchored natural flow: oldest message at the top, newest
        // appended below. When the chat is short enough to fit, content
        // sits at the top of the viewport (which is what the user wants
        // for empty/new chats). When it overflows, ScrollViewReader
        // anchors the latest message to the bottom on initial load and
        // on every new message appended after that.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 8)
                    if hasLoaded {
                        ForEach(renderedMessages, id: \.id) { msg in
                            MessageView(
                                message: msg,
                                isReasoningExpanded: expandedReasoning.contains(msg.id),
                                toggleReasoning: { toggleReasoning(messageId: msg.id) },
                                onOpenFile: onOpenFile,
                                shouldAnimateEntrance: shouldAnimateEntrance(for: msg)
                            )
                            .id(msg.id)
                            .onAppear { alreadySeenMessageIds.insert(msg.id) }
                        }
                    }
                    Color.clear.frame(height: 30).id("transcript-bottom")
                }
                .padding(.horizontal, AppLayout.screenHorizontalPadding)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                TapGesture().onEnded {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    #endif
                }
            )
            .onChange(of: hasLoaded, initial: true) { _, loaded in
                guard loaded, !didCaptureInitialSnapshot else { return }
                didCaptureInitialSnapshot = true
                alreadySeenMessageIds.formUnion(renderedMessages.map(\.id))
                // No-op for short chats (content fits in viewport);
                // anchors the latest message to the bottom for long
                // chats so the user lands on what they were last
                // reading instead of the top of the history.
                DispatchQueue.main.async {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
            .onChange(of: renderedMessages.last?.id) { _, newId in
                guard didCaptureInitialSnapshot, newId != nil else { return }
                // No `withAnimation`: the scroll spring competed with
                // the bubble entrance in the same run loop and dropped
                // frames. Short chats make this a no-op; long chats jump
                // directly to the latest message without tweening.
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
        }
    }

    private func shouldAnimateEntrance(for message: WireMessage) -> Bool {
        // Only user-sent messages slide in from below. Assistant
        // responses surface their content via streaming and don't
        // need a bubble-level entrance.
        guard message.role == .user else { return false }
        // Initial snapshot rows must NOT animate; only messages added
        // after the snapshot was captured (i.e. ones the user just
        // sent) get the slide-up + fade-in.
        guard didCaptureInitialSnapshot else { return false }
        return !alreadySeenMessageIds.contains(message.id)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            GlassIconButton(systemName: "chevron.left", size: 42, action: handleBack)
            titlePill

            Spacer()

            if chat?.hasActiveTurn == true {
                workingPill
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            GlassIconButton(systemName: "ellipsis", size: 42, action: {})
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

    @ViewBuilder
    private var titlePill: some View {
        if let project = derivedProject {
            Button {
                Haptics.tap()
                showProjectPicker = true
            } label: {
                HStack(spacing: 8) {
                    FolderClosedIcon(size: 17, weight: 2.1)
                        .foregroundStyle(Palette.textPrimary)
                    Text(project.name)
                        .font(BodyFont.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(BodyFont.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .glassCapsule()
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Text(chat?.title ?? "Chat")
                .font(BodyFont.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .glassCapsule()
        }
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
        ComposerView(
            text: $composerText,
            attachments: $composerAttachments,
            onSend: send,
            onMicTap: { startRecording(.transcribeToText) },
            onVoiceTap: { startRecording(.sendAsAudio) },
            autofocusOnAppear: isFreshChat ?? false,
            compact: !messages.isEmpty,
            resetToken: composerResetToken
        )
            .opacity(recording == nil ? 1 : 0)
            .allowsHitTesting(recording == nil)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)
            )
    }

    // MARK: Actions

    private func toggleReasoning(messageId: String) {
        Haptics.tap()
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
        let attachmentSnapshot = composerAttachments
        // Clear synchronously so a second tap immediately sees an empty
        // binding (canSend → false) and cannot fire a duplicate send.
        // The composer also remounts its TextField on `composerResetToken`
        // so the underlying UITextView never lingers with stale text.
        composerText = ""
        composerAttachments = []
        composerResetToken &+= 1
        // Encode JPEG bytes off-main; the bridge call back on the main
        // actor only fires once we have all the wire payloads ready.
        Task.detached(priority: .userInitiated) {
            let wire = attachmentSnapshot.compactMap { $0.wireAttachment() }
            await MainActor.run {
                store.sendPrompt(chatId: chatId, text: text, attachments: wire)
            }
        }
    }

    // MARK: Recording flow

    private func startRecording(_ purpose: RecordingOverlay.Purpose) {
        guard recording == nil else { return }
        Haptics.tap()
        voiceRecorder.start()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            recording = ActiveRecording(purpose: purpose, phase: .recording)
        }
    }

    private func cancelRecording() {
        guard recording != nil else { return }
        Haptics.tap()
        transcriptionToken &+= 1
        voiceRecorder.cancel()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = nil
        }
    }

    // Square stop button. Mic flow runs the transcription animation
    // (text lands in the composer for editing). Voice flow pauses the
    // take so the user can keep talking when they hit play, send the
    // captured audio with the up-arrow, or discard with the cancel
    // pill above the capsule.
    private func stopRecording(_ active: ActiveRecording) {
        switch active.purpose {
        case .transcribeToText:
            beginTranscribing(autoSend: false)
        case .sendAsAudio:
            pauseRecording()
        }
    }

    // Up-arrow send button. Both flows go through on-device
    // transcription; the only difference is that mic mode hands the
    // text back to the composer for editing while voice mode submits
    // it as a chat prompt straight away.
    private func sendRecording(_ active: ActiveRecording) {
        switch active.purpose {
        case .transcribeToText:
            beginTranscribing(autoSend: true)
        case .sendAsAudio:
            beginTranscribing(autoSend: true)
        }
    }

    private func pauseRecording() {
        guard var current = recording, current.phase == .recording else { return }
        voiceRecorder.pause()
        current.phase = .paused
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = current
        }
    }

    private func resumeRecording() {
        guard var current = recording, current.phase == .paused else { return }
        Haptics.tap()
        voiceRecorder.resume()
        current.phase = .recording
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = current
        }
    }

    private func beginTranscribing(autoSend: Bool) {
        guard var current = recording else { return }
        guard current.phase == .recording || current.phase == .paused else { return }
        current.phase = .transcribing
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            recording = current
        }
        transcriptionToken &+= 1
        let token = transcriptionToken
        voiceRecorder.stop { transcript in
            guard token == transcriptionToken else { return }
            guard recording?.phase == .transcribing else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if autoSend && !trimmed.isEmpty {
                composerText = trimmed
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    recording = nil
                }
                send()
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    recording = nil
                    if !trimmed.isEmpty {
                        composerText = trimmed
                    }
                }
            }
        }
    }
}

// Recording overlay state owned by the chat. Equatable so the
// `.animation(_:value:)` modifier can detect transitions cleanly.
private struct ActiveRecording: Equatable {
    var purpose: RecordingOverlay.Purpose
    var phase: RecordingOverlay.Phase
}

// MARK: - Message rendering

private struct MessageView: View {
    let message: WireMessage
    let isReasoningExpanded: Bool
    let toggleReasoning: () -> Void
    var onOpenFile: (String) -> Void = { _ in }
    var shouldAnimateEntrance: Bool = false

    var body: some View {
        if message.role == .user {
            UserBubble(text: message.content, animateEntrance: shouldAnimateEntrance)
        } else {
            assistantBlock
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
                    .tracking(-0.2)
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

// User-message bubble. Self-manages a two-track entrance animation:
// opacity ramps to 1 in ~0.18s while the offset
// translates from +50pt to 0 over ~0.42s (the visible "rises into
// place" motion). The fast opacity is intentional — by the time the
// bubble has finished translating, the fade is long since done, so
// the user only perceives a clean slide from below. Initial
// snapshot rows pass `animateEntrance: false`, which seeds the
// state to its final pose so they appear in place without motion.
private struct UserBubble: View {
    let text: String
    let animateEntrance: Bool

    @State private var fadedIn: Bool
    @State private var translatedIn: Bool

    init(text: String, animateEntrance: Bool) {
        self.text = text
        self.animateEntrance = animateEntrance
        _fadedIn = State(initialValue: !animateEntrance)
        _translatedIn = State(initialValue: !animateEntrance)
    }

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(Typography.bodyFont)
                .tracking(-0.2)
                .foregroundStyle(Palette.userBubbleText)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: AppLayout.userBubbleRadius, style: .continuous)
                        .fill(Palette.userBubbleFill)
                )
        }
        .opacity(fadedIn ? 1 : 0)
        // Large offset so the bubble visually starts from the composer
        // area and rises into place, matching familiar chat apps.
        .offset(y: translatedIn ? 0 : 320)
        // `.animation(_:value:)` ties each property to its own value
        // trigger, avoiding cross-property transactions or run-loop hops.
        .animation(.easeOut(duration: 0.08), value: fadedIn)
        // Deterministic decelerating cubic curve: starts fast, eases
        // slightly at the end, and finishes exactly at `duration` with
        // no overshoot or settle.
        .animation(.timingCurve(0.0, 0.55, 0.45, 1.0, duration: 0.32), value: translatedIn)
        .onAppear {
            guard animateEntrance else { return }
            fadedIn = true
            translatedIn = true
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
                    CopyIconView(color: Palette.textTertiary, lineWidth: 1.55)
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
        Haptics.success()
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
