import Foundation
import AppKit
import SwiftUI

/// Frameless, click-through-friendly NSPanel that paints the
/// recording pill on top of every space and every fullscreen app. The
/// panel itself owns no state; an `NSHostingView` rooted at
/// `DictationOverlayView` reads the coordinator and animates state
/// changes.
///
/// Patterned after `DragChipPanel` in `SidebarView.swift` so the
/// chrome (level, collection behavior, opacity) matches what the rest
/// of the app already does for floating UI.
@MainActor
final class DictationOverlay {

    static let shared = DictationOverlay()

    private var panel: NSPanel?
    private weak var coordinator: DictationCoordinator?
    private var escMonitor: Any?

    /// Bind the overlay to the coordinator. Show/hide happens through
    /// the `overlayVisible` published flag; we observe it via SwiftUI
    /// inside the panel content.
    func install(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        guard panel == nil else { return }

        let size = NSSize(width: 260, height: 110)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        // Strictly pass-through: the pill is purely informational
        // chrome that never steals clicks from the app underneath.
        // The user cancels with Esc (handled in `installEscMonitor`).
        panel.ignoresMouseEvents = true

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
        installEscMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeEscMonitor()
    }

    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let width = panel.frame.width
        let height = panel.frame.height
        let x = area.midX - width / 2
        // Sit ~80pt above the bottom of the visible area so the pill
        // hovers near the dock without touching it. visibleFrame.minY
        // is already the top of the dock when it's pinned, so this is
        // dock-aware.
        let y = area.minY + 80
        panel.setFrame(
            NSRect(x: x, y: y, width: width, height: height),
            display: true
        )
    }

    /// Esc cancels whatever session is in flight. Implemented as a
    /// global+local key monitor pair while the overlay is visible so
    /// the user can dismiss the pill no matter which app has focus,
    /// without the panel having to grab clicks.
    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 0x35 { // Esc
                self?.coordinator?.cancel()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}

/// SwiftUI shim that watches `coordinator.overlayVisible` and pipes
/// it back to the AppKit panel via a closure, so the panel's lifetime
/// follows the coordinator's state without the view itself owning any
/// AppKit references.
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
