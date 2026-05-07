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
struct QuickAskView: View {

    let onSubmit: (String) -> Void
    let onClose: () -> Void

    @State private var prompt: String = ""
    @State private var selectedModel: QuickAskModel = .instant
    @FocusState private var inputFocused: Bool

    private let cornerRadius: CGFloat = 26

    var body: some View {
        ZStack {
            shape
            content
        }
        // Explicit visible size so the squircle's footprint matches
        // what the controller treats as the "real" panel; the
        // surrounding `.padding(QuickAskController.shadowMargin)`
        // gives the drop shadow room to render past the squircle's
        // edge without being clipped by the NSPanel's bounds.
        .frame(width: QuickAskController.visibleSize.width,
               height: QuickAskController.visibleSize.height)
        .padding(QuickAskController.shadowMargin)
        .onAppear { focusInput() }
        .onReceive(NotificationCenter.default.publisher(for: QuickAskController.didShowNotification)) { _ in
            focusInput()
        }
    }

    // Glass background + a solid-ish dark tint so the panel reads as a
    // panel, not a watermark. White hairline at 50% reads like the
    // bright bevel in the user's reference shot. Shadow is softer than
    // the previous pass — the user said the prior radius/opacity
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
        VStack(alignment: .leading, spacing: 6) {
            promptField
            controlsRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var promptField: some View {
        TextField(
            "",
            text: $prompt,
            prompt: Text("Pregunta lo que quieras")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Color(white: 0.55))
        )
        .textFieldStyle(.plain)
        .font(BodyFont.system(size: 12))
        .foregroundColor(.white)
        .focused($inputFocused)
        .onSubmit(submitIfReady)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            QuickAskPlusMenu()
            QuickAskModelPicker(selection: $selectedModel)
            Spacer(minLength: 0)
            micButton
            sendButton
        }
    }

    // Same `MicIcon` and visual treatment as `ComposerView` so the
    // QuickAsk panel and the in-app composer feel like the same family.
    private var micButton: some View {
        Button {
            // Voice flow lands alongside the dictation wiring; for now
            // the button is visual parity with the main composer.
        } label: {
            MicIcon(lineWidth: 1.5)
                .foregroundColor(.white)
                .opacity(0.62)
                .frame(width: 18, height: 18)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Send button is a 1:1 copy of `ComposerView.sendButton`'s look:
    // 30pt white disc with a bold black `arrow.up`, dimmed when the
    // input is empty.
    private var sendButton: some View {
        Button(action: submitIfReady) {
            Image(systemName: "arrow.up")
                .font(BodyFont.system(size: 15, weight: .bold))
                .foregroundColor(canSend ? Color(white: 0.06) : Color.white.opacity(0.55))
                .frame(width: 28, height: 28)
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
        onSubmit(trimmed)
        prompt = ""
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
                .font(BodyFont.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.78)
                .frame(width: 26, height: 26)
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

/// Pill-style dropdown styled after the macOS composer's model button
/// (label + `chevron.down`). For QuickAsk we ship a single
/// "5.5 Instant" model selected by default; the menu still surfaces
/// the alternates so the affordance reads as a real picker.
private struct QuickAskModelPicker: View {
    @Binding var selection: QuickAskModel

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
            HStack(spacing: 4) {
                Text(selection.displayName)
                    .font(BodyFont.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.78))
                Image(systemName: "chevron.down")
                    .font(BodyFont.system(size: 9, weight: .bold))
                    .foregroundColor(Color(white: 0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        // `.menuStyle(.button) + .buttonStyle(.plain)` is the
        // combination that suppresses the system disclosure glyph
        // SwiftUI normally injects on the leading side. Without it,
        // the custom trailing `chevron.down` ends up duplicated.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
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
