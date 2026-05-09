import SwiftUI
import AppKit
import ClawixEngine

/// First-run voice setup. Lightweight sheet that batches the three
/// TCC permissions plus the first-model download, so a brand-new
/// user gets dictation working without hunting through Settings.
///
/// Designed to be invocable from two places:
///   * Automatically the first time the app runs after a successful
///     login, gated on `dictation.hasCompletedOnboarding`.
///   * Manually from `DictationSettingsPage` → Avanzado → "Show
///     voice setup again", which flips the flag back to false.
struct DictationOnboardingView: View {
    @Binding var isPresented: Bool
    @State private var permissions = PermissionsSnapshot()
    @State private var refreshTimer: Timer?

    @ObservedObject private var modelManager = DictationCoordinator.shared.modelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up Voice to Text")
                    .font(BodyFont.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("Dictation runs locally on your Mac. Grant the three permissions below, pick a Whisper model size, and you're ready to dictate in any app.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Permissions") {
                        OnboardingPermissionRow(
                            title: "Microphone",
                            detail: "Capture your voice to feed the local Whisper model.",
                            status: permissions.microphone,
                            request: {
                                Task {
                                    _ = await DictationPermissions.requestMicrophone()
                                    refresh()
                                }
                            },
                            openSettings: { DictationPermissions.openMicrophoneSettings() }
                        )
                        OnboardingPermissionRow(
                            title: "Accessibility",
                            detail: "Allows Clawix to paste the transcript into the focused app.",
                            status: permissions.accessibility,
                            request: {
                                DictationPermissions.requestAccessibility()
                                refresh()
                            },
                            openSettings: { DictationPermissions.openAccessibilitySettings() }
                        )
                        OnboardingPermissionRow(
                            title: "Input Monitoring",
                            detail: "Lets the global hotkey work while another app has focus.",
                            status: permissions.inputMonitoring,
                            request: {
                                DictationPermissions.requestInputMonitoring()
                                refresh()
                            },
                            openSettings: { DictationPermissions.openInputMonitoringSettings() }
                        )
                    }

                    section("Model") {
                        Text("Pick a Whisper size to start. Tiny is fast and runs anywhere; Small balances quality and disk; Large is the most accurate. You can change this later from Settings → Voice to Text.")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        OnboardingModelGrid(manager: modelManager)
                    }
                }
                .padding(20)
            }
            .thinScrollers()

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack {
                Button("Skip for now") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundColor(Palette.textSecondary)
                Spacer()
                Button("Done") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 580, height: 540)
        .background(Color(white: 0.10))
        .onAppear {
            refresh()
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refresh() {
        permissions.microphone = DictationPermissions.microphone()
        permissions.accessibility = DictationPermissions.accessibility()
        permissions.inputMonitoring = DictationPermissions.inputMonitoring()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: DictationOnboardingTrigger.completedKey)
        isPresented = false
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 700))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            content()
        }
    }

    private struct PermissionsSnapshot {
        var microphone: DictationPermissions.Status = .notDetermined
        var accessibility: DictationPermissions.Status = .notDetermined
        var inputMonitoring: DictationPermissions.Status = .notDetermined
    }
}

/// Owns the persistence flag + a public triggerIfNeeded() that the
/// app root can call after a successful login. Kept separate from the
/// view so the flag can be referenced from anywhere (Settings reset
/// button, etc.) without dragging SwiftUI in.
enum DictationOnboardingTrigger {
    static let completedKey = "dictation.hasCompletedOnboarding"

    static func reset() {
        UserDefaults.standard.set(false, forKey: completedKey)
    }

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static var shouldAutoPresent: Bool {
        guard !hasCompleted else { return false }
        let env = ProcessInfo.processInfo.environment
        return env["CLAWIX_DUMMY_MODE"] != "1" && env["CLAWIX_DISABLE_BACKEND"] != "1"
    }
}

// MARK: - Permission row

private struct OnboardingPermissionRow: View {
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
            switch status {
            case .granted:
                Text("Granted")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
            case .notDetermined:
                Button("Request", action: request)
            case .denied:
                Button("Open Settings", action: openSettings)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private var dotColor: Color {
        switch status {
        case .granted:       return Color(red: 0.27, green: 0.74, blue: 0.42)
        case .denied:        return Color(red: 0.94, green: 0.36, blue: 0.36)
        case .notDetermined: return Color(white: 0.55)
        }
    }
}

// MARK: - Model grid

private struct OnboardingModelGrid: View {
    @ObservedObject var manager: DictationModelManager

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
            spacing: 8
        ) {
            ForEach(DictationModel.allCases, id: \.self) { model in
                Button {
                    if manager.installedModels.contains(model) {
                        manager.setActive(model)
                    } else {
                        manager.download(model)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.displayName)
                                .font(BodyFont.system(size: 12.5, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                            if manager.activeModel == model {
                                Spacer()
                                LucideIcon(.circleCheck, size: 11)
                                    .foregroundColor(Color(red: 0.16, green: 0.46, blue: 0.98))
                            }
                        }
                        Text(label(for: model))
                            .font(BodyFont.system(size: 10.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(for model: DictationModel) -> String {
        let gb = String(format: "%.1f GB", Double(model.approximateBytes) / 1_000_000_000)
        if manager.installedModels.contains(model) {
            return "\(gb) · downloaded"
        }
        return "\(gb) · tap to download"
    }
}
