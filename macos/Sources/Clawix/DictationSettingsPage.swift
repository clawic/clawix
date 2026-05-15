import SwiftUI
import ClawixEngine
import KeyboardShortcuts

/// Settings page that exposes the dictation engine: hotkey trigger
/// and behaviour, active Whisper model, language hint, paste vs
/// clipboard-only output, and the three permissions the flow needs.
///
/// Mirrors the visual language of the other Settings pages
/// (`PageHeader`, dark-fill cards with hairline strokes, dropdowns and
/// pill toggles) without depending on the file-private helpers in
/// `SettingsView.swift` — the building blocks below are local to this
/// file so the page is self-contained.
struct DictationSettingsPage: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dictation: DictationCoordinator
    @ObservedObject private var hotkey = HotkeyManagerObservable.shared
    @ObservedObject private var micPrefs = MicrophonePreferences.shared

    @AppStorage(DictationCoordinator.injectDefaultsKey) private var injectText = true
    @AppStorage(DictationCoordinator.restoreClipboardDefaultsKey) private var restoreClipboard = true
    @AppStorage(DictationCoordinator.autoSendKeyDefaultsKey) private var autoSendRaw = DictationAutoSendKey.none.rawValue
    @AppStorage(DictationCoordinator.languageDefaultsKey) private var language = "auto"
    @AppStorage(DictationCoordinator.restoreClipboardDelayMsKey) private var restoreClipboardDelayMs = 2000
    @AppStorage(DictationCoordinator.addSpaceBeforeKey) private var addSpaceBefore = true
    @AppStorage(DictationCoordinator.autoFormatParagraphsKey) private var autoFormatParagraphs = true

    @AppStorage(SoundManager.defaultsKey) private var soundFeedback = true
    @AppStorage(SoundManager.playStartKey) private var playStartSound = true
    @AppStorage(SoundManager.playStopKey) private var playStopSound = true
    @AppStorage(SoundManager.customStartURLKey) private var customStartURL = ""
    @AppStorage(SoundManager.customStopURLKey) private var customStopURL = ""

    @AppStorage(MediaController.enabledKey) private var muteAudioWhileRecording = true
    @AppStorage(MediaController.resumeDelayKey) private var muteResumeDelay = 0

    @AppStorage(PlaybackController.enabledKey) private var pauseMediaWhileRecording = false
    @AppStorage(PlaybackController.resumeDelayKey) private var pauseResumeDelay = 0

    @AppStorage(FillerWordsManager.enabledKey) private var fillerWordsEnabled = true

    @AppStorage(DictationCoordinator.prewarmOnLaunchKey) private var prewarmOnLaunch = true

    @AppStorage(DictationOverlay.styleKey) private var recorderStyle = DictationRecorderStyle.mini.rawValue

    @AppStorage(ClawixPersistentSurfaceKeys.dictationAdvancedExpanded) private var advancedExpanded = false

    @StateObject private var replacementStore = DictationReplacementStore.shared
    @StateObject private var vocabulary = VocabularyManager.shared
    @StateObject private var whisperPrompts = WhisperPromptStore.shared
    @StateObject private var powerMode = PowerModeManager.shared
    @StateObject private var promptLibrary = PromptLibrary.shared
    @StateObject private var transcripts = TranscriptionsRepository.shared

    @State private var permissions = PermissionsSnapshot()
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Voice to Text",
                subtitle: "Local on-device dictation. Press the trigger key in any app, speak, release, and the transcript is pasted at the cursor."
            )

            SectionLabel(title: "Hotkey")
            SettingsCard {
                DropdownRow(
                    title: "Trigger",
                    detail: "Bare modifier press starts dictation in any app",
                    options: DictationHotkeyTrigger.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { hotkey.trigger },
                        set: { hotkey.trigger = $0 }
                    ),
                    minWidth: 0
                )
                CardDivider()
                DropdownRow(
                    title: "Behaviour",
                    detail: "Hold to push-to-talk, tap to toggle, or both",
                    options: [
                        (DictationHotkeyMode.hybrid,     "Hybrid"),
                        (DictationHotkeyMode.pushToTalk, "Push-to-talk"),
                        (DictationHotkeyMode.toggle,     "Toggle")
                    ],
                    selection: Binding(
                        get: { hotkey.mode },
                        set: { hotkey.mode = $0 }
                    ),
                    minWidth: 0
                )
            }

            SectionLabel(title: "Audio Input")
            SettingsCard {
                MicrophoneSelectorRow(
                    micPrefs: micPrefs,
                    dictation: dictation,
                    micPermission: permissions.microphone
                )
            }

            SectionLabel(title: "Model")
            SettingsCard {
                ForEach(Array(DictationModel.allCases.enumerated()), id: \.offset) { idx, model in
                    if idx > 0 { CardDivider() }
                    DictationModelRow(
                        model: model,
                        manager: dictation.modelManager,
                        appState: appState
                    )
                }
            }

            SectionLabel(title: "Output")
            SettingsCard {
                DropdownRow(
                    title: "Language",
                    detail: "Auto-detect works for most users; force a language for proper nouns",
                    options: languageOptions,
                    selection: $language
                )
                CardDivider()
                ToggleRow(
                    title: "Paste into the focused app",
                    detail: "Off keeps the transcript on the clipboard only",
                    isOn: $injectText
                )
                CardDivider()
                ToggleRow(
                    title: "Restore previous clipboard",
                    detail: "After pasting, put the original clipboard contents back",
                    isOn: $restoreClipboard
                )
                CardDivider()
                DropdownRow(
                    title: "Auto-send after paste",
                    detail: "Submit chat-field transcripts automatically with the right shortcut for that app",
                    options: autoSendOptions,
                    selection: $autoSendRaw,
                    minWidth: 180
                )
            }

            SectionLabel(title: "Sound")
            SettingsCard {
                ToggleRow(
                    title: "Sound feedback",
                    detail: "Play short cues when recording starts and stops",
                    isOn: $soundFeedback
                )
            }

            SectionLabel(title: "While recording")
            SettingsCard {
                ToggleRow(
                    title: "Mute system audio",
                    detail: "Silences output while you dictate so video, music or alerts don't bleed into the mic",
                    isOn: $muteAudioWhileRecording
                )
            }

            SectionLabel(title: "Cleanup")
            SettingsCard {
                ToggleRow(
                    title: "Remove filler words",
                    detail: "Strip \"uh\", \"um\", \"este\", \"o sea\" and similar across multiple languages",
                    isOn: $fillerWordsEnabled
                )
            }

            SectionLabel(title: "Dictionary")
            SettingsCard {
                DictionarySummaryRow(store: replacementStore)
                CardDivider()
                VocabularyHintsRow(vocabulary: vocabulary)
            }

            DSPAdvancedSection(expanded: $advancedExpanded) {
                SectionLabel(title: "Auto-send timing")
                SettingsCard {
                    DropdownRow(
                        title: "Restore clipboard delay",
                        detail: "Wait this long after pasting before putting the original clipboard back. Slow Electron apps need 1-2 s",
                        options: restoreDelayOptions,
                        selection: $restoreClipboardDelayMs,
                        minWidth: 130
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Add space before paste",
                        detail: "If the cursor is right after a word, prepend a space so the transcript doesn't merge into it",
                        isOn: $addSpaceBefore
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Format long transcripts as paragraphs",
                        detail: "Split long pauses into paragraph breaks. Activates once the streaming model lands; toggle is honored already",
                        isOn: $autoFormatParagraphs
                    )
                }

                SectionLabel(title: "Sound (advanced)")
                SettingsCard {
                    ToggleRow(
                        title: "Play start sound",
                        detail: "Independent toggle for the start cue",
                        isOn: $playStartSound
                    )
                    CardDivider()
                    CustomSoundRow(
                        title: "Start sound file",
                        currentPath: $customStartURL
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Play stop sound",
                        detail: "Independent toggle for the stop cue",
                        isOn: $playStopSound
                    )
                    CardDivider()
                    CustomSoundRow(
                        title: "Stop sound file",
                        currentPath: $customStopURL
                    )
                }

                SectionLabel(title: "While recording (advanced)")
                SettingsCard {
                    DropdownRow(
                        title: "Mute resume delay",
                        detail: "Seconds to wait after recording stops before unmuting the system",
                        options: secondsOptions,
                        selection: $muteResumeDelay,
                        minWidth: 130
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Pause media while recording",
                        detail: "Pause Music, Spotify or Podcasts (whichever is playing) and resume only that app",
                        isOn: $pauseMediaWhileRecording
                    )
                    CardDivider()
                    DropdownRow(
                        title: "Pause resume delay",
                        detail: "Seconds before unpausing the media app after the session ends",
                        options: secondsOptions,
                        selection: $pauseResumeDelay,
                        minWidth: 130
                    )
                }

                SectionLabel(title: "Hotkey 2 (optional)")
                SettingsCard {
                    DropdownRow(
                        title: "Trigger",
                        detail: "Second modifier you can use to start dictation, with its own behaviour",
                        options: DictationHotkeyTrigger.allCases.map { ($0, $0.displayName) },
                        selection: Binding(
                            get: { hotkey.trigger2 },
                            set: { hotkey.trigger2 = $0 }
                        ),
                        minWidth: 0
                    )
                    CardDivider()
                    DropdownRow(
                        title: "Behaviour",
                        detail: "Hold to push-to-talk, tap to toggle, or both",
                        options: [
                            (DictationHotkeyMode.hybrid,     "Hybrid"),
                            (DictationHotkeyMode.pushToTalk, "Push-to-talk"),
                            (DictationHotkeyMode.toggle,     "Toggle")
                        ],
                        selection: Binding(
                            get: { hotkey.mode2 },
                            set: { hotkey.mode2 = $0 }
                        ),
                        minWidth: 0
                    )
                }

                SectionLabel(title: "Performance")
                SettingsCard {
                    ToggleRow(
                        title: "Prewarm model on launch",
                        detail: "Run a local warm-up at boot so the first dictation of the session is instant.",
                        isOn: $prewarmOnLaunch
                    )
                }

                SectionLabel(title: "Whisper prompt")
                SettingsCard {
                    WhisperPromptEditorRow(
                        store: whisperPrompts,
                        activeLanguage: language
                    )
                }

                SectionLabel(title: "Recorder style")
                SettingsCard {
                    DropdownRow(
                        title: "Pill placement",
                        detail: "Mini sits at the bottom-centre. Notch docks at the top, hugging the notch on MacBooks that have one",
                        options: DictationRecorderStyle.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: $recorderStyle,
                        minWidth: 160
                    )
                }

                SectionLabel(title: "Power Mode")
                SettingsCard {
                    PowerModeSummaryRow(manager: powerMode)
                }

                SectionLabel(title: "AI Enhancement")
                SettingsCard {
                    EnhancementSummaryRow(library: promptLibrary)
                }

                SectionLabel(title: "Transcript history")
                SettingsCard {
                    TranscriptHistorySummaryRow(repo: transcripts)
                }

                SectionLabel(title: "Audio input mode")
                SettingsCard {
                    DropdownRow(
                        title: "Mode",
                        detail: "System default uses macOS sound prefs. Custom keeps a single preferred mic. Prioritized walks an ordered list and falls back if the top one disconnects",
                        options: MicrophoneInputMode.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: Binding(
                            get: { micPrefs.mode.rawValue },
                            set: { raw in
                                if let mode = MicrophoneInputMode(rawValue: raw) {
                                    micPrefs.mode = mode
                                }
                            }
                        ),
                        minWidth: 180
                    )
                }

                SectionLabel(title: "Transcription backend")
                SettingsCard {
                    DropdownRow(
                        title: "Engine",
                        detail: "Local Whisper for highest accuracy. Apple Speech streams partials with no model download. Cloud variants need API keys (configure below)",
                        options: DictationTranscriptionBackend.allCases.map { ($0.rawValue, $0.displayName) },
                        selection: Binding(
                            get: { UserDefaults.standard.string(forKey: DictationCoordinator.backendKey) ?? DictationTranscriptionBackend.whisperLocal.rawValue },
                            set: { UserDefaults.standard.set($0, forKey: DictationCoordinator.backendKey) }
                        ),
                        minWidth: 220
                    )
                    CardDivider()
                    ToggleRow(
                        title: "Live preview while recording",
                        detail: "Show streaming partial transcripts in the floating pill. Only fires with backends that stream (Apple Speech)",
                        isOn: Binding(
                            get: { UserDefaults.standard.object(forKey: DictationCoordinator.livePreviewEnabledKey) as? Bool ?? true },
                            set: { UserDefaults.standard.set($0, forKey: DictationCoordinator.livePreviewEnabledKey) }
                        )
                    )
                    CardDivider()
                    CloudBackendsRow()
                }

                SectionLabel(title: "Quality")
                SettingsCard {
                    ToggleRow(
                        title: "Voice Activity Detection",
                        detail: "Filter silences and non-speech before transcription so Whisper doesn't hallucinate over them. Local Whisper only",
                        isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: DictationCoordinator.vadEnabledKey) },
                            set: { UserDefaults.standard.set($0, forKey: DictationCoordinator.vadEnabledKey) }
                        )
                    )
                }

                SectionLabel(title: "Voice setup")
                SettingsCard {
                    OnboardingTriggerRow()
                }

                SectionLabel(title: "Quick-action shortcuts")
                SettingsCard {
                    KeyboardShortcutsRow(
                        title: "Toggle dictation",
                        detail: "Start/stop dictation from any app",
                        name: .dictationToggle
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Cancel dictation",
                        detail: "Abandon the in-flight session without pasting",
                        name: .dictationCancel
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Paste last transcription",
                        detail: "Re-paste the most recent transcript at the cursor",
                        name: .pasteLastTranscription
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Retry last transcription",
                        detail: "Re-run the previous audio with the current model",
                        name: .retryLastTranscription
                    )
                    CardDivider()
                    KeyboardShortcutsRow(
                        title: "Toggle AI Enhancement",
                        detail: "Flip the master toggle without opening Settings",
                        name: .toggleEnhancement
                    )
                }
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                PermissionRow(
                    title: "Microphone",
                    detail: "Needed to capture your voice",
                    status: permissions.microphone,
                    request: {
                        Task { @MainActor in
                            _ = await DictationPermissions.requestMicrophone()
                            refreshPermissions()
                        }
                    },
                    openSettings: { DictationPermissions.openMicrophoneSettings() }
                )
                CardDivider()
                PermissionRow(
                    title: "Accessibility",
                    detail: "Allows Clawix to paste the transcript into the focused app",
                    status: permissions.accessibility,
                    request: {
                        DictationPermissions.requestAccessibility()
                        refreshPermissions()
                    },
                    openSettings: { DictationPermissions.openAccessibilitySettings() }
                )
                CardDivider()
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Lets the global hotkey work while another app has focus",
                    status: permissions.inputMonitoring,
                    request: {
                        DictationPermissions.requestInputMonitoring()
                        // The grant lands async; the periodic timer
                        // below picks it up and re-registers the
                        // global monitor on the next tick.
                        refreshPermissions()
                    },
                    openSettings: { DictationPermissions.openInputMonitoringSettings() }
                )
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            refreshPermissions()
            // Light periodic refresh so the user sees the green dot
            // flip the moment they grant the permission in System
            // Settings, without a restart.
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                Task { @MainActor in refreshPermissions() }
            }
            dictation.modelManager.refreshInstalled()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private var languageOptions: [(String, String)] {
        var options: [(String, String)] = [("auto", "Auto-detect")]
        for lang in AppLanguage.allCases {
            options.append((lang.whisperLanguageCode, lang.displayName))
        }
        return options
    }

    /// Picker options for the auto-send-after-paste dropdown. Stored as
    /// `DictationAutoSendKey.rawValue` so we don't need a Picker tag
    /// separate from the `@AppStorage` string.
    private var autoSendOptions: [(String, String)] {
        DictationAutoSendKey.allCases.map { ($0.rawValue, $0.displayName) }
    }

    /// Generic 0-5s picker used by the mute and pause delays.
    private var secondsOptions: [(Int, String)] {
        [(0, "0 s"), (1, "1 s"), (2, "2 s"), (3, "3 s"), (4, "4 s"), (5, "5 s")]
    }

    /// Restore-clipboard delay picker. Sub-second resolution at the
    /// short end matches the speed of native Cocoa text fields; the
    /// long tail covers slow web views.
    private var restoreDelayOptions: [(Int, String)] {
        [
            (250, "250 ms"),
            (500, "500 ms"),
            (1000, "1 s"),
            (2000, "2 s"),
            (3000, "3 s"),
            (4000, "4 s"),
            (5000, "5 s")
        ]
    }

    private func refreshPermissions() {
        let previousInputMon = permissions.inputMonitoring
        permissions.microphone = DictationPermissions.microphone()
        permissions.accessibility = DictationPermissions.accessibility()
        permissions.inputMonitoring = DictationPermissions.inputMonitoring()
        // If Input Monitoring was just granted (transition from
        // .notDetermined/.denied to .granted), re-arm the hotkey so
        // the global monitor comes online without a relaunch.
        if previousInputMon != .granted, permissions.inputMonitoring == .granted {
            HotkeyManager.shared.bootstrap(
                coordinator: DictationCoordinator.shared
            )
        }
    }

    private struct PermissionsSnapshot {
        var microphone: DictationPermissions.Status = .notDetermined
        var accessibility: DictationPermissions.Status = .notDetermined
        var inputMonitoring: DictationPermissions.Status = .notDetermined
    }
}

