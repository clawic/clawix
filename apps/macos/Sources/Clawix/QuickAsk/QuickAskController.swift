import AppKit
import Combine
import SwiftUI

/// Owns the QuickAsk floating panel: creates it lazily, shows/hides it
/// in response to the global hotkey, and persists the drag position so
/// the panel reappears wherever the user last left it.
@MainActor
final class QuickAskController: ObservableObject {

    static let shared = QuickAskController()

    private var panel: QuickAskPanel?
    private var positionObserver: NSObjectProtocol?

    private let defaults = UserDefaults.standard
    private let bottomCenterKey = "quickAsk.bottomCenter"
    private let legacyFrameKey = "quickAsk.panelFrame"
    private let chatIdKey = "quickAsk.activeChatId"

    weak var appState: AppState?

    static let compactVisibleSize = NSSize(width: 500, height: 88)
    static let expandedVisibleSize = NSSize(width: 520, height: 540)

    /// Transparent breathing room around the squircle, on all sides,
    /// so SwiftUI's drop shadow has room to render without being
    /// clipped by the NSPanel's outer rectangle. Same value for both
    /// sizes so the perceived gap stays constant.
    static let shadowMargin: CGFloat = 30

    @Published private(set) var isExpanded: Bool = false

    @Published private(set) var activeChatId: UUID?

    /// Resolved visible footprint for the current expansion state.
    private var visibleSize: NSSize {
        isExpanded ? Self.expandedVisibleSize : Self.compactVisibleSize
    }

    /// NSPanel size = visible squircle + shadow margin on every side.
    private var panelSize: NSSize {
        NSSize(
            width: visibleSize.width + Self.shadowMargin * 2,
            height: visibleSize.height + Self.shadowMargin * 2
        )
    }

    private var isResizingProgrammatically: Bool = false

    /// Notification fired every time the panel becomes visible so the
    /// SwiftUI view can re-acquire keyboard focus on each open. With a
    /// `.nonactivatingPanel`, `onAppear` only runs the first time the
    /// host is mounted — subsequent toggles re-show the same view, so
    /// `@FocusState` needs an explicit nudge.
    static let didShowNotification = Notification.Name("QuickAskDidShow")

    private init() {
        if let raw = defaults.string(forKey: chatIdKey),
           let id = UUID(uuidString: raw) {
            self.activeChatId = id
        }
    }

    func attach(appState: AppState) {
        self.appState = appState
    }

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
        NSLog("[QuickAsk] toggle() hotkey fired, visible=\(panel?.isVisible == true)")
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        NSLog("[QuickAsk] show() activeChatId=\(activeChatId?.uuidString ?? "nil") chats=\(appState?.chats.count ?? -1)")
        if let id = activeChatId {
            if let chat = appState?.chats.first(where: { $0.id == id }), !chat.messages.isEmpty {
                isExpanded = true
            } else {
                clearActiveChat()
                isExpanded = false
            }
        } else {
            isExpanded = false
        }

        let panel = ensurePanel()
        positionForShow(panel)
        NSLog("[QuickAsk] show() panel frame=\(NSStringFromRect(panel.frame)) screen=\(panel.screen?.localizedName ?? "nil") isExpanded=\(isExpanded)")
        // Bring forward but don't promote the app to frontmost; the
        // non-activating panel keeps the user's previous app in focus
        // until they click/type into the panel.
        panel.orderFrontRegardless()
        panel.makeKey()
        NSLog("[QuickAsk] show() ordered front, isVisible=\(panel.isVisible)")
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

    // MARK: - Conversation lifecycle

    func submitPrompt(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let appState else { return }

        let resolvedId = appState.submitQuickAsk(chatId: activeChatId, text: trimmed)
        if activeChatId != resolvedId {
            activeChatId = resolvedId
            persistActiveChat()
        }
        if !isExpanded {
            isExpanded = true
            resizePanel(animated: true)
        }
    }

    func startNewConversation() {
        clearActiveChat()
        if isExpanded {
            isExpanded = false
            resizePanel(animated: true)
        }
    }

    func openInMainApp() {
        guard let id = activeChatId, let appState else {
            hide()
            return
        }
        appState.currentRoute = .chat(id)
        for window in NSApp.windows where window.identifier?.rawValue == FileMenuActions.mainWindowID {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hide()
            return
        }
        // No main window currently around: nudge AppKit to reopen one.
        NSApp.activate(ignoringOtherApps: true)
        hide()
    }

    private func clearActiveChat() {
        activeChatId = nil
        persistActiveChat()
    }

    private func persistActiveChat() {
        if let id = activeChatId {
            defaults.set(id.uuidString, forKey: chatIdKey)
        } else {
            defaults.removeObject(forKey: chatIdKey)
        }
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

        let host = NSHostingView(rootView: QuickAskView(controller: self))
        // Use the autoresize-mask path (instead of constraint-based
        // layout) so the host always fills the panel's contentView.
        // With `translatesAutoresizingMaskIntoConstraints = false` and
        // no explicit constraints, AppKit can leave the host detached
        // from the panel's frame and the resulting window ends up at
        // `NSHostingView`'s default intrinsic size.
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
            guard let self else { return }
            // Programmatic resizes also fire didMoveNotification because
            // the origin changes; skip those so the saved anchor only
            // ever reflects an interactive drag.
            if self.isResizingProgrammatically { return }
            guard let win = note.object as? NSWindow else { return }
            self.saveBottomCenter(from: win.frame)
        }

