import SwiftUI
import ClawixEngine

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
    @AppStorage(DictationCoordinator.autoEnterDefaultsKey) private var autoEnter = false
    @AppStorage(DictationCoordinator.languageDefaultsKey) private var language = "auto"

    @State private var permissions = PermissionsSnapshot()
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSPHeader()

            DSPSectionLabel(title: "Hotkey")
            DSPCard {
                DSPDropdownRow(
                    title: "Trigger",
                    detail: "Bare modifier press starts dictation in any app",
                    options: DictationHotkeyTrigger.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { hotkey.trigger },
                        set: { hotkey.trigger = $0 }
                    )
                )
                DSPCardDivider()
                DSPDropdownRow(
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
                    )
                )
            }

            DSPSectionLabel(title: "Audio Input")
            DSPCard {
                MicrophoneSelectorRow(
                    micPrefs: micPrefs,
                    dictation: dictation,
                    micPermission: permissions.microphone
                )
            }

            DSPSectionLabel(title: "Model")
            DSPCard {
                ForEach(Array(DictationModel.allCases.enumerated()), id: \.offset) { idx, model in
                    if idx > 0 { DSPCardDivider() }
                    DictationModelRow(
                        model: model,
                        manager: dictation.modelManager,
                        appState: appState
                    )
                }
            }

            DSPSectionLabel(title: "Output")
            DSPCard {
                DSPDropdownRow(
                    title: "Language",
                    detail: "Auto-detect works for most users; force a language for proper nouns",
                    options: languageOptions,
                    selection: $language
                )
                DSPCardDivider()
                DSPToggleRow(
                    title: "Paste into the focused app",
                    detail: "Off keeps the transcript on the clipboard only",
                    isOn: $injectText
                )
                DSPCardDivider()
                DSPToggleRow(
                    title: "Restore previous clipboard",
                    detail: "After pasting, put the original clipboard contents back",
                    isOn: $restoreClipboard
                )
                DSPCardDivider()
                DSPToggleRow(
                    title: "Press Return after pasting",
                    detail: "Auto-submit the transcript in chat fields and forms",
                    isOn: $autoEnter
                )
            }

            DSPSectionLabel(title: "Permissions")
            DSPCard {
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
                DSPCardDivider()
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
                DSPCardDivider()
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

    private func refreshPermissions() {
        let previousInputMon = permissions.inputMonitoring
        permissions.microphone = DictationPermissions.microphone()
        permissions.accessibility = DictationPermissions.accessibility()
        permissions.inputMonitoring = DictationPermissions.inputMonitoring()
        // If Input Monitoring was just granted (transition from
        // .notDetermined/.denied to .granted), re-arm the hotkey so
        // the global monitor comes online without a relaunch.
        if previousInputMon != .granted, permissions.inputMonitoring == .granted {
            HotkeyManager.shared.bootstrapIfPermitted(
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
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textPrimary)
                        if manager.activeModel == model {
                            Text("Active")
                                .font(BodyFont.system(size: 10, weight: .semibold))
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
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }

                Spacer(minLength: 12)

                trailingControl
            }

            if let error = manager.downloadErrors[model] {
                Text("Download failed: \(error)")
                    .font(BodyFont.system(size: 11))
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
                    .font(BodyFont.system(size: 12, weight: .medium))
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
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
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
                .font(BodyFont.system(size: 11, weight: .medium))
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

private struct DSPHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Voice to Text")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Local on-device dictation. Press the trigger key in any app, speak, release, and the transcript is pasted at the cursor.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.bottom, 26)
    }
}

private struct DSPSectionLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(BodyFont.system(size: 13, weight: .medium))
            .foregroundColor(Palette.textPrimary)
            .padding(.bottom, 14)
            .padding(.top, 28)
    }
}

private struct DSPCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .liftWhenSettingsDropdownOpen()
    }
}

private struct DSPCardDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
}

private struct DSPToggleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            PillToggle(isOn: $isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct DSPDropdownRow<T: Hashable>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } trailing: {
            SettingsDropdown(
                options: options,
                selection: $selection,
                fillsWidth: true
            )
        }
        .liftWhenSettingsDropdownOpen()
    }
}

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
                .font(BodyFont.system(size: 12, weight: .medium))
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
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            if micPrefs.devices.isEmpty {
                Text("No input devices")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            } else {
                SettingsDropdown(
                    options: dropdownOptions,
                    selection: dropdownBinding,
                    trailingAccessory: {
                        AnyView(
                            MicLevelTinyMeter(meter: meter, active: isMeterActive)
                        )
                    },
                    fillsWidth: true
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

    private init() {
        self.mode = HotkeyManager.shared.mode
        self.trigger = HotkeyManager.shared.trigger
    }
}