// MARK: - Model row

private struct DictationModelRow: View {
    let model: DictationModel
    @ObservedObject var manager: DictationModelManager
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        if manager.activeModel == model {
                            Text("Active")
                                .font(BodyFont.system(size: 10, wght: 700))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(red: 0.16, green: 0.46, blue: 0.98))
                                )
                        }
                    }
                    Text(sizeLabel)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }

                Spacer(minLength: 12)

                trailingControl
            }

            if let error = manager.downloadErrors[model] {
                Text(error)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var sizeLabel: LocalizedStringKey {
        let gb = Double(model.approximateBytes) / 1_000_000_000
        return "~\(String(format: "%.1f", gb)) GB on disk"
    }

    @ViewBuilder
    private var trailingControl: some View {
        let installed = manager.installedModels.contains(model)
        let downloading = manager.isDownloading(model)
        let deleting = manager.isDeleting(model)
        if deleting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
                Text("Deleting…")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textSecondary)
            }
        } else if downloading {
            HStack(spacing: 10) {
                DSPDownloadProgressBar(value: manager.downloadProgress[model] ?? 0)
                DSPSecondaryButton(label: "Cancel") {
                    manager.cancel(model)
                }
            }
        } else if installed {
            HStack(spacing: 8) {
                if manager.activeModel != model {
                    DSPSecondaryButton(label: "Use") {
                        manager.setActive(model)
                    }
                }
                DSPSecondaryButton(label: "Delete") {
                    requestDeleteConfirmation()
                }
            }
        } else {
            DSPSecondaryButton(label: "Download") {
                manager.download(model)
            }
        }
    }

    private func requestDeleteConfirmation() {
        let gb = String(format: "%.1f", Double(model.approximateBytes) / 1_000_000_000)
        let body = LocalizedStringKey(
            "\(model.displayName) will be removed from disk (~\(gb) GB freed). You can re-download it any time. This cannot be undone."
        )
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Delete this model?",
            body: body,
            confirmLabel: "Delete",
            isDestructive: true,
            onConfirm: { [model, manager] in
                manager.delete(model)
            }
        )
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: DictationPermissions.Status
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .granted:
            Text("Granted")
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
        case .notDetermined:
            DSPSecondaryButton(label: "Request Access", action: request)
        case .denied:
            DSPSecondaryButton(label: "Open Settings", action: openSettings)
        }
    }

    private var dotColor: Color {
        switch status {
        case .granted:       return Color(red: 0.27, green: 0.74, blue: 0.42)
        case .denied:        return Color(red: 0.94, green: 0.36, blue: 0.36)
        case .notDetermined: return Color(white: 0.55)
        }
    }
}

