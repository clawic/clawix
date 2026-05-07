import SwiftUI
import AppKit

/// Floating composer rendered inside `QuickAskPanel`. Visual language
/// mirrors the macOS composer (`ComposerView`): same `MicIcon`, same
/// white-circle `arrow.up` send button, same model-pill dropdown
/// styling. Buttons that exist in the main composer (globe / context
/// indicator / paperclip / permissions) are intentionally absent here
/// because QuickAsk is a HUD-scale ask-anywhere surface, not a full
/// chat thread. The plus menu is the single entry point for
/// attachments and screen captures.
///
/// Two layout modes, driven by `controller.isExpanded`:
///   - Compact (~500x100): just the prompt field + controls row, used
///     before the user has submitted anything.
///   - Expanded (~520x540): a scrollable conversation transcript above
///     the same prompt + controls row. The input row stays anchored at
///     the bottom (the controller pins the panel's bottom-center on
///     resize) so the prompt cursor does not jump under the user.
struct QuickAskView: View {

    @ObservedObject var controller: QuickAskController

    /// QuickAsk lives in an `NSPanel`-hosted `NSHostingView`, outside the
    /// main `WindowGroup`'s environment, so `@EnvironmentObject` does
    /// not reach here. We grab the dictation singleton directly so the
    /// HUD's mic button shares the same coordinator (and state machine)
    /// as the in-app composer.
    @ObservedObject private var dictation = DictationCoordinator.shared

    @State private var prompt: String = ""
    @State private var selectedModel: QuickAskModel = .instant
    @State private var sendOnStop = false
    @State private var micHover = false
    @State private var hoveringPanel = false
    @FocusState private var inputFocused: Bool

    private let cornerRadius: CGFloat = 24

    /// The QuickAsk conversation lives inside `AppState.chats` (it is a
    /// real persisted chat, not an ephemeral HUD-only buffer). We pull
    /// the chat by id off the controller so streaming deltas the
    /// runtime emits show up inside the panel without any extra
    /// plumbing: the assistant bubble redraws as the underlying
    /// `ChatMessage.content` mutates.
    private var currentChat: Chat? {
        guard let appState = controller.appState,
              let id = controller.activeChatId
        else { return nil }
        return appState.chats.first(where: { $0.id == id })
    }

    private var visibleSize: NSSize {
        controller.isExpanded
            ? QuickAskController.expandedVisibleSize
            : QuickAskController.compactVisibleSize
    }

    var body: some View {
        ZStack {
            shape
            content
            if controller.isExpanded {
                hoverControls
                    .opacity(hoveringPanel ? 1 : 0)
                    .animation(.easeOut(duration: 0.14), value: hoveringPanel)
            }
            newConversationShortcut
        }
        // Explicit visible size so the squircle's footprint matches
        // what the controller treats as the "real" panel; the
        // surrounding `.padding(QuickAskController.shadowMargin)`
        // gives the drop shadow room to render past the squircle's
        // edge without being clipped by the NSPanel's bounds.
        .frame(width: visibleSize.width, height: visibleSize.height)
        .padding(QuickAskController.shadowMargin)
        .animation(.easeOut(duration: 0.22), value: controller.isExpanded)
        .onHover { hoveringPanel = $0 }
        .onAppear { focusInput() }
        .onReceive(NotificationCenter.default.publisher(for: QuickAskController.didShowNotification)) { _ in
            focusInput()
        }
    }

