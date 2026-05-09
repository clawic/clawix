import SwiftUI
import AppKit

/// Vertical mirror of `SidebarResizeHandle`. Sits straddling the top
/// edge of the terminal panel (5pt above / 5pt below the boundary), and
/// drags the panel between [minHeight, maxHeightOverride]. Snaps the
/// panel closed if released below `closeThreshold`.
///
/// Why duplicate the sidebar handle instead of generalizing it: the
/// AppKit-level cursor-race fixes (move monitor, async dispatch,
/// mouseDownCanMoveWindow override) work the same per axis, but the
/// math (deltaSign on Y, inverted because dragging UP grows the panel)
/// is direction-specific enough that mixing them in the same NSView
/// would be noisier than two focused files. See the comment in
/// `ContentView.swift` near `SidebarResizeNSView` for the same set of
/// hard-won workarounds.
private let terminalPanelDefaultHeight: CGFloat = 280
private let terminalPanelMinHeight: CGFloat = 120
private let terminalPanelCloseThreshold: CGFloat = 80

struct TerminalResizeHandle: View {
    @Binding var heightRaw: Double
    @Binding var hovered: Bool
    var maxHeightOverride: CGFloat? = nil
    var onClose: () -> Void

    var body: some View {
        TerminalResizeNSViewBridge(
            heightRaw: $heightRaw,
            hovered: $hovered,
            maxHeightOverride: maxHeightOverride,
            onClose: onClose
        )
    }
}

private struct TerminalResizeNSViewBridge: NSViewRepresentable {
    @Binding var heightRaw: Double
    @Binding var hovered: Bool
    var maxHeightOverride: CGFloat?
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            heightRaw: $heightRaw,
            hovered: $hovered,
            maxHeightOverride: maxHeightOverride,
            onClose: onClose
        )
    }

    func makeNSView(context: Context) -> TerminalResizeNSView {
        let view = TerminalResizeNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TerminalResizeNSView, context: Context) {
        context.coordinator.heightRaw = $heightRaw
        context.coordinator.hovered = $hovered
        context.coordinator.maxHeightOverride = maxHeightOverride
        context.coordinator.onClose = onClose
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var heightRaw: Binding<Double>
        var hovered: Binding<Bool>
        var maxHeightOverride: CGFloat?
        var onClose: () -> Void
        init(
            heightRaw: Binding<Double>,
            hovered: Binding<Bool>,
            maxHeightOverride: CGFloat?,
            onClose: @escaping () -> Void
        ) {
            self.heightRaw = heightRaw
            self.hovered = hovered
            self.maxHeightOverride = maxHeightOverride
            self.onClose = onClose
        }
    }
}

private final class TerminalResizeNSView: NSView {
    weak var coordinator: TerminalResizeNSViewBridge.Coordinator?

    private var trackingArea: NSTrackingArea?
    private var dragStartLocationY: CGFloat = 0
    private var dragStartHeight: CGFloat = 0
    private var isDragging = false
    private var moveMonitor: Any?

    override var isFlipped: Bool { true }

    /// Same reasoning as the sidebar handle: the window has
    /// `isMovableByWindowBackground = true` for some chrome regions;
    /// returning false forwards the click to our `mouseDown`.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        if window != nil {
            installMoveMonitor()
        } else {
            removeMoveMonitor()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    private func installMoveMonitor() {
        guard moveMonitor == nil else { return }
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.applyResizeCursorIfInside(event: event)
            return event
        }
    }

    private func removeMoveMonitor() {
        if let m = moveMonitor {
            NSEvent.removeMonitor(m)
            moveMonitor = nil
        }
    }

    private func applyResizeCursorIfInside(event: NSEvent) {
        guard let window, event.window === window else { return }
        let mouseLocal = convert(event.locationInWindow, from: nil)
        guard bounds.contains(mouseLocal) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let local = self.convert(windowPoint, from: nil)
            guard self.bounds.contains(local) else { return }
            NSCursor.resizeUpDown.set()
        }
    }

    deinit {
        removeMoveMonitor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator?.hovered.wrappedValue = true
        NSCursor.resizeUpDown.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            coordinator?.hovered.wrappedValue = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else { return }
        isDragging = true
        dragStartLocationY = event.locationInWindow.y
        dragStartHeight = CGFloat(coordinator.heightRaw.wrappedValue)
        NSCursor.resizeUpDown.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        NSCursor.resizeUpDown.set()
        // Window-coordinate Y grows upward in non-flipped windows. The
        // panel is anchored to the bottom of the content area, so
        // dragging the handle DOWN in window coordinates (decreasing Y)
        // shrinks the panel; dragging UP grows it.
        let delta = dragStartLocationY - event.locationInWindow.y
        let proposed = dragStartHeight + delta
        let maxH = coordinator.maxHeightOverride ?? .greatestFiniteMagnitude
        let clamped = max(terminalPanelMinHeight, min(maxH, proposed))
        coordinator.heightRaw.wrappedValue = Double(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        isDragging = false
        let delta = dragStartLocationY - event.locationInWindow.y
        let proposed = dragStartHeight + delta
        if proposed < terminalPanelCloseThreshold {
            coordinator.onClose()
            coordinator.heightRaw.wrappedValue = Double(terminalPanelDefaultHeight)
        } else {
            let maxH = coordinator.maxHeightOverride ?? .greatestFiniteMagnitude
            let clamped = max(terminalPanelMinHeight, min(maxH, proposed))
            coordinator.heightRaw.wrappedValue = Double(clamped)
        }
        let mouse = convert(event.locationInWindow, from: nil)
        if !bounds.contains(mouse) {
            coordinator.hovered.wrappedValue = false
        }
    }
}

/// Defaults exposed for callers (clamping in the parent before
/// applying `frame(height:)`, choosing the initial panel height, etc.).
enum TerminalPanelMetrics {
    static let defaultHeight: CGFloat = terminalPanelDefaultHeight
    static let minHeight: CGFloat = terminalPanelMinHeight
    static let closeThreshold: CGFloat = terminalPanelCloseThreshold
}