// MARK: - Local building blocks (page-private)

/// Capsule-on-capsule progress bar so the inner fill keeps its rounded
/// ends instead of inheriting the half-circle look the default
/// `ProgressView(value:)` falls into at low percentages on macOS.
///
/// WhisperKit's progress callback fires once per network chunk, so the
/// raw `value` lands in visible jumps. The fill width is animated with
/// an `easeInOut` curve to interpolate between those steps and keep the
/// motion continuous instead of stuttering.
private struct DSPDownloadProgressBar: View {
    let value: Double

    private let trackWidth: CGFloat = 90
    private let trackHeight: CGFloat = 7

    var body: some View {
        let clamped = min(max(value, 0), 1)
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
            Capsule(style: .continuous)
                .fill(Color.white)
                .frame(width: max(trackHeight, trackWidth * clamped))
                .opacity(clamped > 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: clamped)
        }
        .frame(width: trackWidth, height: trackHeight)
    }
}

private struct DSPSecondaryButton: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(hovered ? Color(white: 0.21) : Color(white: 0.165))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Microphone selector

/// Lists every input device Core Audio sees, with the active one
/// shown as the dropdown's current value. Selecting an entry promotes
/// it to the head of the persisted preferred list, so reconnecting
/// that device on a future launch re-binds dictation to it
/// automatically.
private struct MicrophoneSelectorRow: View {
    @ObservedObject var micPrefs: MicrophonePreferences
    @ObservedObject var dictation: DictationCoordinator
    let micPermission: DictationPermissions.Status

