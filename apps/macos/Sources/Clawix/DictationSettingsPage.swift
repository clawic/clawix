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

    @EnvironmentObject private var dictation: DictationCoordinator
    @ObservedObject private var hotkey = HotkeyManagerObservable.shared
    @ObservedObject private var micPrefs = MicrophonePreferences.shared

    @AppStorage(DictationCoordinator.injectDefaultsKey) private var injectText = true
    @AppStorage(DictationCoordinator.restoreClipboardDefaultsKey) private var restoreClipboard = true
    @AppStorage("dictation.language") private var language = "auto"

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
                        (DictationHotkeyMode.hybrid,     "Hybrid (recommended)"),
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
                MicrophoneSelectorRow(micPrefs: micPrefs)
            }

            DSPSectionLabel(title: "Model")
            DSPCard {
                ForEach(Array(DictationModel.allCases.enumerated()), id: \.offset) { idx, model in
                    if idx > 0 { DSPCardDivider() }
                    DictationModelRow(model: model)
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
                    detail: "Keeps the global hotkey responsive when Clawix is in the background",
                    status: permissions.inputMonitoring,
                    request: {
                        DictationPermissions.requestInputMonitoring()
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
        permissions.microphone = DictationPermissions.microphone()
        permissions.accessibility = DictationPermissions.accessibility()
        permissions.inputMonitoring = DictationPermissions.inputMonitoring()
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
    @EnvironmentObject private var dictation: DictationCoordinator

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary)
                    if dictation.modelManager.activeModel == model {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var sizeLabel: LocalizedStringKey {
        let gb = Double(model.approximateBytes) / 1_000_000_000
        return "~\(String(format: "%.1f", gb)) GB on disk"
    }

    @ViewBuilder
    private var trailingControl: some View {
        let installed = dictation.modelManager.installedModels.contains(model)
        let downloading = dictation.modelManager.isDownloading(model)
        if downloading {
            ProgressView(value: dictation.modelManager.downloadProgress[model] ?? 0)
                .frame(width: 120)
        } else if installed {
            HStack(spacing: 8) {
                if dictation.modelManager.activeModel != model {
                    DSPSecondaryButton(label: "Use") {
                        dictation.modelManager.setActive(model)
                    }
                }
                DSPSecondaryButton(label: "Delete") {
                    dictation.modelManager.delete(model)
                }
            }
        } else {
            DSPSecondaryButton(label: "Download") {
                dictation.modelManager.download(model)
            }
        }
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
        EqualSplitRow(spacing: 14) {
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
            SettingsDropdown(
                options: options,
                selection: $selection,
                fillsWidth: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liftWhenSettingsDropdownOpen()
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

    var body: some View {
        EqualSplitRow(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Microphone")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if micPrefs.devices.isEmpty {
                Text("No input devices")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                SettingsDropdown(
                    options: dropdownOptions,
                    selection: dropdownBinding,
                    fillsWidth: true
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liftWhenSettingsDropdownOpen()
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
        didSet { HotkeyManager.shared.trigger = trigger }
    }

    private init() {
        self.mode = HotkeyManager.shared.mode
        self.trigger = HotkeyManager.shared.trigger
    }
}
