import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Settings page for the floating QuickAsk panel. Exposes the global
/// shortcut so the user can change it from the default ⌃⌥⌘K, plus
/// a one-tap "Open now" button to test the panel without leaving
/// Settings (handy when verifying a freshly-recorded combo).
struct QuickAskSettingsPage: View {

    @ObservedObject private var hotkeyManager = QuickAskHotkeyManager.shared
    @State private var recording = false

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
                        Text("Restores ⌃⌥⌘K, the shipped default.")
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

            QASSectionLabel(title: "Try it")
            QASCard {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open the panel now")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Same as pressing the shortcut. Drag the panel anywhere on screen — its position is remembered.")
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
            .padding(.bottom, 16)
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