    @StateObject private var meter = MicLevelMeterModel()

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Microphone")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            if micPrefs.devices.isEmpty {
                Text("No input devices")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            } else {
                SettingsDropdown(
                    options: dropdownOptions,
                    selection: dropdownBinding,
                    trailingAccessory: {
                        AnyView(
                            MicLevelTinyMeter(meter: meter, active: isMeterActive)
                        )
                    }
                )
            }
        }
        .liftWhenSettingsDropdownOpen()
        .onAppear { syncCapture() }
        .onDisappear { meter.stop() }
        .onChange(of: micPrefs.activeUID) { _, _ in restartCapture() }
        .onChange(of: dictation.state) { _, _ in syncCapture() }
        .onChange(of: micPermission) { _, _ in syncCapture() }
    }

    private var isMeterActive: Bool {
        micPermission == .granted && dictation.state == .idle
    }

    private func syncCapture() {
        if isMeterActive {
            meter.start(deviceID: micPrefs.activeDeviceID())
        } else {
            meter.stop()
        }
    }

    private func restartCapture() {
        meter.stop()
        // AVAudioEngine needs the input node fully torn down before a
        // new device can be bound; 60 ms is the empirical floor that
        // avoids "device in use" on built-in mics without being
        // perceptible to the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if isMeterActive {
                meter.start(deviceID: micPrefs.activeDeviceID())
            }
        }
    }

    private var dropdownOptions: [(String, String)] {
        micPrefs.devices.map { ($0.uid, $0.name) }
    }

    private var dropdownBinding: Binding<String> {
        Binding(
            get: { micPrefs.activeUID ?? "" },
            set: { uid in
                guard !uid.isEmpty else { return }
                micPrefs.selectPreferred(uid: uid)
            }
        )
    }

    private var detailText: LocalizedStringKey {
        "Auto-switches to your last preferred mic when it reconnects; falls back to the system default otherwise"
    }
}

