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
        return SlashCommandCatalog.filter(q)
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
                    if appState.selectedAgentRuntime == .opencode {
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
                    LucideIcon(.chevronDown, size: 11)
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

            if dictation.state == .transcribing, dictation.activeSource == .composer {
                Button {
                    dictation.cancel()
                } label: {
                    TranscribingSpinner()
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel voice transcription")
                .hoverHint(L10n.t("Cancel transcription"))
            } else {
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
            LucideIcon(.plus, size: 11)
                .foregroundColor(.white)
                .opacity(active ? 0.96 : 0.62)
                .frame(width: 28, height: 28)
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
                            LucideIcon(.chevronDown, size: 8)
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
                        localModels: localModelsService.installedModels.map { $0.name }
                    )
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
        .sheet(item: $projectEditorContext) { ctx in
            ProjectEditorSheet(context: ctx) { projectEditorContext = nil }
                .environmentObject(appState)
        }
    }
}

// MARK: - Anchor keys

private struct PlusButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct ModelButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct PermissionsButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct ProjectPickerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct ContextIndicatorAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Project picker popup

private struct ProjectPickerPopup: View {
    @Binding var isPresented: Bool
    let projects: [Project]
    let selectedId: UUID?
    let onSelect: (Project?) -> Void
    let onCreate: () -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    static let popupWidth: CGFloat = 320
    static let scrollMaxHeight: CGFloat = 220

    private var filtered: [Project] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        return projects.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                .padding(.top, MenuStyle.menuVerticalPadding + 2)
                .padding(.bottom, 4)

            scrollableList

            MenuStandardDivider()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                ProjectPickerRow(
                    label: String(localized: "Add project", bundle: AppLocale.bundle, locale: AppLocale.current),
                    iconName: "folder.badge.plus",
                    isSelected: false
                ) { onCreate() }