    // ⌘N starts a fresh conversation. The visible affordance is the
    // `+` button in `conversationHeader`, but that only renders in
    // expanded mode; this zero-size hidden button keeps the shortcut
    // alive in compact mode too, where pressing ⌘N just clears the
    // prompt for a clean slate.
    private var newConversationShortcut: some View {
        Button("New conversation") {
            controller.startNewConversation()
            prompt = ""
        }
        .keyboardShortcut("n", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Glass background + a solid-ish dark tint so the panel reads as a
    // panel, not a watermark. White hairline at 50% reads like the
    // bright bevel in the user's reference shot. Shadow is softer than
    // the previous pass: the user said the prior radius/opacity
    // combo was too heavy.
    private var shape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.50), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 18, x: 0, y: 8)
    }

    /// Pull the SwiftUI `@FocusState` to the text field. The two-step
    /// (`false` then `true` on the next tick) is what consistently
    /// gets the field to first-responder when the host panel is a
    /// `.nonactivatingPanel`; without the reset, SwiftUI sometimes
    /// keeps the binding "true" without actually wiring AppKit's
    /// first-responder, and the field stays unable to receive keys.
    private func focusInput() {
        inputFocused = false
        DispatchQueue.main.async { inputFocused = true }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: controller.isExpanded ? 6 : 0) {
            if controller.isExpanded {
                conversationScroll
                inputBox
            } else {
                // Placeholder anchored near the top edge, controls
                // anchored near the bottom edge. Without the explicit
                // Spacer + maxHeight the VStack would settle on its
                // natural height and the surrounding ZStack would
                // center it vertically — that's what was making the
                // controls drift toward the middle of the panel even
                // though the bottom padding was already minimal.
                promptField
                Spacer(minLength: 0)
                controlsRow
            }
        }
        .padding(.horizontal, controller.isExpanded ? 14 : 7)
        .padding(.top, controller.isExpanded ? 10 : 7)
        .padding(.bottom, controller.isExpanded ? 8.5 : 7)
        .frame(maxHeight: .infinity)
    }

    /// In expanded mode the prompt + controls row live inside their
    /// own bordered, slightly-brighter frosted box so the input reads
    /// as a discrete surface stacked under the transcript instead of
    /// floating loose at the bottom edge of the panel. Compact mode
    /// keeps the bare layout because the panel itself is the box.
    private var inputBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            promptField
            controlsRow
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            // `outer panel radius (22) - horizontal inset (14) = 8`
            // keeps the inner curve concentric with the panel edge.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }

    // MARK: - Conversation (expanded mode)

    /// Top-edge controls that ONLY appear on hover: close button on
    /// the left, new-chat (custom ComposeIcon, same shape used by the
    /// sidebar's "New chat" row) and open-in-main-app on the right.
    /// No persistent title and no permanent icons — the panel chrome
    /// stays clean until the user reaches the top edge with the
    /// pointer.
    private var hoverControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                hoverIconButton(
                    action: { controller.hide() },
                    tooltip: "Close"
                ) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(.white.opacity(0.62))
                }
                Spacer(minLength: 0)
                hoverIconButton(
                    action: {
                        controller.startNewConversation()
                        prompt = ""
                    },
                    tooltip: "New conversation (⌘N)"
                ) {
                    ComposeIcon()
                        .stroke(
                            Color.white.opacity(0.62),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 17, height: 17)
                }
                hoverIconButton(
                    action: { controller.openInMainApp() },
                    tooltip: "Open in app"
                ) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.white.opacity(0.62))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
    }

    private func hoverIconButton<Content: View>(
        action: @escaping () -> Void,
        tooltip: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    /// Scrollable transcript. We auto-scroll to the latest message id
    /// on every append AND on streaming-content mutation so the
    /// assistant reply stays in view as it types itself out. Top and
    /// bottom edges fade into the panel's dark glass per the user's
    /// "fade-edge into background" rule.
    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let chat = currentChat, let appState = controller.appState {
                        ForEach(chat.messages) { message in
                            QuickAskMessageBubble(message: message, appState: appState)
                                .id(message.id)
                        }
                    }
                    // Anchor at the very bottom so we can always scroll
                    // past the trailing message's intrinsic height when
                    // a streaming token grows it. Without this anchor
                    // ScrollViewReader sometimes settles a few points
                    // short of the real bottom on rapid deltas.
                    Color.clear.frame(height: 1).id(QuickAskScrollAnchor.bottom)
                }
                // Top padding pushes the first message past the 6%
                // top fade in the surrounding mask, so it never reads
                // as half-erased even when the transcript is short.
                .padding(.top, 36)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .onChange(of: currentChat?.messages.last?.id) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: currentChat?.messages.last?.content) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear { scrollToBottom(proxy: proxy, animated: false) }
            .onReceive(NotificationCenter.default.publisher(for: QuickAskController.didShowNotification)) { _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
        .mask(
            // Soft fade on both edges so messages dissolve into the
            // dark glass instead of slamming against an invisible
            // straight cut. 6% top / 6% bottom matches the visual
            // weight of the input row underneath.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(QuickAskScrollAnchor.bottom, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(QuickAskScrollAnchor.bottom, anchor: .bottom)
        }
    }

    // MARK: - Composer row

    private var promptField: some View {
        TextField(
            "",
            text: $prompt,
            prompt: Text("Pregunta lo que quieras")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.55))
        )
        .textFieldStyle(.plain)
        .font(BodyFont.system(size: 12, wght: 500))
        .foregroundColor(.white)
        .focused($inputFocused)
        .onSubmit(submitIfReady)
        .padding(.leading, 9)
    }

    /// Default controls row: `+` / model / mic / send. Mirrors the
    /// macOS composer layout and behaviour 1:1 — during transcription
    /// the mic slot becomes a `TranscribingSpinner`.
    private var normalControlsRow: some View {
        HStack(spacing: 8) {
            QuickAskPlusMenu()
            QuickAskModelPicker(selection: $selectedModel)
            Spacer(minLength: 0)

            if dictation.state == .transcribing, dictation.activeSource == .quickAsk {
                TranscribingSpinner()
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("Transcribing voice note")
            } else {
                micButton
            }

            sendButton
        }
    }

    /// Recording controls row: `+` / waveform / elapsed timer / stop /
    /// send. Stop just transcribes into the prompt field; send
    /// transcribes and auto-submits the resulting prompt.
    private var recordingControlsRow: some View {
        HStack(spacing: 8) {
            QuickAskPlusMenu()

            ComposerRecordingWaveform(
                isActive: dictation.state == .recording,
                levels: dictation.barLevels
            )
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .padding(.horizontal, 4)

            Text(dictation.formattedElapsed)
                .font(BodyFont.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.78))
                .monospacedDigit()
                .padding(.horizontal, 2)

            Button {
                stopAndAppendTranscription()
            } label: {
                Image(systemName: "stop.fill")
                    .font(BodyFont.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.92))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(white: 0.22)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")

            Button {
                stopAndSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(BodyFont.system(size: 15, weight: .bold))
                    .foregroundColor(Color(white: 0.06))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send voice note")
        }
    }

    @ViewBuilder
    private var controlsRow: some View {
        if dictation.state == .recording, dictation.activeSource == .quickAsk {
            recordingControlsRow
        } else {
            normalControlsRow
        }
    }

    // Same `MicIcon` and visual treatment as `ComposerView` so the
    // QuickAsk panel and the in-app composer feel like the same family.
    private var micButton: some View {
        Button {
            startVoice()
        } label: {
            MicIcon(lineWidth: 1.5)
                .foregroundColor(.white)
                .opacity(micHover ? 1.0 : 0.88)
                .frame(width: 20, height: 20)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { micHover = $0 }
        .animation(.easeOut(duration: 0.12), value: micHover)
        .accessibilityLabel("Start voice recording")
    }

    // Send button is a 1:1 copy of `ComposerView.sendButton`'s look:
    // 32pt white disc with a heavy black `arrow.up`, dimmed when the
    // input is empty.
    private var sendButton: some View {
        Button(action: submitIfReady) {
            Image(systemName: "arrow.up")
                .font(BodyFont.system(size: 17, weight: .heavy))
                .foregroundColor(canSend ? Color(white: 0.06) : Color.white.opacity(0.55))
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(canSend ? Color.white : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitIfReady() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        controller.submitPrompt(trimmed)
        prompt = ""
    }

    // MARK: - Voice recording

    /// Mirrors `ComposerView.startVoice()`. The completion fires once
    /// when transcription finishes; we re-use the same `sendOnStop`
    /// trick so a "stop" press appends the text and a "stop + send"
    /// press appends + auto-submits.
    private func startVoice() {
        sendOnStop = false
        let pendingSend = $sendOnStop
        dictation.startFromQuickAsk(language: nil) { text in
            appendTranscribedText(text)
            if pendingSend.wrappedValue,
               !prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                submitIfReady()
            }
            pendingSend.wrappedValue = false
        }
    }

    private func stopAndAppendTranscription() {
        sendOnStop = false
        dictation.stop()
    }

    private func stopAndSend() {
        sendOnStop = true
        dictation.stop()
    }

    private func appendTranscribedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if prompt.isEmpty {
            prompt = trimmed
        } else {
            let needsSpace = !prompt.hasSuffix(" ") && !prompt.hasSuffix("\n")
            prompt += (needsSpace ? " " : "") + trimmed
        }
    }
}

