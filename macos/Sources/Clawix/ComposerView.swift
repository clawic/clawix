import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ComposerView: View {
    private enum ComposerPopup {
        case add, permissions, model, project, meshTarget
    }

    var chatMode: Bool = false
    /// When non-nil, the send button routes to this chat id using the
    /// view-owned (env-injected) `composer` instance. Powers the
    /// "Open in side chat" UI: the parent ChatView passes the side
    /// chat's id and overrides the `ComposerState` env so the input
    /// state is independent of the global composer.
    var sideChatId: UUID? = nil

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var composer: ComposerState
    @EnvironmentObject private var flags: FeatureFlags
    @EnvironmentObject private var dictation: DictationCoordinator
    @StateObject private var localModelsService = LocalModelsService.shared
    @State private var sendOnStop = false
    @State private var addMenuOpen = false
    @State private var addMenuHover = false
    @State private var permissionsMenuOpen = false
    @State private var permissionsHover = false
    @State private var permissionsLinger = false
    @State private var permissionsLingerTask: Task<Void, Never>?
    @State private var modelMenuOpen = false
    @State private var contextHover = false
    @State private var micHover = false
    @State private var projectMenuOpen = false
    @State private var projectEditorContext: ProjectEditorContext?
    @State private var slashHighlightID: String? = nil
    @State private var meshTargetMenuOpen = false
    @State private var composerContentHeight: CGFloat = 52
    @State private var planSuggestionDismissed = false
    @State private var mentionFilePickerActive = false

    private let cornerRadius: CGFloat = 22
    private let projectOverlap: CGFloat = 32
    private let composerFill = Color(white: 0.135)
    private let projectFill = Color(white: 0.085)

    private let composerMinContentHeight: CGFloat = 52
    private let composerMaxContentHeight: CGFloat = 412
    private let composerVerticalPadding: CGFloat = 5

    private var composerFrameHeight: CGFloat {
        let clamped = min(composerMaxContentHeight, max(composerMinContentHeight, composerContentHeight))
        return clamped + composerVerticalPadding * 2
    }

    private func closeComposerPopups(except popup: ComposerPopup) {
        if popup != .add { addMenuOpen = false }
        if popup != .permissions { permissionsMenuOpen = false }
        if popup != .model { modelMenuOpen = false }
        if popup != .project { projectMenuOpen = false }
        if popup != .meshTarget { meshTargetMenuOpen = false }
    }

    private var placeholderText: String {
        chatMode
            ? String(localized: "Ask for follow-up changes", bundle: AppLocale.bundle, locale: AppLocale.current)
            : String(localized: "Ask Clawix anything. Type @ to mention files", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    private var slashQuery: String? {
        let text = composer.text
        guard text.hasPrefix("/") else { return nil }
        if text.contains("\n") { return nil }
        return String(text.dropFirst())
    }

    private var slashCommands: [SlashCommand] {
        guard let q = slashQuery else { return [] }
        return SlashCommandCatalog.filter(q, isVisible: flags.isVisible)
    }

    private var slashOpen: Bool { slashQuery != nil }

    /// Sends the current draft. Routes to the side-chat-aware variant
    /// when this composer drives a side chat tab, falls through to the
    /// global `sendMessage()` for the main composer. Both variants
    /// clear `composer.text` and `composer.attachments` internally,
    /// so callers don't need to.
    private func dispatchSend() {
        if let target = sideChatId {
            appState.sendMessage(forChatId: target, composer: composer)
        } else {
            appState.sendMessage()
        }
    }

    /// True when the draft contains the standalone word "plan"
    /// (case-insensitive, separated by word boundaries) so we can offer
    /// the plan-mode shortcut. We deliberately keep this English-only
    /// per spec: "plan" is the same word in EN/ES and the suggestion
    /// is intentionally a literal trigger, not localised.
    private var draftMentionsPlan: Bool {
        let text = composer.text
        guard !text.isEmpty else { return false }
        return text.range(of: #"(?i)\bplan\b"#, options: .regularExpression) != nil
    }

    private var showsPlanSuggestion: Bool {
        draftMentionsPlan
            && !appState.planMode
            && !planSuggestionDismissed
    }

    private func activatePlanModeFromSuggestion() {
        guard !appState.planMode else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            appState.togglePlanMode()
            planSuggestionDismissed = false
        }
    }

    var body: some View {
        RenderProbe.tick("ComposerView")
        return composerStack
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    if slashOpen {
                        SlashCommandMenu(
                            commands: slashCommands,
                            highlightedID: slashHighlightID ?? slashCommands.first?.id,
                            onSelect: { cmd in
                                composer.text = ""
                                slashHighlightID = nil
                                if cmd.id == "modo-plan" {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        appState.togglePlanMode()
                                    }
                                }
                            },
                            onHover: { cmd in
                                slashHighlightID = cmd.id
                            }
                        )
                        .frame(width: proxy.size.width)
                        .reportsComposerPopupRect()
                        .alignmentGuide(.top) { d in d[.bottom] + 8 }
                        .alignmentGuide(.leading) { d in d[.leading] }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(y: 4))
                    }
                }
                .allowsHitTesting(slashOpen)
            }
        .onChange(of: composer.text) {
            let ids = slashCommands.map(\.id)
            if let current = slashHighlightID, !ids.contains(current) {
                slashHighlightID = ids.first
            } else if slashHighlightID == nil {
                slashHighlightID = ids.first
            }
            if !slashOpen { slashHighlightID = nil }
        }
        .animation(.easeOut(duration: 0.20), value: slashOpen)
    }

    // MARK: - Toolbars

    private var activeTurnInChat: Bool {
        if case let .chat(id) = appState.currentRoute,
           let chat = appState.chats.first(where: { $0.id == id }) {
            return chat.hasActiveTurn
        }
        return false
    }

    /// Chat the composer is currently anchored to (used by overlays
    /// like `SkillsChipBar` that need the chat scope to resolve active
    /// skills). nil when the composer is being rendered outside a
    /// chat context (e.g. on the home view's compose-to-start surface).
    private var currentComposerChatId: UUID? {
        if case let .chat(id) = appState.currentRoute { return id }
        return nil
    }

    private var canSend: Bool {
        !composer.text.trimmingCharacters(in: .whitespaces).isEmpty
            || !composer.attachments.isEmpty
    }

    /// Default composer toolbar: + / permissions / model / mic / send.
    /// During transcription the mic button is replaced by a small spinner
    /// so the user sees that the recorded clip is being processed.
    private var normalToolbar: some View {
        HStack(spacing: 6) {
            plusButton

            if appState.planMode {
                planModePill
                    .transition(.asymmetric(
                        insertion: AnyTransition.opacity
                            .combined(with: AnyTransition.scale(scale: 0.85, anchor: .leading)),
                        removal: AnyTransition.opacity
                    ))
            }

            permissionsPill

            if chatMode, flags.isVisible(.remoteMesh) {
                MeshTargetPill(style: .toolbarCompact, menuOpen: $meshTargetMenuOpen)
            }

            Spacer()

            if let usage = appState.currentContextUsage {
                ContextIndicatorButton(
                    usage: usage,
                    isHovering: $contextHover
                )
            }

            Button {
                modelMenuOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    if flags.isVisible(.openCode), appState.selectedAgentRuntime == .opencode {
                        LucideIcon(.globe, size: 13)
                            .foregroundColor(Color(white: 0.92))
                            .accessibilityHidden(true)
                        Text(appState.openCodeModelSelection)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Color(white: 0.92))
                    } else if let local = appState.localModelName(forSelected: appState.selectedModel) {
                        LucideIcon(.laptop, size: 13)
                            .foregroundColor(Color(white: 0.92))
                            .accessibilityHidden(true)
                        Text(local)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Color(white: 0.92))
                    } else {
                        if appState.selectedSpeed == .fast {
                            LucideIcon(.zap, size: 13)
                                .foregroundColor(Color(white: 0.92))
                                .accessibilityHidden(true)
                        }
                        Text(appState.selectedModel)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Color(white: 0.92))
                        Text(appState.selectedIntelligence.label)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Color(white: 0.55))
                    }
                    LucideIcon(.chevronDown, size: 13)
                        .foregroundColor(Color(white: 0.55))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.a11yModelPicker(model: appState.selectedModel,
                                                    intelligence: appState.selectedIntelligence.label))
            .anchorPreference(key: ModelButtonAnchorKey.self, value: .bounds) { $0 }
            .hoverHint(L10n.t("Change model"))

            if flags.isVisible(.voiceToText),
               dictation.state == .transcribing,
               dictation.activeSource == .composer {
                Button {
                    dictation.cancel()
                } label: {
                    TranscribingSpinner()
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel voice transcription")
                .hoverHint(L10n.t("Cancel transcription"))
            } else if flags.isVisible(.voiceToText) {
                Button {
                    startVoice()
                } label: {
                    MicIcon(lineWidth: 1.5)
                        .foregroundColor(.white)
                        .opacity(micHover ? 0.96 : 0.62)
                        .frame(width: 20, height: 20)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { micHover = $0 }
                .animation(.easeOut(duration: 0.12), value: micHover)
                .accessibilityLabel("Start voice recording")
                .hoverHint(L10n.t("Record voice note"))
            }

            if activeTurnInChat {
                Button { appState.interruptActiveTurn() } label: {
                    StopSquircle()
                        .fill(Color(white: 0.06))
                        .frame(width: 14, height: 14)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop response")
                .hoverHint(L10n.t("Stop response"))
            } else {
                Button { dispatchSend() } label: {
                    ArrowUpIcon(size: 14)
                        .foregroundColor(canSend ? Color(white: 0.06) : Color.white.opacity(0.55))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(canSend ? Color.white : Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
                .hoverHint(L10n.t("Send message"))
            }
        }
    }

    /// Toolbar shown while a voice note is being recorded: + / waveform /
    /// elapsed timer / stop / send. Stop transcribes; send transcribes
    /// then auto-submits the resulting message.
    private var recordingToolbar: some View {
        HStack(spacing: 6) {
            plusButton

            ComposerRecordingWaveform(
                isActive: dictation.state == .recording,
                levels: dictation.barLevels
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, 4)

            Text(dictation.formattedElapsed)
                .font(BodyFont.system(size: 12.5, design: .monospaced))
                .foregroundColor(Color(white: 0.78))
                .monospacedDigit()
                .padding(.horizontal, 2)

            Button {
                stopAndAppendTranscription()
            } label: {
                StopSquircle()
                    .fill(Color(white: 0.92))
                    .frame(width: 13, height: 13)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(white: 0.22)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
            .hoverHint(L10n.t("Stop recording"))

            Button {
                stopAndSend()
            } label: {
                ArrowUpIcon(size: 14)
                    .foregroundColor(Color(white: 0.06))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send voice note")
            .hoverHint(L10n.t("Transcribe and send"))
        }
    }

    private var plusButton: some View {
        let active = addMenuOpen || addMenuHover
        return Button {
            addMenuOpen.toggle()
        } label: {
            PlusIcon(size: 24, lineWidth: 1.3)
                .foregroundColor(.white)
                .opacity(active ? 0.96 : 0.62)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.white.opacity(active ? 0.08 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { addMenuHover = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
        .accessibilityLabel(L10n.t("Add"))
        .anchorPreference(key: PlusButtonAnchorKey.self, value: .bounds) { $0 }
        .hoverHint(L10n.t("Add"))
    }

    /// Permissions selector. Collapsed state is just the mode icon at 50%
    /// white, so the toolbar reads as quiet chrome. On hover (or while the
    /// popup is open) the label + chevron animate in and the icon picks up
    /// the mode accent color, becoming a full clickable dropdown.
    private var permissionsPill: some View {
        let expanded = permissionsMenuOpen || permissionsHover || permissionsLinger
        return Button {
            permissionsMenuOpen.toggle()
        } label: {
            Group {
                if expanded {
                    HStack(spacing: 5) {
                        LucideIcon.auto(appState.permissionMode.iconName, size: 13)
                        Text(appState.permissionMode.label)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .lineLimit(1)
                        LucideIcon(.chevronDown, size: 11)
                    }
                    .foregroundColor(appState.permissionMode.accent)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.asymmetric(
                        insertion: AnyTransition.opacity
                            .combined(with: AnyTransition.offset(y: 4)),
                        removal: AnyTransition.opacity
                    ))
                } else {
                    LucideIcon.auto(appState.permissionMode.iconName, size: 13)
                        .foregroundColor(Color.white.opacity(0.5))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { permissionsHover = $0 }
        .animation(.easeOut(duration: 0.18), value: expanded)
        .accessibilityLabel(L10n.a11yChangePermissions(label: appState.permissionMode.label))
        .anchorPreference(key: PermissionsButtonAnchorKey.self, value: .bounds) { $0 }
        .hoverHint(L10n.t("Change permissions"))
        .onChange(of: appState.permissionMode) {
            permissionsLingerTask?.cancel()
            permissionsLinger = true
            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !Task.isCancelled {
                    permissionsLinger = false
                }
            }
            permissionsLingerTask = task
        }
    }

    /// Pill that mirrors the chrome of the permissions pill but renders
    /// only while plan mode is on. Tap toggles plan mode off so the user
    /// can drop back into normal execution without opening the "+" menu.
    private var planModePill: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                appState.togglePlanMode()
            }
        } label: {
            HStack(spacing: 5) {
                LucideIcon(.listChecks, size: 11)
                Text(L10n.t("Plan mode"))
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(Color(red: 0.62, green: 0.78, blue: 0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.62, green: 0.78, blue: 0.95).opacity(0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("Turn off plan mode"))
        .hoverHint(L10n.t("Turn off plan mode"))
    }

    private func startVoice() {
        // The completion fires once when transcription finishes. We
        // capture `$sendOnStop` so the same closure can implement both
        // the "stop" and "stop + send" buttons: the buttons toggle the
        // bool, the completion reads it, and we reset it on consumption.
        sendOnStop = false
        // Pass nil so the coordinator resolves the Whisper language from
        // the user's Voice-to-Text setting (auto-detect by default), the
        // same path the global hotkey already uses. Forcing the UI
        // language here translated Spanish dictation to English when the
        // app's interface was set to English.
        let pendingSend = $sendOnStop
        dictation.startFromComposer(language: nil) { text in
            appendTranscribedText(text)
            if pendingSend.wrappedValue,
               !composer.text.trimmingCharacters(in: .whitespaces).isEmpty {
                dispatchSend()
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
        if composer.text.isEmpty {
            composer.text = trimmed
        } else {
            let needsSpace = !composer.text.hasSuffix(" ")
                && !composer.text.hasSuffix("\n")
            composer.text += (needsSpace ? " " : "") + trimmed
        }
    }

    private func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("Add photos and files")
        panel.message = L10n.t("Select photos or files to attach to the chat")
        panel.prompt = L10n.t("Attach")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.20)) {
            appState.addComposerAttachments(urls)
        }
        appState.requestComposerFocus()
    }

    private var composerStack: some View {
        VStack(spacing: 8) {
            // Active skills chip row. Renders only when at least one
            // skill is active in the current chat (resolved across
            // global → project → chat). Sits above the composer so the
            // user always knows what's loading into the system prompt.
            SkillsChipBar(chatId: currentComposerChatId)

            if showsPlanSuggestion {
                PlanSuggestionBar(
                    onUsePlanMode: { activatePlanModeFromSuggestion() },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            planSuggestionDismissed = true
                        }
                    }
                )
                .padding(.horizontal, 4)
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity
                        .combined(with: AnyTransition.offset(y: 6)),
                    removal: AnyTransition.opacity
                        .combined(with: AnyTransition.offset(y: 4))
                ))
            }

            mainComposerStack
        }
        .animation(.easeOut(duration: 0.20), value: showsPlanSuggestion)
        .onChange(of: composer.text) {
            if !chatMode, composer.text == "@", !mentionFilePickerActive {
                openFilePickerFromMentionTrigger()
            }
            // Reset the user's "X" once the trigger word leaves the
            // draft, so the next time they re-type "plan" the hint
            // surfaces again.
            if !draftMentionsPlan, planSuggestionDismissed {
                planSuggestionDismissed = false
            }
        }
        .onChange(of: appState.planMode) {
            // Plan mode just turned on (via shortcut, pill, slash menu,
            // or this suggestion), so the hint has done its job.
            if appState.planMode, planSuggestionDismissed {
                planSuggestionDismissed = false
            }
        }
    }

    private func openFilePickerFromMentionTrigger() {
        mentionFilePickerActive = true
        composer.text = ""
        closeComposerPopups(except: .add)
        addMenuOpen = false
        DispatchQueue.main.async {
            presentFilePicker()
            mentionFilePickerActive = false
        }
    }

    private var mainComposerStack: some View {
        VStack(spacing: -projectOverlap) {
            VStack(spacing: 0) {
                if !composer.attachments.isEmpty {
                    ComposerAttachmentRow(
                        attachments: composer.attachments,
                        onRemove: { id in
                            withAnimation(.easeInOut(duration: 0.20)) {
                                appState.removeComposerAttachment(id: id)
                            }
                        }
                    )
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .transition(.opacity)
                }

                ZStack(alignment: .topLeading) {
                    if composer.text.isEmpty {
                        Text(placeholderText)
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(Color(white: 0.42))
                            .padding(.horizontal, 13)
                            .padding(.top, 13)
                            .allowsHitTesting(false)
                    }

                    ComposerTextEditor(
                        text: $composer.text,
                        contentHeight: $composerContentHeight,
                        autofocus: !projectMenuOpen,
                        focusToken: composer.focusToken,
                        onSubmit: { dispatchSend() },
                        onShiftTab: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                appState.togglePlanMode()
                            }
                        }
                    )
                    .equatable()
                    .padding(.horizontal, 9)
                    .padding(.vertical, composerVerticalPadding)
                    .frame(height: composerFrameHeight)
                    .accessibilityLabel("Composer text field")
                }

                Group {
                    if dictation.state == .recording, dictation.activeSource == .composer {
                        recordingToolbar
                    } else {
                        normalToolbar
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(composerFill)
            )
            .animation(.easeInOut(duration: 0.20), value: composer.attachments)
            .zIndex(1)

            if !chatMode {
                HStack(spacing: 6) {
                    Button {
                        projectMenuOpen.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            FolderClosedIcon(size: 11)
                            Text(appState.selectedProject?.name
                                 ?? String(localized: "Work on a project", bundle: AppLocale.bundle, locale: AppLocale.current))
                                .font(BodyFont.system(size: 11.5, wght: 500))
                            LucideIcon(.chevronDown, size: 11)
                        }
                        .foregroundColor(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Project picker")
                    .anchorPreference(key: ProjectPickerAnchorKey.self, value: .bounds) { $0 }

                    Spacer()

                    if flags.isVisible(.remoteMesh) {
                        MeshTargetPill(style: .projectRow, menuOpen: $meshTargetMenuOpen)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, projectOverlap + 12)
                .padding(.bottom, 12)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: cornerRadius,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(projectFill)
                )
                .zIndex(0)
            }
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
        .overlayPreferenceValue(PlusButtonAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if addMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    AddMenuPopup(
                        isPresented: $addMenuOpen,
                        planMode: $appState.planMode,
                        plugins: appState.plugins,
                        onPickFiles: { presentFilePicker() }
                    )
                    .reportsComposerPopupRect()
                    .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }
                    .alignmentGuide(.leading) { d in d[.leading] - buttonFrame.minX }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(addMenuOpen)
        }
        .overlayPreferenceValue(PermissionsButtonAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, permissionsMenuOpen {
                    let buttonFrame = proxy[anchor]
                    PermissionsMenuPopup(
                        isPresented: $permissionsMenuOpen,
                        selection: $appState.permissionMode
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .reportsComposerPopupRect()
                    .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }
                    .alignmentGuide(.leading) { d in d[.leading] - buttonFrame.minX + 6 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(permissionsMenuOpen)
        }
        .overlayPreferenceValue(ContextIndicatorAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if contextHover, let anchor, let usage = appState.currentContextUsage {
                    let buttonFrame = proxy[anchor]
                    ContextTooltip(usage: usage)
                        .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 8 }
                        .alignmentGuide(.leading) { d in
                            d[.leading] - (buttonFrame.midX - d.width / 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
        .overlayPreferenceValue(ModelButtonAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if modelMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    ModelMenuPopup(
                        isPresented: $modelMenuOpen,
                        runtime: $appState.selectedAgentRuntime,
                        intelligence: $appState.selectedIntelligence,
                        model: $appState.selectedModel,
                        speed: $appState.selectedSpeed,
                        primaryModels: appState.availableModels,
                        otherModels: appState.otherModels,
                        localModels: flags.isVisible(.localModels)
                            ? localModelsService.installedModels.map { $0.name }
                            : []
                    )
                    .reportsComposerPopupRect()
                    .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }
                    .alignmentGuide(.leading) { d in
                        d[.leading] - (buttonFrame.maxX - ModelMenuPopup.mainColumnWidth)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(modelMenuOpen)
        }
        .overlayPreferenceValue(MeshTargetAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if flags.isVisible(.remoteMesh), meshTargetMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    MeshTargetPopup(isPresented: $meshTargetMenuOpen)
                        .reportsComposerPopupRect()
                        .alignmentGuide(.top) { d in d[.bottom] - buttonFrame.minY + 6 }
                        .alignmentGuide(.leading) { d in d[.leading] - buttonFrame.minX }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(meshTargetMenuOpen)
        }
        .overlayPreferenceValue(ProjectPickerAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if projectMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let composerFrame = proxy.frame(in: .global)
                    let windowHeight = NSApp.keyWindow?.contentView?.bounds.height ?? 1000
                    let buttonGlobalMaxY = composerFrame.minY + buttonFrame.maxY
                    let buttonGlobalMinY = composerFrame.minY + buttonFrame.minY
                    let gap: CGFloat = 6
                    let safety: CGFloat = 16
                    let popupTarget: CGFloat = 320
                    let availableBelow = windowHeight - buttonGlobalMaxY - safety
                    let availableAbove = buttonGlobalMinY - safety
                    let placeBelow = availableBelow >= popupTarget || availableBelow >= availableAbove

                    ProjectPickerPopup(
                        isPresented: $projectMenuOpen,
                        projects: appState.projects,
                        selectedId: appState.selectedProject?.id,
                        onSelect: { project in
                            appState.selectedProject = project
                            projectMenuOpen = false
                        },
                        onCreate: {
                            projectMenuOpen = false
                            projectEditorContext = ProjectEditorContext(project: nil)
                        }
                    )
                    .reportsComposerPopupRect()
                    .alignmentGuide(.top) { d in
                        placeBelow
                            ? -(buttonFrame.maxY + gap)
                            : d[.bottom] - buttonFrame.minY + gap
                    }
                    .alignmentGuide(.leading) { d in d[.leading] - buttonFrame.minX }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: placeBelow ? -4 : 4))
                }
            }
            .allowsHitTesting(projectMenuOpen)
        }
        .animation(.easeOut(duration: 0.20), value: addMenuOpen)
        .animation(.easeOut(duration: 0.20), value: permissionsMenuOpen)
        .animation(.easeOut(duration: 0.20), value: modelMenuOpen)
        .animation(.easeOut(duration: 0.14), value: contextHover)
        .animation(.easeOut(duration: 0.20), value: projectMenuOpen)
        .animation(.easeOut(duration: 0.20), value: meshTargetMenuOpen)
        .onChange(of: addMenuOpen) { _, isOpen in
            if isOpen { closeComposerPopups(except: .add) }
        }
        .onChange(of: permissionsMenuOpen) { _, isOpen in
            if isOpen { closeComposerPopups(except: .permissions) }
        }
        .onChange(of: modelMenuOpen) { _, isOpen in
            if isOpen { closeComposerPopups(except: .model) }
        }
        .onChange(of: projectMenuOpen) { _, isOpen in
            if isOpen { closeComposerPopups(except: .project) }
        }
        .onChange(of: meshTargetMenuOpen) { _, isOpen in
            if isOpen { closeComposerPopups(except: .meshTarget) }
        }
        .onPreferenceChange(ComposerPopupRectsKey.self) { rects in
            ComposerCursorRectsBridge.shared.popupSwiftUIRects = rects
        }
        .sheet(item: $projectEditorContext) { ctx in
            ProjectEditorSheet(context: ctx) { projectEditorContext = nil }
                .environmentObject(appState)
        }
    }
}