                ProjectPickerRow(
                    label: "No project",
                    iconName: "folder.badge.minus",
                    isSelected: selectedId == nil
                ) { onSelect(nil) }
            }
            .padding(.bottom, MenuStyle.menuVerticalPadding)
        }
        .frame(width: Self.popupWidth, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
        .onAppear {
            searchFocused = true
            DispatchQueue.main.async { searchFocused = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: MenuStyle.rowIconLabelSpacing) {
            SearchIcon(size: 11)
                .foregroundColor(MenuStyle.rowSubtle)
                .frame(width: 18, alignment: .center)
            TextField(
                "",
                text: $query,
                prompt: Text(String(localized: "Search projects", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .foregroundColor(MenuStyle.rowSubtle)
            )
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 11.5))
            .foregroundColor(MenuStyle.rowText)
            .focused($searchFocused)
            .onSubmit {
                if let first = filtered.first { onSelect(first) }
            }
        }
        .padding(.vertical, MenuStyle.rowVerticalPadding - 1)
    }

    @ViewBuilder
    private var scrollableList: some View {
        if filtered.isEmpty {
            Text(String(localized: "No matches", bundle: AppLocale.bundle, locale: AppLocale.current))
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(MenuStyle.rowSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MenuStyle.rowHorizontalPadding + 18 + MenuStyle.rowIconLabelSpacing)
                .padding(.vertical, 12)
        } else {
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { project in
                        ProjectPickerRow(
                            label: project.name,
                            iconName: "folder",
                            isSelected: selectedId == project.id
                        ) {
                            onSelect(project)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: Self.scrollMaxHeight)
        }
    }
}

private struct ProjectPickerRow: View {
    let label: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                IconImage(iconName, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Standard 1-pt divider for menu rows. Indents 14pt to mirror row padding.
struct MenuStandardDivider: View {
    var body: some View {
        Rectangle()
            .fill(MenuStyle.dividerColor)
            .frame(height: 1)
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
    }
}

// MARK: - Permissions menu popup

private struct PermissionsMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var selection: PermissionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PermissionMode.allCases) { mode in
                PermissionsMenuRow(
                    mode: mode,
                    isSelected: selection == mode
                ) {
                    selection = mode
                    isPresented = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(minWidth: 244, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

private struct PermissionsMenuRow: View {
    let mode: PermissionMode
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                LucideIcon.auto(mode.iconName, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(mode.label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Context indicator (left of the model button)

/// Small donut showing how full the active model's context window is.
/// Hover surfaces the detailed breakdown tooltip.
struct ContextIndicatorButton: View {
    let usage: ContextUsage
    @Binding var isHovering: Bool

    var body: some View {
        ContextRing(fraction: usage.usedFraction)
            .frame(width: 13, height: 13)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .anchorPreference(key: ContextIndicatorAnchorKey.self, value: .bounds) { $0 }
            .onHover { hovering in
                isHovering = hovering
            }
            .accessibilityLabel(contextA11yLabel(usage: usage))
    }
}

private struct ContextRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 2.0)
            Circle()
                .trim(from: 0, to: max(0.02, min(1.0, fraction)))
                .stroke(
                    Color(white: 0.92),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
        }
    }
}

private struct ContextTooltip: View {
    let usage: ContextUsage

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Context window:")
                .font(BodyFont.system(size: 11.5, weight: .light))
                .foregroundColor(Color(white: 0.55))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if usage.contextWindow != nil {
                Text(percentLine)
                    .font(BodyFont.system(size: 12, weight: .light))
                    .foregroundColor(Color(white: 0.94))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(tokensLine)
                .font(BodyFont.system(size: 12, weight: .light))
                .foregroundColor(Color(white: 0.94))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text("Clawix automatically compacts its context")
                .font(BodyFont.system(size: 11.5, weight: .regular))
                .foregroundColor(Color(white: 0.94))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 185)
        .menuStandardBackground()
    }

    private var percentLine: String {
        let used = Int((usage.usedFraction * 100).rounded())
        let remaining = max(0, 100 - used)
        return "\(used) % usado (\(remaining) % restante)"
    }

    private var tokensLine: String {
        let usedStr = formatTokens(usage.usedTokens)
        if let window = usage.contextWindow {
            return "\(usedStr)/\(formatTokens(window)) tokens used"
        }
        return "\(usedStr) tokens used"
    }

    private func formatTokens(_ value: Int64) -> String {
        if value < 1_000 {
            return "\(value)"
        }
        let k = Double(value) / 1_000.0
        if k < 10 {
            return String(format: "%.1f k", k)
        }
        return "\(Int(k.rounded())) k"
    }
}

private func contextA11yLabel(usage: ContextUsage) -> String {
    let used = Int((usage.usedFraction * 100).rounded())
    if usage.contextWindow == nil {
        return "Context window: \(usage.usedTokens) tokens used"
    }
    return "Context window: \(used) % used"
}

// MARK: - Model menu popup

private enum ModelSubmenu { case none, model, otherModels, speed }

private enum ModelChevronRow: Hashable { case gpt, velocidad, otrosModelos }

private struct ModelChevronAnchorsKey: PreferenceKey {
    static var defaultValue: [ModelChevronRow: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ModelChevronRow: Anchor<CGRect>],
                       nextValue: () -> [ModelChevronRow: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Collects the global window-coordinate frames of every popup column
/// currently rendered (mainColumn + any visible submenu overlays). The
/// `MenuOutsideClickWatcher` consults the union as additional "inside"
/// hit area so clicks on submenu rows propagate to SwiftUI buttons
/// instead of being swallowed as outside-clicks.
private struct PopupFramesPref: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ModelMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var runtime: AgentRuntimeChoice
    @Binding var intelligence: IntelligenceLevel
    @Binding var model: String
    @Binding var speed: SpeedLevel
    let primaryModels: [String]
    let otherModels: [String]
    let localModels: [String]

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var agentStore: AgentStore

    static let mainColumnWidth: CGFloat = 232
    private static let modelColumnWidth: CGFloat = 220
    private static let otherModelsColumnWidth: CGFloat = 200
    private static let speedColumnWidth: CGFloat = 244
    private static let columnGap: CGFloat = 6

    @State private var openSubmenu: ModelSubmenu = .none
    @State private var submenuFrames: [CGRect] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainColumn
        }
        .overlayPreferenceValue(ModelChevronAnchorsKey.self) { anchors in
            GeometryReader { proxy in
                let parentGlobalMinX = proxy.frame(in: .global).minX
                if openSubmenu == .speed, let anchor = anchors[.velocidad] {
                    let row = proxy[anchor]
                    let placement = submenuLeadingPlacement(
                        parentGlobalMinX: parentGlobalMinX,
                        row: row,
                        submenuWidth: Self.speedColumnWidth,
                        gap: Self.columnGap
                    )
                    speedColumn
                        .background(popupFrameReader)
                        .alignmentGuide(.leading) { _ in placement.offset }
                        .alignmentGuide(.top) { _ in -row.minY }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                }
                if (openSubmenu == .model || openSubmenu == .otherModels), let anchor = anchors[.gpt] {
                    let row = proxy[anchor]
                    let placement = submenuLeadingPlacement(
                        parentGlobalMinX: parentGlobalMinX,
                        row: row,
                        submenuWidth: Self.modelColumnWidth,
                        gap: Self.columnGap
                    )
                    modelSubmenuTree(parentPlacedRight: placement.placedRight)
                        .alignmentGuide(.leading) { _ in placement.offset }
                        .alignmentGuide(.top) { _ in -row.minY }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                }
            }
            .animation(.easeOut(duration: 0.18), value: openSubmenu)
        }
        .onPreferenceChange(PopupFramesPref.self) { frames in
            submenuFrames = frames
        }
        .background(
            MenuOutsideClickWatcher(
                isPresented: $isPresented,
                extraInsideTest: { [submenuFrames] point in
                    submenuFrames.contains { $0.contains(point) }
                }
            )
        )
    }

    /// `.background` content that publishes the column's global frame
    /// up to `PopupFramesPref` so the click watcher knows the submenu
    /// is still inside the popup's hit area.
    private var popupFrameReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: PopupFramesPref.self,
                value: [geo.frame(in: .global)]
            )
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            agentSection
            MenuStandardDivider()
                .padding(.vertical, 5)
            ModelMenuHeader(L10n.t("Runtime"))

            ForEach(AgentRuntimeChoice.allCases) { choice in
                ModelMenuCheckRow(
                    label: choice.label,
                    isSelected: runtime == choice
                ) {
                    runtime = choice
                    if choice == .opencode, !model.contains("/") {
                        model = AgentRuntimeChoice.defaultOpenCodeModel
                    } else if choice == .codex, model.contains("/") {
                        model = "5.5"
                    }
                    isPresented = false
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .none }
                }
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuHeader(L10n.t("Intelligence"))

            ForEach(IntelligenceLevel.allCases) { level in
                ModelMenuCheckRow(
                    label: level.label,
                    isSelected: intelligence == level
                ) {
                    intelligence = level
                    isPresented = false
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .none }
                }
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuChevronRow(
                label: runtime == .opencode ? model : "GPT-\(model)",
                highlighted: openSubmenu == .model || openSubmenu == .otherModels
            ) {
                openSubmenu = (openSubmenu == .model || openSubmenu == .otherModels) ? .none : .model
            }
            .onHover { hovering in
                if hovering, openSubmenu != .otherModels { openSubmenu = .model }
            }
            .anchorPreference(key: ModelChevronAnchorsKey.self, value: .bounds) { [.gpt: $0] }

            ModelMenuChevronRow(
                label: L10n.t("Speed"),
                highlighted: openSubmenu == .speed
            ) {
                openSubmenu = openSubmenu == .speed ? .none : .speed
            }
            .onHover { hovering in
                if hovering { openSubmenu = .speed }
            }
            .anchorPreference(key: ModelChevronAnchorsKey.self, value: .bounds) { [.velocidad: $0] }

            // Local models live inline in the main column (NOT inside a
            // submenu) so their click hit area is covered by the same
            // `MenuOutsideClickWatcher` that wraps `mainColumn`.
            // Submenu overlays sit outside the watcher's bounds; the
            // watcher consumes mouseDown there as an "outside click",
            // which would close the popup before SwiftUI's button could
            // fire and the selection would silently no-op.
            if !localModels.isEmpty {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                ModelMenuHeader(L10n.t("Local models"))
                ForEach(localModels, id: \.self) { m in
                    ModelMenuCheckRow(
                        label: m,
                        isSelected: model == "ollama:\(m)"
                    ) {
                        model = "ollama:\(m)"
                        isPresented = false
                    }
                    .onHover { hovering in
                        if hovering { openSubmenu = .none }
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.mainColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    @ViewBuilder
    private func modelSubmenuTree(parentPlacedRight: Bool) -> some View {
        modelColumn
            .background(popupFrameReader)
            .overlayPreferenceValue(ModelChevronAnchorsKey.self) { anchors in
                GeometryReader { proxy in
                    let parentGlobalMinX = proxy.frame(in: .global).minX
                    if openSubmenu == .otherModels, let anchor = anchors[.otrosModelos] {
                        let row = proxy[anchor]
                        // If the modelColumn itself was forced to flip left,
                        // keep cascading to the left so the chain stays inside
                        // the window. Otherwise prefer right and only flip
                        // when it overflows.
                        let placement: (offset: CGFloat, placedRight: Bool) = {
                            if parentPlacedRight {
                                return submenuLeadingPlacement(
                                    parentGlobalMinX: parentGlobalMinX,
                                    row: row,
                                    submenuWidth: Self.otherModelsColumnWidth,
                                    gap: Self.columnGap
                                )
                            }
                            return (-(row.minX - Self.columnGap - Self.otherModelsColumnWidth), false)
                        }()
                        otherModelsColumn
                            .background(popupFrameReader)
                            .alignmentGuide(.leading) { _ in placement.offset }
                            .alignmentGuide(.top) { _ in -row.minY }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: openSubmenu)
            }
    }

    private var modelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Model"))

            if runtime == .opencode {
                ModelMenuCheckRow(
                    label: AgentRuntimeChoice.defaultOpenCodeModel,
                    isSelected: model == AgentRuntimeChoice.defaultOpenCodeModel
                ) {
                    model = AgentRuntimeChoice.defaultOpenCodeModel
                    isPresented = false
                }
                Text("Images use a visible fallback when the model cannot read them.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(primaryModels, id: \.self) { m in
                    ModelMenuCheckRow(
                        label: "GPT-\(m)",
                        isSelected: model == m
                    ) {
                        model = m
                        isPresented = false
                    }
                    .onHover { hovering in
                        if hovering { openSubmenu = .model }
                    }
                }

                ModelMenuChevronRow(
                    label: L10n.t("Other models"),
                    highlighted: openSubmenu == .otherModels
                ) {
                    openSubmenu = openSubmenu == .otherModels ? .model : .otherModels
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .otherModels }
                }
                .anchorPreference(key: ModelChevronAnchorsKey.self, value: .bounds) { [.otrosModelos: $0] }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.modelColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    private var otherModelsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Other models"))

            ForEach(otherModels, id: \.self) { m in
                ModelMenuCheckRow(
                    label: "GPT-\(m)",
                    isSelected: model == m
                ) {
                    model = m
                    isPresented = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.otherModelsColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    private var speedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Speed"))

            ForEach(SpeedLevel.allCases) { s in
                ModelMenuDescriptionRow(
                    label: s.label,
                    description: s.description,
                    isSelected: speed == s
                ) {
                    speed = s
                    isPresented = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.speedColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    /// Top section of the model menu: lets the user pick which Agent
    /// the next composer send routes to. Selecting an agent also writes
    /// the resolved runtime + model so existing code paths that read
    /// `selectedAgentRuntime` / `selectedModel` keep working without a
    /// migration. The built-in Codex agent sits at the top of the list.
    private var agentSection: some View {
        let agents = agentStore.agents
        return VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Agent"))
            ForEach(agents) { agent in
                ModelMenuCheckRow(
                    label: agent.name,
                    isSelected: appState.selectedAgentId == agent.id
                ) {
                    appState.selectedAgentId = agent.id
                    if let mappedRuntime = AgentRuntimeChoice(rawValue: agent.runtime == .codex ? "codex" : "opencode") {
                        appState.selectedAgentRuntime = mappedRuntime
                    }
                    if !agent.model.isEmpty {
                        appState.selectedModel = agent.model
                    }
                    isPresented = false
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .none }
                }
            }
        }
    }
}

struct ModelMenuHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11))
            .foregroundColor(MenuStyle.headerText)
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }
}

private struct ModelMenuCheckRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct ModelMenuChevronRow: View {
    let label: String
    let highlighted: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                LucideIcon(.chevronRight, size: 11)
                    .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                    .foregroundColor(MenuStyle.rowSubtle)
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(
                active: highlighted || hovered,
                intensity: highlighted ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            ))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct ModelMenuDescriptionRow: View {
    let label: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(MenuStyle.rowText)
                    Text(description)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(MenuStyle.rowSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Add menu popup

private struct AddMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var planMode: Bool
    let plugins: [Plugin]
    let onPickFiles: () -> Void

    @State private var showComplementos = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            mainColumn
            if showComplementos {
                pluginsColumn
                    .transition(.softNudge(x: -4))
            }
        }
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddMenuRow(
                icon: "paperclip",
                label: L10n.t("Add photos and files"),
                trailing: nil,
                highlighted: false
            ) {
                isPresented = false
                // Defer so the menu finishes dismissing before the
                // modal NSOpenPanel takes over the run loop.
                DispatchQueue.main.async { onPickFiles() }
            }
            .onHover { hovering in
                if hovering { withAnimation(.easeOut(duration: 0.20)) { showComplementos = false } }
            }

            MenuStandardDivider()
                .padding(.vertical, 3)

            AddMenuToggleRow(icon: "checklist", label: L10n.t("Plan mode"), isOn: $planMode)
                .onHover { hovering in
                    if hovering { withAnimation(.easeOut(duration: 0.20)) { showComplementos = false } }
                }

            /*
            MenuStandardDivider()
                .padding(.vertical, 3)

            AddMenuRow(
                icon: "square.grid.2x2",
                label: "Plugins",
                trailing: "chevron.right",
                highlighted: showComplementos
            ) {
                withAnimation(.easeOut(duration: 0.20)) { showComplementos.toggle() }
            }
            .onHover { hovering in
                if hovering { withAnimation(.easeOut(duration: 0.20)) { showComplementos = true } }
            }
            */
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 186, alignment: .leading)
        .menuStandardBackground()
    }

    private var pluginsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(headerText)

            ForEach(plugins) { plugin in
                PluginRow(plugin: plugin) { isPresented = false }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 176, alignment: .leading)
        .menuStandardBackground()
    }

    private var headerText: String {
        L10n.installedPlugins(plugins.count)
    }
}

private struct AddMenuRow: View {
    let icon: String
    let label: String
    let trailing: String?
    let highlighted: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                LucideIcon.auto(icon, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if let trailing {
                    LucideIcon.auto(trailing, size: 11)
                        .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding
                                + (trailing != nil ? MenuStyle.rowTrailingIconExtra : 0))
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(
                active: highlighted || hovered,
                intensity: highlighted ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            ))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct AddMenuToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    @State private var hovered = false

    var body: some View {
        HStack(spacing: MenuStyle.rowIconLabelSpacing) {
            LucideIcon.auto(icon, size: 11)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)
            Text(label)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            CompactMenuToggle(isOn: $isOn)
        }
        .padding(.horizontal, MenuStyle.rowHorizontalPadding)
        .padding(.vertical, MenuStyle.rowVerticalPadding)
        .contentShape(Rectangle())
        .background(MenuRowHover(active: hovered))
        .onHover { hovered = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: 0.14)) { isOn.toggle() } }
    }
}