        self.panel = panel
        return panel
    }

    /// Restore the last-known position if it still falls on a connected
    /// screen, otherwise drop the panel at the bottom-center of the
    /// screen the cursor is on, with a small breathing margin above
    /// the dock. `NSScreen.main` is the screen with the key window
    /// (not the cursor), so on multi-display setups we pick the
    /// pointer's screen explicitly to land near the user's attention.
    /// `visibleFrame.minY` already accounts for the dock, so adding a
    /// fixed offset keeps the gap consistent whether the dock is
    /// pinned or hidden.
    private func positionForShow(_ panel: QuickAskPanel) {
        let size = panelSize
        if let bottomCenter = restoreBottomCenter() {
            let frame = clampedFrame(forBottomCenter: bottomCenter, size: size)
            panel.setFrame(frame, display: true, animate: false)
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
        let x = area.midX - size.width / 2
        let y = area.minY + bottomMargin - Self.shadowMargin
        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true,
            animate: false
        )
    }

    /// Animate the panel between compact and expanded sizes while
    /// keeping the bottom-center of the visible squircle pinned. The
    /// input row sits near the bottom of the panel in both sizes, so
    /// anchoring by bottom-center means the prompt field stays under
    /// the user's cursor across the resize, only the conversation
    /// area appears (or disappears) above it.
    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        let oldFrame = panel.frame
        let newSize = panelSize
        let visibleBottomCenter = NSPoint(
            x: oldFrame.midX,
            y: oldFrame.minY + Self.shadowMargin
        )
        let target = clampedFrame(
            forBottomCenter: visibleBottomCenter,
            size: newSize,
            screen: panel.screen
        )

        isResizingProgrammatically = true
        panel.setFrame(target, display: true, animate: animated)
        // Reset the guard after the animation kick-off so any user
        // drag that arrives while the animation is still in flight
        // is still treated as user input. AppKit's animated setFrame
        // is short (~0.15s) so a runloop hop is sufficient in practice.
        DispatchQueue.main.async { [weak self] in
            self?.isResizingProgrammatically = false
        }
    }

    private func clampedFrame(
        forBottomCenter bottomCenter: NSPoint,
        size: NSSize,
        screen explicitScreen: NSScreen? = nil
    ) -> NSRect {
        let x = bottomCenter.x - size.width / 2
        let y = bottomCenter.y - Self.shadowMargin
        var frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        let screen = explicitScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(bottomCenter) })
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // If growing past the top edge would bury the conversation
            // under the menu bar, push the panel down so it stays in
            // view. Same idea on the bottom edge for the dock.
            let topOverflow = frame.maxY - visible.maxY
            if topOverflow > 0 {
                frame.origin.y -= topOverflow
            }
            let bottomOverflow = visible.minY - frame.minY
            if bottomOverflow > 0 {
                frame.origin.y += bottomOverflow
            }
            // Same horizontal clamp in case a multi-monitor layout
            // changed since the last position was saved.
            let rightOverflow = frame.maxX - visible.maxX
            if rightOverflow > 0 {
                frame.origin.x -= rightOverflow
            }
            let leftOverflow = visible.minX - frame.minX
            if leftOverflow > 0 {
                frame.origin.x += leftOverflow
            }
        }
        return frame
    }

    private func screenContainingCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }

    // MARK: - Position persistence

    /// We persist only the bottom-center of the visible squircle, NOT
    /// the panel's full frame. The panel changes size between the
    /// compact (100pt tall) and expanded (~540pt tall) layouts, but the
    /// user thinks of the input row as the "anchor". Saving a
    /// frame-with-size means the panel would jump after every
    /// shrink/grow on subsequent reopens. Saving just the bottom-center
    /// lets `positionForShow` rebuild a frame that matches whatever
    /// size we are about to render at.
    private func saveBottomCenter(from frame: NSRect) {
        let bottomCenter = NSPoint(
            x: frame.midX,
            y: frame.minY + Self.shadowMargin
        )
        defaults.set(NSStringFromPoint(bottomCenter), forKey: bottomCenterKey)
    }

    private func restoreBottomCenter() -> NSPoint? {
        if let raw = defaults.string(forKey: bottomCenterKey) {
            let point = NSPointFromString(raw)
            if isPointOnAnyScreen(point) { return point }
            return nil
        }
        // One-shot migration from the old "full frame" key so users
        // who already dragged the compact HUD do not see it jump back
        // to default placement on the first launch after this change.
        if let legacy = defaults.string(forKey: legacyFrameKey) {
            let rect = NSRectFromString(legacy)
            if rect.width > 100, rect.height > 50 {
                let point = NSPoint(x: rect.midX, y: rect.minY + Self.shadowMargin)
                if isPointOnAnyScreen(point) { return point }
            }
        }
        return nil
    }

    private func isPointOnAnyScreen(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens where screen.visibleFrame.contains(point) {
            return true
        }
        return false
    }
}