// MARK: - Hotkey observable wrapper

/// `HotkeyManager` keeps its mode/trigger in `UserDefaults` so the
/// daemon and the GUI can read the same source of truth, but Settings
/// needs a `@Published` surface for SwiftUI to re-render on change.
/// This thin wrapper republishes whenever the bound `@AppStorage`
/// values move.
@MainActor
final class HotkeyManagerObservable: ObservableObject {
    static let shared = HotkeyManagerObservable()

    // Slot 1
    @Published var mode: DictationHotkeyMode {
        didSet { HotkeyManager.shared.mode = mode }
    }
    @Published var trigger: DictationHotkeyTrigger {
        didSet {
            let previous = oldValue
            HotkeyManager.shared.trigger = trigger
            // When the user turns the hotkey on from Settings, drive
            // the Input Monitoring TCC flow explicitly so the consent
            // dialog appears with this Settings sheet on screen. The
            // trigger setter already retries `register()` after we
            // set it, but `register()` silently skips the global
            // monitor on `.notDetermined`/`.denied`. The explicit
            // request below is what surfaces the prompt and/or sends
            // the user to System Settings.
            if previous == .off, trigger != .off {
                HotkeyManager.shared.requestPermissionAndRegister(
                    coordinator: DictationCoordinator.shared
                )
            }
        }
    }

    // Slot 2 (optional second binding, opt-in)
    @Published var mode2: DictationHotkeyMode {
        didSet { HotkeyManager.shared.mode2 = mode2 }
    }
    @Published var trigger2: DictationHotkeyTrigger {
        didSet {
            let previous = oldValue
            HotkeyManager.shared.trigger2 = trigger2
            if previous == .off, trigger2 != .off {
                HotkeyManager.shared.requestPermissionAndRegister(
                    coordinator: DictationCoordinator.shared
                )
            }
        }
    }

    private init() {
        self.mode = HotkeyManager.shared.mode
        self.trigger = HotkeyManager.shared.trigger
        self.mode2 = HotkeyManager.shared.mode2
        self.trigger2 = HotkeyManager.shared.trigger2
    }
}