private struct PluginRow: View {
    let plugin: Plugin
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                LucideIcon.auto(plugin.iconName, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(plugin.name)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Compact menu toggle. A small dark capsule with a white knob that slides
/// from left (off) to right (on). Used inside dropdown rows where the native
/// `.switch` style would feel too tall and chunky.
struct CompactMenuToggle: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 24
    private let trackHeight: CGFloat = 14
    private let knobSize: CGFloat = 10
    private let knobInset: CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? Color(white: 0.92) : Color(white: 0.30))
            Circle()
                .fill(isOn ? Color(white: 0.18) : Color(white: 0.96))
                .frame(width: knobSize, height: knobSize)
                .offset(x: isOn ? trackWidth - knobSize - knobInset : knobInset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) { isOn.toggle() }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

// MARK: - Outside click monitor

struct MenuOutsideClickWatcher: NSViewRepresentable {
    @Binding var isPresented: Bool
    /// Optional extra hit-test, in window coordinates. Returns `true`
    /// when a point should be treated as INSIDE the popup (so the click
    /// propagates to SwiftUI instead of dismissing the menu). Used by
    /// menus whose submenu overlays render outside the watcher view's
    /// own bounds — without this their rows would silently no-op.
    var extraInsideTest: ((NSPoint) -> Bool)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = ClickWatcherView()
        view.onOutsideClick = {
            isPresented = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ClickWatcherView else { return }
        view.isMonitoring = isPresented
        view.extraInsideTest = extraInsideTest
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? ClickWatcherView)?.isMonitoring = false
    }
}