// MARK: - Plus menu

/// `+` button that opens an `NSMenu` covering the five attach/capture
/// actions the user listed: load file, load photo, take screenshot
/// (with a submenu of every visible screen and on-screen window),
/// take photo from camera, open application. We render through a
/// SwiftUI `Menu` rather than a custom popup panel because the system
/// menu (a) renders correctly outside the QuickAsk panel's bounds,
/// (b) handles keyboard navigation and ⌘O for free, and (c) styles
/// itself to match macOS dark mode automatically.
private struct QuickAskPlusMenu: View {
    @State private var screens: [QuickAskCaptureSource.Screen] = []
    @State private var windows: [QuickAskCaptureSource.Window] = []

    var body: some View {
        Menu {
            Button {
                QuickAskActions.loadFile()
            } label: {
                Label("Cargar archivo", systemImage: "doc")
            }

            Button {
                QuickAskActions.loadPhoto()
            } label: {
                Label("Cargar foto", systemImage: "photo")
            }

            Menu {
                if !screens.isEmpty {
                    Section("Pantallas") {
                        ForEach(screens) { screen in
                            Button {
                                QuickAskActions.captureScreen(screen)
                            } label: {
                                Label(screen.name, systemImage: "display")
                            }
                        }
                    }
                }
                if !windows.isEmpty {
                    Section("Ventanas") {
                        ForEach(windows) { window in
                            Button {
                                QuickAskActions.captureWindow(window)
                            } label: {
                                Label(window.label, systemImage: "macwindow")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    QuickAskActions.captureInteractive()
                } label: {
                    Label("Selección personalizada…", systemImage: "selection.pin.in.out")
                }
            } label: {
                Label("Hacer una captura de pantalla", systemImage: "camera.viewfinder")
            }

            Button {
                QuickAskActions.takePhoto()
            } label: {
                Label("Hacer foto", systemImage: "camera")
            }

            Divider()

            Button {
                QuickAskActions.openApplication()
            } label: {
                Label("Abrir la aplicación", systemImage: "app.badge")
            }
            .keyboardShortcut("o", modifiers: [.command])
        } label: {
            Image(systemName: "plus")
                .font(BodyFont.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .opacity(0.78)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // Refresh the screen and window inventory every time the menu
        // is about to surface so we never show a stale list (apps open
        // and close, monitors get plugged in/out).
        .onTapGesture {
            screens = QuickAskCaptureSource.currentScreens()
            windows = QuickAskCaptureSource.currentWindows()
        }
        .onAppear {
            screens = QuickAskCaptureSource.currentScreens()
            windows = QuickAskCaptureSource.currentWindows()
        }
    }
}

// MARK: - Model picker pill

/// Bare-text model picker. No leading icon, no trailing chevron — the
/// dropdown affordance is implicit, surfaced only on hover via a
/// squircle background that highlights the label as a hit target.
private struct QuickAskModelPicker: View {
    @Binding var selection: QuickAskModel
    @State private var hovered = false

    var body: some View {
        Menu {
            ForEach(QuickAskModel.allCases) { model in
                Button {
                    selection = model
                } label: {
                    if model == selection {
                        Label(model.displayName, systemImage: "checkmark")
                    } else {
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            Text(selection.displayName)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Color(white: 0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.09 : 0))
                )
                .contentShape(Rectangle())
        }
        // `.menuStyle(.button) + .buttonStyle(.plain)` suppresses the
        // system disclosure glyph SwiftUI normally injects on the
        // leading side, so the label renders as raw text only.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Models

/// Shipping list of models the QuickAsk pill exposes. Default is
/// `.instant` per the user's spec — QuickAsk is meant for tight,
/// quick prompts and Instant is the right cost/speed balance.
enum QuickAskModel: String, CaseIterable, Identifiable {
    case instant
    case fast
    case smart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instant: return "5.5 Instant"
        case .fast:    return "5.5 Fast"
        case .smart:   return "5.5 Smart"
        }
    }
}