// MARK: - Dictionary section

/// One-line summary inside the Voice to Text card. Shows how many
/// replacements are configured and exposes a button that opens the
/// management sheet, so the page itself stays compact.
private struct DictionarySummaryRow: View {
    @ObservedObject var store: DictationReplacementStore
    @State private var sheetOpen: Bool = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Word replacements")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            DSPSecondaryButton(label: "Manage") { sheetOpen = true }
        }
        .sheet(isPresented: $sheetOpen) {
            DictionaryManageSheet(store: store, isPresented: $sheetOpen)
        }
    }

    private var detailText: LocalizedStringKey {
        let count = store.entries.count
        if count == 0 {
            return "Auto-fix words Whisper gets wrong. Smart-case keeps emphasis."
        }
        let active = store.entries.filter { $0.enabled }.count
        if count == active {
            return "\(count) replacements active"
        }
        return "\(active) of \(count) replacements active"
    }
}

/// Pop-up window with the full dictionary editor. Compact macOS sheet:
/// minimal header, inline add form, scrollable list, Done at the
/// bottom. The Voice to Text card itself stays a one-liner — this is
/// where the actual editing happens.
private struct DictionaryManageSheet: View {
    @ObservedObject var store: DictationReplacementStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dictionary")
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            DictionaryAddRow(store: store)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)

            if store.entries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { idx, entry in
                            if idx > 0 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: 0.5)
                                    .padding(.leading, 16)
                            }
                            DictionaryRow(entry: entry, store: store)
                        }
                    }
                }
                .thinScrollers()
            }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 540, height: 440)
        .background(Color(white: 0.10))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No replacements yet")
                .font(BodyFont.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textSecondary)
            Text("Use commas above to cover variants Whisper gets wrong.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }
}

/// Inline form to create a new replacement. Two text fields and an
/// add button. Submits on Enter from either field. Validation errors
/// surface inline for ~2.5s, then auto-clear.
private struct DictionaryAddRow: View {
    @ObservedObject var store: DictationReplacementStore
    @State private var original: String = ""
    @State private var replacement: String = ""
    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var addHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DictionaryFieldStyle(
                    placeholder: "Word Whisper gets wrong (commas for variants)",
                    text: $original,
                    onSubmit: submit
                )
                LucideIcon(.arrowRight, size: 11)
                    .foregroundColor(Palette.textSecondary)
                DictionaryFieldStyle(
                    placeholder: "Replacement",
                    text: $replacement,
                    onSubmit: submit
                )
                Button(action: submit) {
                    LucideIcon(.plus, size: 13)
                        .foregroundColor(canSubmit ? Palette.textPrimary : Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(addButtonFill))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .onHover { addHovered = $0 }
            }
            if let feedback {
                Text(feedback)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    private var addButtonFill: Color {
        if !canSubmit { return Color(white: 0.12) }
        return addHovered ? Color(white: 0.24) : Color(white: 0.18)
    }

    private var canSubmit: Bool {
        !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let result = store.add(original: original, replacement: replacement)
        switch result {
        case .success:
            original = ""
            replacement = ""
            showFeedback(nil)
        case .failure(let error):
            showFeedback(message(for: error))
        }
    }

    private func showFeedback(_ message: String?) {
        feedbackTask?.cancel()
        feedback = message
        guard message != nil else { return }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { feedback = nil }
        }
    }

    private func message(for error: DictationReplacementStore.AddError) -> String {
        switch error {
        case .emptyOriginal:
            return "Add at least one word to replace."
        case .emptyReplacement:
            return "The replacement text can't be empty."
        case .duplicateVariant(let conflict, let variant):
            return "\"\(variant)\" is already a variant of \"\(conflict)\"."
        }
    }
}

/// Single read-only row showing one replacement with toggle, edit, and
/// delete controls. The full text is displayed; long variant lists wrap
/// to a second line so the user can see exactly what is matched.
private struct DictionaryRow: View {
    let entry: DictationReplacement
    @ObservedObject var store: DictationReplacementStore
    @State private var editing: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PillToggle(isOn: Binding(
                get: { entry.enabled },
                set: { store.setEnabled(entry.id, $0) }
            ))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.original)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(entry.enabled ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    LucideIcon(.arrowRight, size: 11)
                        .foregroundColor(Palette.textSecondary)
                    Text(entry.replacement)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(entry.enabled ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)

            DictionaryIconButton(systemName: "pencil") { editing = true }
            DictionaryIconButton(systemName: "trash") { store.delete(entry.id) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(entry.enabled ? 1.0 : 0.55)
        .sheet(isPresented: $editing) {
            DictionaryEditSheet(entry: entry, store: store, isPresented: $editing)
        }
    }
}

