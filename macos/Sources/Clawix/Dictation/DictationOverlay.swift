import Foundation
import AppKit
import SwiftUI

/// Frameless `NSPanel` that hosts the dictation pill near the bottom
/// of the active screen. The panel itself owns no state — an
/// `NSHostingView` rooted at `DictationOverlayView` reads the shared
/// `DictationCoordinator` and animates phase transitions.
///
/// The panel is `.nonactivatingPanel` so showing it doesn't steal focus
/// from the user's foreground app, and ships with `canJoinAllSpaces`
/// + `fullScreenAuxiliary` so it floats over fullscreen apps too.
///
/// Mouse events are accepted (so the trailing stop button is tappable),
/// but the SwiftUI hierarchy paints the pill in a small centred frame
/// while the surrounding panel area stays transparent — empty SwiftUI
/// regions don't grab clicks, so the chrome around the pill remains
/// fully click-through to the app underneath.
/// Where the floating dictation pill is anchored. `mini` keeps the
/// classic bottom-centre placement that doesn't depend on hardware;
/// `notch` docks the pill at the top of the main display, adjacent to
/// the MacBook camera notch on machines that have one. Notch
/// placement falls back to top-centre on hardware without a notch.
enum DictationRecorderStyle: String, CaseIterable, Codable {
    case mini
    case notch

    var displayName: String {
        switch self {
        case .mini:  return "Mini (bottom)"
        case .notch: return "Notch (top)"
        }
    }
}

@MainActor
final class DictationOverlay {

    static let shared = DictationOverlay()

    /// Persisted in UserDefaults. Reading on every show keeps the
    /// switch live without a relaunch.
    nonisolated static let styleKey = "dictation.recorderStyle"

    private var panel: NSPanel?
    private weak var coordinator: DictationCoordinator?

    /// Panel content area. Width fits the Esc-confirmation toast
    /// (296pt) with a small horizontal margin; height fits the toast
    /// (38pt) + gap (10pt) + pill (40pt) plus a few pt of vertical
    /// breathing room.
    private static let panelSize = NSSize(width: 320, height: 100)

    /// Bind the overlay to the coordinator. Show/hide is driven by the
    /// `overlayVisible` published flag through `DictationOverlayHost`.
    func install(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = false
        // Mouse events ARE accepted: the trailing stop button needs to
        // receive taps. SwiftUI paints the pill in a centred 184×40
        // frame and leaves the surrounding area transparent, so clicks
        // outside the pill fall through to the app underneath.
        panel.ignoresMouseEvents = false

        let view = DictationOverlayHost(coordinator: coordinator) { [weak self] visible in
            guard let self else { return }
            if visible {
                self.show()
            } else {
                self.hide()
            }
        }
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting
        self.panel = panel
    }

    func show() {
        guard let panel else { return }
        position(panel: panel)
        panel.orderFront(nil)
        // Only grab bare Esc system-wide while a recording / transcription
        // session is live — not when the panel is just up to surface an
        // error toast. Otherwise the user's foreground app would lose Esc
        // for the toast's whole window for no reason.
        if let coordinator, coordinator.state != .idle {
            armEscRegistrar()
        } else {
            disarmEscRegistrar()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        disarmEscRegistrar()
    }

    /// Anchor the panel based on the user's `recorderStyle` setting.
    /// `mini` (default) → bottom-centre of the active screen, dock
    /// aware via `visibleFrame`. `notch` → top-centre, sitting just
    /// below the notch / menu bar so the pill reads as an extension of
    /// the system chrome on MacBooks.
    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let style = currentStyle()
        let width = panel.frame.width
        let height = panel.frame.height
        let area = screen.visibleFrame
        let x = area.midX - width / 2
        let y: CGFloat
        switch style {
        case .mini:
            y = area.minY + 24
        case .notch:
            // `visibleFrame.maxY` already excludes the menu bar (and
            // the notch's vertical extent on machines that have one),
            // so anchoring `panel.maxY` exactly at that line keeps a
            // small breathing room from the notch chrome.
            y = area.maxY - height - 4
        }
        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true
        )
    }

    private func currentStyle() -> DictationRecorderStyle {
        let raw = UserDefaults.standard.string(forKey: Self.styleKey) ?? DictationRecorderStyle.mini.rawValue
        return DictationRecorderStyle(rawValue: raw) ?? .mini
    }

    /// Wire bare Esc system-wide for the lifetime of this session and
    /// route every press through the coordinator's double-tap handler:
    /// the first press raises the "Press ESC again to cancel" toast,
    /// a second press inside the 1.5s window cancels.
    ///
    /// `addLocalMonitorForEvents` only delivers Esc while Clawix is
    /// frontmost; the user dictating into another app would press Esc,
    /// the foreground app would beep (no key consumer), and our
    /// handler would never fire. Carbon's `RegisterEventHotKey`
    /// (encapsulated in `DictationEscRegistrar`) intercepts the chord
    /// regardless of frontmost app and consumes it, so no system
    /// beep escapes either.
    private func armEscRegistrar() {
        DictationEscRegistrar.shared.onPress = { [weak self] in
            self?.coordinator?.handleEscapeFromOverlay()
        }
        DictationEscRegistrar.shared.arm()
    }

    private func disarmEscRegistrar() {
        DictationEscRegistrar.shared.disarm()
    }
}

/// SwiftUI shim that pipes `coordinator.overlayVisible` back to the
/// AppKit panel through a closure. Keeps view code free of AppKit
/// references and makes the overlay's lifetime follow coordinator
/// state without any explicit show/hide call sites.
private struct DictationOverlayHost: View {
    @ObservedObject var coordinator: DictationCoordinator
    let onVisibilityChange: (Bool) -> Void

    var body: some View {
        DictationOverlayView(coordinator: coordinator)
            .onChange(of: coordinator.overlayVisible) { _, newValue in
                onVisibilityChange(newValue)
            }
            .onAppear {
                onVisibilityChange(coordinator.overlayVisible)
            }
    }
}