final class ClickWatcherView: NSView {
    var onOutsideClick: (() -> Void)?
    private var monitor: Any?

    /// Optional extra hit-test, in window coordinates. When present and
    /// it returns `true` for the click point, the watcher treats the
    /// click as INSIDE its popup (returns the event, skips dismiss).
    /// Used by menus whose submenu overlays sit outside the watcher's
    /// own view bounds (the model picker's GPT / Other models / Speed
    /// columns and the local-models inline list) so clicks on those
    /// submenu rows aren't swallowed by the watcher.
    var extraInsideTest: ((NSPoint) -> Bool)?

    var isMonitoring: Bool = false {
        didSet {
            guard oldValue != isMonitoring else { return }
            isMonitoring ? attach() : detach()
        }
    }

    private func attach() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let win = self.window, event.window == win else { return event }
            let pointInSelf = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(pointInSelf) { return event }
            if let extra = self.extraInsideTest, extra(event.locationInWindow) { return event }
            // Swallow the dismissal click. SwiftUI Buttons fire on mouseUp,
            // so if we let mouseDown through to a trigger that does
            // `isOpen.toggle()`, the watcher closes the menu and the
            // button reopens it on release. NSPopover/NSMenu transient
            // dismissal works the same way: the click that closes the
            // popup is consumed.
            self.onOutsideClick?()
            return nil
        }
    }

    private func detach() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit { detach() }
}