private struct DictionaryIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 11)
                .foregroundColor(Palette.textPrimary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(hovered ? Color(white: 0.22) : Color(white: 0.14))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Modal editor for an existing entry. Same two fields as the inline
/// add row but with multi-line `TextEditor` to give breathing room for
/// long variant lists. Validates before saving and surfaces conflicts
/// inline.
private struct DictionaryEditSheet: View {
    let entry: DictationReplacement
    @ObservedObject var store: DictationReplacementStore
    @Binding var isPresented: Bool

    @State private var original: String
    @State private var replacement: String
    @State private var error: String?

    init(entry: DictationReplacement, store: DictationReplacementStore, isPresented: Binding<Bool>) {
        self.entry = entry
        self.store = store
        self._isPresented = isPresented
        self._original = State(initialValue: entry.original)
        self._replacement = State(initialValue: entry.replacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit replacement")
                .font(BodyFont.system(size: 16, wght: 700))
                .foregroundColor(Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Words Whisper gets wrong")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                DictionaryEditorBox(text: $original, minHeight: 70)
                Text("Separate variants with commas, e.g. \"Super base, Supabase, Superbase\".")
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Replacement")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                DictionaryEditorBox(text: $replacement, minHeight: 50)
            }

            if let error {
                Text(error)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .background(Color(white: 0.10))
    }

    private var canSave: Bool {
        !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        var draft = entry
        draft.original = original
        draft.replacement = replacement
        switch store.update(draft) {
        case .success:
            isPresented = false
        case .failure(.emptyOriginal):
            error = "Add at least one word to replace."
        case .failure(.emptyReplacement):
            error = "The replacement text can't be empty."
        case .failure(.duplicateVariant(let conflict, let variant)):
            error = "\"\(variant)\" is already a variant of \"\(conflict)\"."
        }
    }
}

private struct DictionaryEditorBox: View {
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(BodyFont.system(size: 12.5, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
    }
}

private struct DictionaryFieldStyle: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .onSubmit(onSubmit)
    }
}

// MARK: - Cloud backends row

private struct CloudBackendsRow: View {
    @State private var sheetOpen = false
    @State private var configuredCount: Int = 0
    @ObservedObject private var vault: SecretsManager = .shared

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cloud backend keys")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Button {
                sheetOpen = true
            } label: {
                Text("Configure")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.165)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $sheetOpen) {
            CloudBackendsSheet(isPresented: $sheetOpen)
        }
        .task(id: vault.state) { await refreshConfigured() }
    }

    private var detail: LocalizedStringKey {
        if vault.state != .unlocked {
            return "Secrets locked. Unlock to manage cloud backend keys."
        }
        if configuredCount == 0 {
            return "Add Groq / Deepgram / Custom Whisper keys to use the cloud backends."
        }
        return "\(configuredCount) backend\(configuredCount == 1 ? "" : "s") configured."
    }

    private func refreshConfigured() async {
        let groq = await CloudTranscriptionSecrets.hasAPIKey(for: .groq)
        let deepgram = await CloudTranscriptionSecrets.hasAPIKey(for: .deepgram)
        let custom = await CloudTranscriptionSecrets.hasAPIKey(for: .custom)
        configuredCount = [groq, deepgram, custom].filter { $0 }.count
    }
}

// MARK: - KeyboardShortcuts recorder row

/// Wraps the framework's `KeyboardShortcuts.Recorder` in the page's
/// row chrome so the picker reads the same as every other row in
/// Settings. Recording starts on click; clearing happens via the
/// little reset button the framework already provides inside the
/// recorder.
private struct KeyboardShortcutsRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let name: KeyboardShortcuts.Name

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}

// MARK: - Onboarding trigger row

/// One-row entry in Avanzado that launches `DictationOnboardingView`
/// on demand. Same view that #28 will auto-present after login lands;
/// for now users discover it from Settings.
private struct OnboardingTriggerRow: View {
    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Voice setup walk-through")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text("Re-run the first-time setup: permissions checklist + model download in one screen.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Button {
                DictationOnboardingTrigger.reset()
                sheetOpen = true
            } label: {
                Text("Show")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.165)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $sheetOpen) {
            DictationOnboardingView(isPresented: $sheetOpen)
        }
    }
}

// MARK: - Avanzados disclosure

/// Collapsible disclosure that hides advanced controls behind a single
/// "Avanzado" trigger row. Persistent expansion state is owned by the
/// parent page (via `@Binding`) and stored in UserDefaults so the
/// section stays open across launches if the user opted in.
///
/// Reuses the page's section/card styling so collapsed it reads as a
/// single subtle row, and expanded the children look indistinguishable
/// from the always-visible sections above.
private struct DSPAdvancedSection<Content: View>: View {
    @Binding var expanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    LucideIcon(.chevronRight, size: 11)
                        .foregroundColor(Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Advanced")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
            .padding(.bottom, expanded ? 0 : 10)

            if expanded {
                content
            }
        }
    }

    private func toggle() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            expanded.toggle()
        }
    }
}

// MARK: - Custom sound picker row

