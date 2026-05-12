import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Settings page for the floating QuickAsk panel. Exposes the global
/// shortcut so the user can change it from the default ⌃⌥⌘K, plus
/// a one-tap "Open now" button to test the panel without leaving
/// Settings (handy when verifying a freshly-recorded combo).
struct QuickAskSettingsPage: View {

    @ObservedObject private var hotkeyManager = QuickAskHotkeyManager.shared
    @ObservedObject private var slashStore = QuickAskSlashCommandsStore.shared
    @ObservedObject private var mentionsStore = QuickAskMentionsStore.shared
    @ObservedObject private var flags = FeatureFlags.shared
    @EnvironmentObject private var appState: AppState
    @State private var recording = false
    @State private var advancedExpanded = false
    @State private var defaultModelSelection: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QASHeader()

            QASSectionLabel(title: "Hotkey")
            QASCard {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shortcut")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Press this combo from any app to summon the QuickAsk panel.")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    ShortcutRecorder(
                        recording: $recording,
                        hotkey: hotkeyManager.current,
                        onRecord: { hotkeyManager.update($0) }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                QASCardDivider()

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reset to default")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Restores ⌃Space, the shipped default.")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer(minLength: 12)
                    QASSecondaryButton(label: "Reset") {
                        hotkeyManager.update(.defaultValue)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            QASSectionLabel(title: "Default model")
            QASCard {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Model")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Applied every time the QuickAsk panel opens. Picker inside the HUD overrides it for the current session.")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Picker("", selection: $defaultModelSelection) {
                        Text("Follow main composer").tag("")
                        if flags.isVisible(.openCode) {
                            Text(AgentRuntimeChoice.defaultOpenCodeModel).tag(AgentRuntimeChoice.defaultOpenCodeModel)
                        }
                        ForEach(appState.availableModels + appState.otherModels, id: \.self) { m in
                            Text("GPT-\(m)").tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .onChange(of: defaultModelSelection) { newValue in
                        if newValue.contains("/"), !flags.isVisible(.openCode) {
                            defaultModelSelection = ""
                            QuickAskController.shared.quickAskDefaultModel = nil
                            return
                        }
                        QuickAskController.shared.quickAskDefaultModel =
                            newValue.isEmpty ? nil : newValue
                    }
                    .onChange(of: flags.experimental) { _, _ in
                        if defaultModelSelection.contains("/"), !flags.isVisible(.openCode) {
                            defaultModelSelection = ""
                            QuickAskController.shared.quickAskDefaultModel = nil
                        }
                    }
                    .onAppear {
                        defaultModelSelection =
                            QuickAskController.shared.quickAskDefaultModel ?? ""
                        if defaultModelSelection.contains("/"), !flags.isVisible(.openCode) {
                            defaultModelSelection = ""
                            QuickAskController.shared.quickAskDefaultModel = nil
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            QASSectionLabel(title: "Try it")
            QASCard {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open the panel now")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Same as pressing the shortcut. Empty prompts open bottom-center; active conversations reopen where you parked them.")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    QASSecondaryButton(label: "Open") {
                        QuickAskController.shared.show()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            DisclosureGroup(isExpanded: $advancedExpanded) {
                advancedContent
                    .padding(.top, 12)
            } label: {
                Text("Advanced")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
            }
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
        QASSectionLabel(title: "Slash commands")
        QASCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in: /search, /research, /imagine, /think")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                if slashStore.customCommands.isEmpty {
                    Text("No custom commands yet. Add one and use it from QuickAsk by typing /<trigger>.")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                } else {
                    ForEach(slashStore.customCommands) { cmd in
                        HStack(spacing: 8) {
                            Text(cmd.trigger)
                                .font(BodyFont.system(size: 12, wght: 700))
                                .foregroundColor(Palette.textPrimary)
                            Text(cmd.description)
                                .font(BodyFont.system(size: 11, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            QASSecondaryButton(label: "Remove") {
                                slashStore.remove(cmd.id)
                            }
                        }
                    }
                }
                QASSecondaryButton(label: "Add custom command") {
                    let suffix = slashStore.customCommands.count + 1
                    slashStore.upsert(QuickAskSlashCommand(
                        trigger: "/custom\(suffix)",
                        description: "Custom command",
                        expansion: nil
                    ))
                }
            }
            .padding(14)
        }

        QASSectionLabel(title: "Mention prompts")
        QASCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick-recall prompt templates. Type @<name> in QuickAsk to expand them.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                if mentionsStore.customPrompts.isEmpty {
                    Text("No custom prompts yet.")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                } else {
                    ForEach(mentionsStore.customPrompts) { p in
                        HStack(spacing: 8) {
                            Text("@\(p.name)")
                                .font(BodyFont.system(size: 12, wght: 700))
                                .foregroundColor(Palette.textPrimary)
                            Text(p.description)
                                .font(BodyFont.system(size: 11, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            QASSecondaryButton(label: "Remove") {
                                mentionsStore.remove(p.id)
                            }
                        }
                    }
                }
                QASSecondaryButton(label: "Add prompt") {
                    let suffix = mentionsStore.customPrompts.count + 1
                    mentionsStore.upsert(QuickAskMentionPrompt(
                        name: "prompt\(suffix)",
                        description: "Custom prompt",
                        body: "Edit this prompt body."
                    ))
                }
            }
            .padding(14)
        }

        QASSectionLabel(title: "Work with Apps")
        QASCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick the app QuickAsk should treat as your focal context. The picker lives in the toolbar inside the panel.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                Text("Reading app contents (selection, file paths) requires Accessibility permission.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                QASSecondaryButton(label: "Open Accessibility settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Shortcut recorder

/// Pill-shaped shortcut field. Click to enter recording mode; the next
/// chord that contains at least one modifier and a non-modifier key is
/// captured. Esc cancels, the same way Apple's keyboard preferences do.
private struct ShortcutRecorder: View {
    @Binding var recording: Bool
    let hotkey: QuickAskHotkey
    let onRecord: (QuickAskHotkey) -> Void

    @State private var hovered = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(recording
                      ? Color(red: 0.16, green: 0.46, blue: 0.98).opacity(0.18)
                      : (hovered ? Color(white: 0.21) : Color(white: 0.165)))
            Capsule(style: .continuous)
                .stroke(recording
                        ? Color(red: 0.16, green: 0.46, blue: 0.98).opacity(0.6)
                        : Color.white.opacity(0.10),
                        lineWidth: 0.7)

            Text(recording ? "Type a shortcut…" : hotkey.displayString)
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(recording ? Color(red: 0.66, green: 0.78, blue: 1.0) : Palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .fixedSize()
        .onHover { hovered = $0 }
        .onTapGesture { recording.toggle() }
        .background(
            ShortcutRecordingMonitor(
                isActive: $recording,
                onCapture: { code, mods in
                    onRecord(QuickAskHotkey(keyCode: code, modifiers: mods))
                    recording = false
                },
                onCancel: { recording = false }
            )
        )
    }
}

/// Bridges a SwiftUI parent into AppKit's local key-event monitor. We
/// install the monitor only while the recorder is active, capture the
/// next valid chord, and tear it down to avoid swallowing keystrokes
/// elsewhere in the app.
private struct ShortcutRecordingMonitor: NSViewRepresentable {
    @Binding var isActive: Bool
    let onCapture: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(
            isActive: isActive,
            onCapture: onCapture,
            onCancel: onCancel
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var monitor: Any?
        private var onCapture: ((UInt32, UInt32) -> Void)?
        private var onCancel: (() -> Void)?

        func sync(
            isActive: Bool,
            onCapture: @escaping (UInt32, UInt32) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            if isActive {
                installIfNeeded()
            } else {
                uninstall()
            }
        }

        private func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self else { return event }
                // Esc: cancel without capturing.
                if event.keyCode == kVK_Escape {
                    self.onCancel?()
                    return nil
                }
                // Require at least one modifier among ⌘⌥⌃⇧ to avoid
                // capturing a bare letter that would clash with normal
                // typing in any focused field after the recorder closes.
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let mods = carbonModifiers(from: flags)
                guard mods != 0 else { return nil }
                let code = UInt32(event.keyCode)
                self.onCapture?(code, mods)
                return nil
            }
        }

        private func uninstall() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { uninstall() }

        private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
            var m: UInt32 = 0
            if flags.contains(.command)  { m |= UInt32(cmdKey) }
            if flags.contains(.option)   { m |= UInt32(optionKey) }
            if flags.contains(.control)  { m |= UInt32(controlKey) }
            if flags.contains(.shift)    { m |= UInt32(shiftKey) }
            return m
        }
    }
}

// MARK: - Local building blocks (page-private)

private struct QASHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QuickAsk")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Floating composer that appears anywhere on screen with a global shortcut. Drag it where you want, ask, dismiss with Esc.")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.bottom, 26)
    }
}

private struct QASSectionLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(BodyFont.system(size: 13, wght: 600))
            .foregroundColor(Palette.textPrimary)
            .padding(.bottom, 14)
            .padding(.top, 28)
    }
}

private struct QASCard<Content: View>: View {
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
    }
}

private struct QASCardDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
}

private struct QASSecondaryButton: View {
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