// MARK: - Popup transition

private struct PopupNudgeModifier: ViewModifier {
    let xOffset: CGFloat
    let yOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
    }
}

extension AnyTransition {
    // Asymmetric on purpose: insertion nudges from the offset to settle
    // in place, removal is fade-only. Translating on dismiss feels off,
    // especially when the click also opens a modal panel (NSOpenPanel)
    // and the user sees the row sliding down behind it.
    static func softNudge(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PopupNudgeModifier(xOffset: x, yOffset: y, opacity: 0),
                identity: PopupNudgeModifier(xOffset: 0, yOffset: 0, opacity: 1)
            ),
            removal: .opacity
        )
    }

    // Symmetric variant: removal also nudges back to the same offset while
    // fading. Use for popovers that should feel like they recede back to
    // their trigger on dismiss (no NSOpenPanel risk).
    static func softNudgeSymmetric(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        .modifier(
            active: PopupNudgeModifier(xOffset: x, yOffset: y, opacity: 0),
            identity: PopupNudgeModifier(xOffset: 0, yOffset: 0, opacity: 1)
        )
    }
}

// MARK: - Voice recording: transcribing spinner

/// Tiny indeterminate spinner that takes the mic button's slot while the
/// recorded clip is being transcribed. Visual language matches
/// `SidebarChatRowSpinner` (track + slow 2.4s rotation, ~0.79 arc) so
/// every "in flight" indicator across the app reads as the same family.
struct TranscribingSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.28),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .trim(from: 0.0, to: 0.79)
                .stroke(Color(white: 0.75),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Composer text editor (Enter sends, Shift/Opt+Enter inserts a newline)

final class ComposerNSTextView: NSTextView {
    var trailingInset: CGFloat = 14
    /// Set to true when the editor should grab keyboard focus the next
    /// time it gets attached to a window. SwiftUI's `@FocusState` does
    /// not cross the NSViewRepresentable boundary, so this is how the
    /// composer auto-focuses on home / new chat.
    var wantsInitialFocus: Bool = false

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        pruneFileDragTypes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        pruneFileDragTypes()
    }

    /// NSTextView registers file URL drag types by default so dropping a
    /// file onto the editor inserts its path as text. That hijacks file
    /// drops away from the panel-wide `BodyDropOverlay`: when the cursor
    /// crosses the input, the text view wins the drag dispatch and the
    /// drop overlay disappears. The user expects drops over the input to
    /// behave exactly like drops over the main area, so we strip file URL
    /// types here and let the body overlay handle them.
    private func pruneFileDragTypes() {
        let blocked: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        let kept = registeredDraggedTypes.filter { !blocked.contains($0) }
        unregisterDraggedTypes()
        if !kept.isEmpty {
            registerForDraggedTypes(kept)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var thin = rect
        thin.size.width = 1
        thin.size.height = max(0, rect.size.height - 4)
        thin.origin.y = rect.origin.y + 2
        super.drawInsertionPoint(in: thin, color: color, turnedOn: flag)
    }

    override var rangeForUserCompletion: NSRange { NSRange(location: NSNotFound, length: 0) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsInitialFocus, let window else { return }
        wantsInitialFocus = false
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let container = self.textContainer else { return }
        let targetWidth = max(0, newSize.width - trailingInset)
        if abs(container.containerSize.width - targetWidth) > 0.5 {
            container.containerSize = NSSize(width: targetWidth,
                                             height: CGFloat.greatestFiniteMagnitude)
        }
    }
}

struct ComposerTextEditor: NSViewRepresentable, Equatable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    /// Whether to grab keyboard focus the first time the view mounts.
    var autofocus: Bool = false
    /// Monotonic counter. When it changes, the editor is forced back to
    /// first responder. Used for "⌘N from home" and chat switching where
    /// the same editor instance stays mounted.
    var focusToken: Int = 0
    var onSubmit: () -> Void
    /// Fires when the user presses ⇧⇥ inside the editor. The composer
    /// uses this to toggle plan mode without leaving the keyboard.
    var onShiftTab: (() -> Void)? = nil

    // Equatable on the inputs that actually affect the visible state
    // of the wrapped NSTextView. The closures (`onSubmit`, `onShiftTab`)
    // are recreated on every parent body eval but they capture
    // EnvironmentObject references, so an older snapshot does the same
    // work as a fresher one. Bindings (`$text`, `$contentHeight`)
    // resolve back through the SwiftUI graph by stable identity so
    // skipping `updateNSView` does not strand a write path. Wrapping
    // the call site in `.equatable()` then lets SwiftUI skip the
    // updateNSView storm we get when the parent `ComposerView` body
    // re-evaluates because an unrelated environment object (auth,
    // dictation, localModelsService) ticked.
    static func == (lhs: ComposerTextEditor, rhs: ComposerTextEditor) -> Bool {
        lhs.text == rhs.text
            && lhs.autofocus == rhs.autofocus
            && lhs.focusToken == rhs.focusToken
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let bigSize = NSSize(width: CGFloat(0), height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: bigSize)
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = ComposerNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.minSize = NSSize(width: CGFloat(0), height: CGFloat(0))
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.string = text
        textView.wantsInitialFocus = autofocus
        context.coordinator.lastFocusToken = focusToken

        let scroller = ThinScroller()
        scroller.scrollerStyle = .overlay
        scrollView.verticalScroller = scroller

        scrollView.documentView = textView
        DispatchQueue.main.async { [weak textView] in
            guard let tv = textView else { return }
            context.coordinator.measure(tv)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let needsTextSync = textView.string != text
        let needsFocusSync = focusToken != context.coordinator.lastFocusToken
        guard needsTextSync || needsFocusSync else { return }
        RenderProbe.tick("ComposerTextEditor.updateNSView")
        // Only push the binding's value into the text view (and re-measure)
        // when it actually differs from what the user is currently editing.
        // Doing this unconditionally on every SwiftUI re-render forces an
        // extra `ensureLayout` pass per keystroke, which lands in the run
        // loop *between* the character insertion and the caret redraw and
        // makes typing feel laggy ("letter appears, then cursor catches up").
        if needsTextSync {
            textView.string = text
            DispatchQueue.main.async { [weak textView] in
                guard let tv = textView else { return }
                context.coordinator.measure(tv)
            }
        }
        if needsFocusSync {
            context.coordinator.lastFocusToken = focusToken
            if let composer = textView as? ComposerNSTextView {
                if composer.window != nil {
                    DispatchQueue.main.async { [weak composer] in
                        guard let composer, let window = composer.window else { return }
                        window.makeFirstResponder(composer)
                    }
                } else {
                    composer.wantsInitialFocus = true
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ComposerTextEditor
        var lastFocusToken: Int = 0
        init(_ parent: ComposerTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            measure(textView)
            // Defer the binding write to the next run-loop tick. Writing
            // synchronously fires `objectWillChange` on AppState mid-keystroke,
            // which forces SwiftUI to re-render the entire composer (toolbars,
            // attachment row, slash menu, project picker, model selector...)
            // *before* AppKit has committed the caret redraw for the inserted
            // character. The user perceives this as "the letter shows up, then
            // the cursor moves." Yielding one tick lets AppKit finish its draw
            // cycle first, then SwiftUI catches up.
            let snapshot = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != snapshot {
                    self.parent.text = snapshot
                }
            }
        }

        func measure(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset.height
            let h = ceil(used.height + inset * 2)
            if abs(parent.contentHeight - h) > 0.5 {
                parent.contentHeight = h
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(self)
                    return true
                }
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                if let onShiftTab = parent.onShiftTab {
                    onShiftTab()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Composer attachment chips

private struct ComposerAttachmentRow: View {
    let attachments: [ComposerAttachment]
    let onRemove: (UUID) -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    ComposerAttachmentChip(
                        attachment: att,
                        onRemove: { onRemove(att.id) },
                        onOpen: {
                            if att.isImage {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    appState.imagePreviewURL = att.url
                                }
                            }
                        }
                    )
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void
    let onOpen: () -> Void

    @State private var hovered = false
    @State private var removeHovered = false

    var body: some View {
        HStack(spacing: attachment.isImage ? 6 : 4) {
            iconView
            Text(attachment.filename)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.94))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(0)
            Button(action: onRemove) {
                LucideIcon(.x, size: 11)
                    .foregroundColor(Color(white: removeHovered ? 1.0 : 0.78))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0.001)
            .accessibilityLabel(L10n.t("Remove attachment"))
            .accessibilityAction(named: Text(L10n.t("Remove attachment"))) {
                onRemove()
            }
            .onHover { removeHovered = $0 }
            .help(L10n.t("Remove attachment"))
            .layoutPriority(1)
        }
        .padding(.leading, attachment.isImage ? 9 : 7)
        .padding(.trailing, hovered ? 7 : 11)
        .padding(.vertical, 5)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.03 : 0))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        )
        .animation(.easeOut(duration: 0.14), value: hovered)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { onOpen() }
        .onHover { hovered = $0 }
        .help(attachment.isImage ? L10n.t("Click to enlarge") : attachment.url.path)
    }

    @ViewBuilder
    private var iconView: some View {
        if attachment.isImage {
            ComposerAttachmentImageIcon(url: attachment.url)
        } else {
            FileChipIcon(size: 10)
                .foregroundColor(Color(white: 0.60))
                .frame(width: 18, height: 18)
        }
    }
}

private struct ComposerAttachmentImageIcon: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                FileChipIcon(size: 10)
                    .foregroundColor(Color(white: 0.60))
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .task(id: url.standardizedFileURL.path) {
            image = await Self.thumbnail(for: url)
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let cfURL = url as CFURL
            guard let source = CGImageSourceCreateWithURL(cfURL, nil) else {
                return NSImage(contentsOf: url)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
