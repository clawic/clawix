import AppKit
import SwiftUI

/// Owns the QuickAsk floating panel: creates it lazily, shows/hides it
/// in response to the global hotkey, and persists the drag position so
/// the panel reappears wherever the user last left it.
@MainActor
final class QuickAskController {

    static let shared = QuickAskController()

    private var panel: QuickAskPanel?
    private var positionObserver: NSObjectProtocol?

    private let defaults = UserDefaults.standard
    private let frameKey = "quickAsk.panelFrame"

    /// Visible squircle size — what the user perceives as the panel.
    /// Kept ~30% narrower than the first iteration so the panel reads
    /// as a HUD, not a full composer.
    static let visibleSize = NSSize(width: 500, height: 100)

    /// Transparent breathing room around the squircle, on all sides,
    /// so SwiftUI's drop shadow has room to render without being
    /// clipped by the NSPanel's outer rectangle. The user flagged
    /// the previous "cut shadow" look — this margin is the fix.
    static let shadowMargin: CGFloat = 30

    /// NSPanel size = visible squircle + shadow margin on every side.
    private var panelSize: NSSize {
        NSSize(
            width: Self.visibleSize.width + Self.shadowMargin * 2,
            height: Self.visibleSize.height + Self.shadowMargin * 2
        )
    }

    /// Notification fired every time the panel becomes visible so the
    /// SwiftUI view can re-acquire keyboard focus on each open. With a
    /// `.nonactivatingPanel`, `onAppear` only runs the first time the
    /// host is mounted — subsequent toggles re-show the same view, so
    /// `@FocusState` needs an explicit nudge.
    static let didShowNotification = Notification.Name("QuickAskDidShow")

    /// Wire the hotkey manager so a press toggles the panel. Called
    /// once from `AppDelegate.applicationDidFinishLaunching`.
    func install() {
        QuickAskHotkeyManager.shared.onTrigger = { [weak self] in
            self?.toggle()
        }
        QuickAskHotkeyManager.shared.install()
    }

    /// Toggle visibility. Pressing the hotkey while the panel is on
    /// screen dismisses it, mirroring Spotlight / Raycast behaviour.
    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        positionForShow(panel)
        // Bring forward but don't promote the app to frontmost; the
        // non-activating panel keeps the user's previous app in focus
        // until they click/type into the panel.
        panel.orderFrontRegardless()
        panel.makeKey()
        // Tell SwiftUI to re-focus the text field. Defer one runloop
        // tick so the focus call lands after the panel is fully on
        // screen and SwiftUI has finished any pending layout.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didShowNotification,
                object: nil
            )
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel construction

    private func ensurePanel() -> QuickAskPanel {
        if let panel { return panel }

        let initialFrame = NSRect(origin: .zero, size: panelSize)
        let panel = QuickAskPanel(contentRect: initialFrame)
        // `canJoinAllSpaces` makes the panel render on whichever Space
        // is active when it is shown; `fullScreenAuxiliary` lets it
        // appear on top of a fullscreen app. Note: `.canJoinAllSpaces`
        // and `.moveToActiveSpace` are mutually exclusive — AppKit
        // throws `NSInternalInconsistencyException` if both are set.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        let host = NSHostingView(rootView: QuickAskView(
            onSubmit: { [weak self] _ in self?.hide() },
            onClose:  { [weak self] in self?.hide() }
        ))
        // Use the autoresize-mask path (instead of constraint-based
        // layout) so the host always fills the panel's contentView.
        // With `translatesAutoresizingMaskIntoConstraints = false` and
        // no explicit constraints, AppKit can leave the host detached
        // from the panel's frame and the resulting window ends up at
        // `NSHostingView`'s default intrinsic size (which on this
        // SwiftUI tree resolves to a square ~500×500 — the bug we just
        // hit).
        host.frame = NSRect(origin: .zero, size: panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setContentSize(panelSize)

        // Persist the user's drag every time the panel moves so we can
        // restore the same screen position on the next press.
        positionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            self?.saveFrame(win.frame)
        }

        self.panel = panel
        return panel
    }

    /// Restore the last-known frame if it still falls on a connected
    /// screen, otherwise drop the panel at the bottom-center of the
    /// screen the cursor is on, with a small breathing margin above
    /// the dock. `NSScreen.main` is the screen with the key window
    /// (not the cursor), so on multi-display setups we pick the
    /// pointer's screen explicitly to land near the user's attention.
    /// `visibleFrame.minY` already accounts for the dock, so adding a
    /// fixed offset keeps the gap consistent whether the dock is
    /// pinned or hidden.
    private func positionForShow(_ panel: QuickAskPanel) {
        if let restored = restoreFrame() {
            panel.setFrame(restored, display: true, animate: false)
            return
        }
        let screen = screenContainingCursor() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let area = screen.visibleFrame
        // We want the *visible* bottom edge of the squircle (not the
        // panel's outer rectangle, which extends `shadowMargin` past
        // it on every side) to sit `bottomMargin` above the dock.
        // Subtract the shadow margin so the perceived gap matches.
        let bottomMargin: CGFloat = 36
        let x = area.midX - panelSize.width / 2
        let y = area.minY + bottomMargin - Self.shadowMargin
        panel.setFrame(
            NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height),
            display: true,
            animate: false
        )
    }

    private func screenContainingCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }

    // MARK: - Frame persistence

    private func saveFrame(_ frame: NSRect) {
        defaults.set(NSStringFromRect(frame), forKey: frameKey)
    }

    private func restoreFrame() -> NSRect? {
        guard let raw = defaults.string(forKey: frameKey) else { return nil }
        let rect = NSRectFromString(raw)
        guard rect.width > 100, rect.height > 50 else { return nil }
        // Reject saved frames that no longer fit any connected screen
        // (external monitor disconnected, etc.). Falls through to the
        // default placement.
        for screen in NSScreen.screens where screen.visibleFrame.intersects(rect) {
            return rect
        }
        return nil
    }
}