/// Row for choosing / previewing / resetting one of the custom
/// dictation sounds. The bound `currentPath` is the absolute filesystem
/// path of the user-installed file, or "" if the bundled default
/// should be used.
private struct CustomSoundRow: View {
    let title: LocalizedStringKey
    @Binding var currentPath: String
    @State private var error: String?

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error {
                    Text(error)
                        .font(BodyFont.system(size: 10.5, wght: 500))
                        .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } trailing: {
            HStack(spacing: 8) {
                CustomSoundIconButton(systemName: "play.fill", action: preview)
                    .disabled(!hasPlayable)
                CustomSoundIconButton(systemName: "folder", action: choose)
                if !currentPath.isEmpty {
                    CustomSoundIconButton(systemName: "arrow.uturn.backward", action: reset)
                }
            }
        }
    }

    private var hasPlayable: Bool {
        if currentPath.isEmpty { return true }
        return FileManager.default.fileExists(atPath: currentPath)
    }

    private var detailText: LocalizedStringKey {
        if currentPath.isEmpty { return "Default" }
        let url = URL(fileURLWithPath: currentPath)
        return LocalizedStringKey(url.lastPathComponent)
    }

    private func preview() {
        let url: URL
        if currentPath.isEmpty {
            // Try bundle URL — preview should mirror what plays during
            // recording.
            return
        } else {
            url = URL(fileURLWithPath: currentPath)
        }
        SoundManager.shared.preview(url: url)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose dictation sound"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        switch SoundManager.validate(url: chosen) {
        case .success:
            do {
                let installed = try CustomSoundLibrary.install(chosen)
                if !currentPath.isEmpty {
                    CustomSoundLibrary.remove(at: currentPath)
                }
                currentPath = installed.path
                error = nil
            } catch {
                self.error = "Couldn't install file: \(error.localizedDescription)"
            }
        case .failure(let validationError):
            self.error = validationError.localizedDescription
        }
    }

    private func reset() {
        if !currentPath.isEmpty {
            CustomSoundLibrary.remove(at: currentPath)
            currentPath = ""
        }
        error = nil
    }
}

private struct CustomSoundIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 11)
                .foregroundColor(isEnabled ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(hovered && isEnabled ? Color(white: 0.22) : Color(white: 0.14))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Vocabulary hints row + sheet

/// Compact one-line row that shows the vocabulary count and opens
/// a sheet for editing. Vocabulary boosts proper nouns in the
/// transcription model itself (Whisper's `initial_prompt`) — orthogonal
/// to the post-processing word replacements stored next to it.
private struct VocabularyHintsRow: View {
    @ObservedObject var vocabulary: VocabularyManager
    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vocabulary")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            DSPSecondaryButton(label: "Manage") { sheetOpen = true }
        }
        .sheet(isPresented: $sheetOpen) {
            VocabularySheet(vocabulary: vocabulary, isPresented: $sheetOpen)
        }
    }

    private var detail: LocalizedStringKey {
        let count = vocabulary.entries.count
        if count == 0 {
            return "Add proper nouns and jargon Whisper should bias toward."
        }
        return "\(count) terms boosted"
    }
}

private struct VocabularySheet: View {
    @ObservedObject var vocabulary: VocabularyManager
    @Binding var isPresented: Bool
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vocabulary boost")
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Text("Whisper sees these as part of the initial prompt, biasing decoding toward them. ~244 token limit.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                TextField("Add a term", text: $draft)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .onSubmit(submit)
                Button(action: submit) {
                    LucideIcon(.plus, size: 13)
                        .foregroundColor(canSubmit ? Palette.textPrimary : Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(white: 0.18)))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(vocabulary.entries.enumerated()), id: \.offset) { idx, term in
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 16)
                        }
                        HStack {
                            Text(term)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            Spacer()
                            Button {
                                vocabulary.remove(at: idx)
                            } label: {
                                LucideIcon(.trash, size: 11)
                                    .foregroundColor(Palette.textPrimary)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color(white: 0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .thinScrollers()

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 480, height: 420)
        .background(Color(white: 0.10))
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        vocabulary.add(draft)
        draft = ""
    }
}

// MARK: - Whisper prompt editor row

/// Row that exposes the per-language Whisper `initial_prompt`. Reads
/// the active language from Settings so editing always targets the
/// language the user is dictating in. "Auto-detect" maps to a special
/// "auto" key which the store applies as a global fallback.
private struct WhisperPromptEditorRow: View {
    @ObservedObject var store: WhisperPromptStore
    let activeLanguage: String
    @State private var editing: Bool = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Output style prompt")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            DSPSecondaryButton(label: "Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            WhisperPromptEditorSheet(
                store: store,
                language: activeLanguage,
                isPresented: $editing
            )
        }
    }

    private var detail: LocalizedStringKey {
        let key = activeLanguage == "auto" ? "auto" : activeLanguage
        let value = store.prompts[key] ?? ""
        if value.isEmpty {
            return "Currently using the default. Edit to bias punctuation, casing, or terminology."
        }
        return "Custom prompt active for this language."
    }
}

private struct WhisperPromptEditorSheet: View {
    @ObservedObject var store: WhisperPromptStore
    let language: String
    @Binding var isPresented: Bool
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Whisper prompt — \(language)")
                    .font(BodyFont.system(size: 14, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }

            Text("This text is sent to Whisper as `initial_prompt` and biases formatting + capitalization in the transcription. Keep it short — Whisper has a ~244-token window.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $draft)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )

            HStack {
                Button("Reset to default") {
                    store.resetToDefault(for: language)
                    draft = store.prompts[language] ?? ""
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.setPrompt(draft, for: language)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
        .background(Color(white: 0.10))
        .onAppear {
            draft = store.prompts[language] ?? ""
        }
    }
}
