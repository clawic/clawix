import SwiftUI
import AppKit

// MARK: - Sidebar toggle icon (custom, replaces SF Symbol)

struct SidebarToggleIcon: View {
    enum Side { case left, right }
    var side: Side
    var size: CGFloat = 18
    var color: Color = Color(white: 0.55)

    var body: some View {
        Canvas { ctx, sz in
            let s = min(sz.width, sz.height) / 24
            let lineW: CGFloat = 1.575 * s + 0.25
            let stroke = StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round)

            // Outer rounded rectangle (square-ish, with softer corners).
            // Height shrunk 5% (17 → 16.15) and re-centred vertically.
            let outer = Path(roundedRect: CGRect(x: 3.5 * s, y: 3.925 * s, width: 17 * s, height: 16.15 * s),
                             cornerSize: CGSize(width: 4 * s, height: 4 * s),
                             style: .continuous)
            ctx.stroke(outer, with: .color(color), style: stroke)

            // Vertical mark near one inner edge; height shrunk 5% (10 → 9.5),
            // re-centred against the outer rect.
            let markX: CGFloat = (side == .left ? 7.5 : 16.5) * s
            var mark = Path()
            mark.move(to: CGPoint(x: markX, y: 7.25 * s))
            mark.addLine(to: CGPoint(x: markX, y: 16.75 * s))
            ctx.stroke(mark, with: .color(color), style: stroke)
        }
        .frame(width: size, height: size)
    }
}

/// Toggle button that brightens on hover, mirroring the sidebar header icons.
/// `SidebarToggleIcon` renders through `Canvas`, which does not interpolate
/// stroke colour between states. We render the canvas at full white and
/// animate the wrapper's `.opacity` instead so the transition shows the
/// same eased curve as the rest of the sidebar chrome.
struct SidebarToggleButton: View {
    let side: SidebarToggleIcon.Side
    var size: CGFloat = 18
    var hitSize: CGFloat? = nil
    var defaultOpacity: Double = 0.45
    var hoverOpacity: Double = 0.96
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            SidebarToggleIcon(side: side, size: size, color: .white)
                .opacity(hovered ? hoverOpacity : defaultOpacity)
                .frame(width: hitSize ?? size, height: hitSize ?? size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Shared colour palette

enum Palette {
    static let background    = Color(white: 0.04)
    static let sidebar       = Color(white: 0.245)
    static let cardFill      = Color(white: 0.14)
    static let cardHover     = Color(white: 0.17)
    static let border        = Color(white: 0.20)
    static let borderSubtle  = Color(white: 0.15)
    static let popupStroke   = Color.white.opacity(0.10)
    static let popupStrokeWidth: CGFloat = 0.5
    static let selFill       = Color(white: 0.28)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.55)
    static let textTertiary  = Color(white: 0.38)
    static let pastelBlue    = Color(red: 0.45, green: 0.65, blue: 1.0)
}

// MARK: - Standard dropdown / popup menu style
// Project-wide canon: every dropdown, popover-style menu, edit menu and
// context menu must share this chrome.
enum MenuStyle {
    static let cornerRadius: CGFloat        = 12
    // Tinted fill on top of a blurred backdrop. Slight translucency lets the
    // wallpaper and chat content bleed through subtly.
    static let fill                         = Color(white: 0.135).opacity(0.82)
    static let shadowColor                  = Color.black.opacity(0.40)
    static let shadowRadius: CGFloat        = 18
    static let shadowOffsetY: CGFloat       = 10
    static let menuVerticalPadding: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 9
    static let rowVerticalPadding: CGFloat   = 6
    static let rowIconLabelSpacing: CGFloat  = 6
    static let rowTrailingIconExtra: CGFloat = 5
    static let rowTrailingIconSize: CGFloat  = 11
    static let rowHoverCornerRadius: CGFloat = 8
    static let rowHoverInset: CGFloat        = 4
    static let rowHoverIntensity: Double     = 0.06
    static let rowHoverIntensityStrong: Double = 0.08
    static let dividerColor                  = Color.white.opacity(0.06)
    static let rowText                       = Color(white: 0.94)
    static let rowIcon                       = Color(white: 0.86)
    static let rowSubtle                     = Color(white: 0.55)
    static let headerText                    = Color(white: 0.50)
    static let openAnimation                 = Animation.easeOut(duration: 0.20)
}

// Window content width, used by lateral submenus to decide whether they
// fit on the right of their anchor row or have to flip to the left.
@MainActor
func currentWindowContentWidth() -> CGFloat {
    NSApp.keyWindow?.contentView?.bounds.width ?? .infinity
}

/// Decides whether a horizontally cascading submenu should open on the
/// right (preferred) or flip to the left of its anchor row, based on
/// whether placing it on the right would overflow the window.
///
/// - parentGlobalMinX: the parent menu's leading edge in window-content
///   coordinates (`proxy.frame(in: .global).minX`).
/// - row: the anchor row's frame in the parent menu's local space.
/// - Returns: a tuple with the offset to feed into
///   `alignmentGuide(.leading) { _ in offset }` and a boolean that is
///   `true` when the submenu was placed on the right.
@MainActor
func submenuLeadingPlacement(parentGlobalMinX: CGFloat,
                             row: CGRect,
                             submenuWidth: CGFloat,
                             gap: CGFloat,
                             safetyMargin: CGFloat = 12) -> (offset: CGFloat, placedRight: Bool) {
    let rightEdgeIfPlacedRight = parentGlobalMinX + row.maxX + gap + submenuWidth
    let windowMaxX = currentWindowContentWidth() - safetyMargin
    if rightEdgeIfPlacedRight <= windowMaxX {
        return (-(row.maxX + gap), true)
    }
    return (-(row.minX - gap - submenuWidth), false)
}

extension View {
    /// Applies the canonical dropdown chrome: blurred backdrop + tinted
    /// rounded fill + thin popup stroke + soft shadow.
    ///
    /// `blurBehindWindow`: pass `true` when the menu lives in a standalone
    /// `NSPanel` (e.g. the sidebar's right-click context menu) so the
    /// blur samples the content behind the panel rather than the
    /// transparent panel-internal contents.
    ///
    /// `opaque`: drop the blur and the tint's translucency for menus that
    /// open over visually busy regions where the standard 18% bleed reads
    /// as a stacking glitch (e.g. file-card "Open" popup, where the parent
    /// card's translucent fill would otherwise show through the menu).
    func menuStandardBackground(blurBehindWindow: Bool = false,
                                opaque: Bool = false) -> some View {
        self.background(
            ZStack {
                if !opaque {
                    VisualEffectBlur(material: .hudWindow,
                                     blendingMode: blurBehindWindow ? .behindWindow : .withinWindow,
                                     state: .active)
                    MenuStyle.fill
                } else {
                    Color(white: 0.135)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MenuStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MenuStyle.cornerRadius, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
            .shadow(color: MenuStyle.shadowColor,
                    radius: MenuStyle.shadowRadius,
                    x: 0, y: MenuStyle.shadowOffsetY)
        )
    }
}

// MARK: - Sidebar resize handle

/// 10-pt wide strip straddling the trailing edge of the left sidebar
/// (5 pt inside, 5 pt outside), that drags the sidebar between
/// [sidebarMinVisibleWidth, sidebarMaxWidth].
///
/// The hit zone is implemented as an `NSView` that registers a system
/// cursor rect (`.resizeLeftRight`) via `addCursorRect`. That avoids the
/// flicker and cursor-escape problem you get from driving the
/// cursor with SwiftUI's `.onHover` + `NSCursor.set()`: the OS now owns
/// the cursor for that rect and stops it from being overridden by
/// neighbouring views.
///
/// Drag is also handled in `mouseDown`/`mouseDragged`/`mouseUp` so the
/// gesture survives even if the cursor briefly leaves the strip during
/// the drag (AppKit keeps mouse events flowing to the original target
/// until mouseUp).
///
/// Releasing below `sidebarCloseThreshold` snaps the sidebar closed and
/// resets the persisted width to the default for the next open.
enum SidebarResizeSide {
    case left
    case right

    var minWidth: CGFloat {
        self == .left ? sidebarMinVisibleWidth : rightSidebarMinVisibleWidth
    }
    var maxWidth: CGFloat {
        self == .left ? sidebarMaxWidth : rightSidebarMaxWidth
    }
    var closeThreshold: CGFloat {
        self == .left ? sidebarCloseThreshold : rightSidebarCloseThreshold
    }
    var defaultWidth: CGFloat {
        self == .left ? sidebarDefaultWidth : rightSidebarDefaultWidth
    }
    /// Sign applied to the horizontal drag delta when computing the new
    /// width. Dragging right grows the left sidebar (+1) but shrinks the
    /// right one (-1).
    var deltaSign: CGFloat {
        self == .left ? 1 : -1
    }
}

struct SidebarResizeHandle: View {
    @Binding var widthRaw: Double
    @Binding var hovered: Bool
    var side: SidebarResizeSide = .left
    /// Tightens the upper bound below the side's static `maxWidth` when
    /// the surrounding layout cannot afford the full range (typically
    /// the right sidebar capped by the current window width minus the
    /// left sidebar and the min content column).
    var maxWidthOverride: CGFloat? = nil
    @EnvironmentObject var appState: AppState

    var body: some View {
        SidebarResizeNSViewBridge(
            widthRaw: $widthRaw,
            hovered: $hovered,
            side: side,
            maxWidthOverride: maxWidthOverride,
            onClose: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    switch side {
                    case .left:  appState.isLeftSidebarOpen = false
                    case .right: appState.isRightSidebarOpen = false
                    }
                }
            }
        )
    }
}

struct SidebarResizeNSViewBridge: NSViewRepresentable {
    @Binding var widthRaw: Double
    @Binding var hovered: Bool
    var side: SidebarResizeSide
    var maxWidthOverride: CGFloat?
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            widthRaw: $widthRaw,
            hovered: $hovered,
            side: side,
            maxWidthOverride: maxWidthOverride,
            onClose: onClose
        )
    }

    func makeNSView(context: Context) -> SidebarResizeNSView {
        let view = SidebarResizeNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SidebarResizeNSView, context: Context) {
        context.coordinator.widthRaw = $widthRaw
        context.coordinator.hovered = $hovered
        context.coordinator.side = side
        context.coordinator.maxWidthOverride = maxWidthOverride
        context.coordinator.onClose = onClose
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var widthRaw: Binding<Double>
        var hovered: Binding<Bool>
        var side: SidebarResizeSide
        var maxWidthOverride: CGFloat?
        var onClose: () -> Void
        init(
            widthRaw: Binding<Double>,
            hovered: Binding<Bool>,
            side: SidebarResizeSide,
            maxWidthOverride: CGFloat?,
            onClose: @escaping () -> Void
        ) {
            self.widthRaw = widthRaw
            self.hovered = hovered
            self.side = side
            self.maxWidthOverride = maxWidthOverride
            self.onClose = onClose
        }
    }
}

final class SidebarResizeNSView: NSView {
    weak var coordinator: SidebarResizeNSViewBridge.Coordinator?

    private var trackingArea: NSTrackingArea?
    private var dragStartLocationX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0
    private var isDragging = false
    private var moveMonitor: Any?

    override var isFlipped: Bool { true }

    // CRITICAL: window has `isMovableByWindowBackground = true`. Any view
    // that doesn't explicitly opt out of "background drag" lets the window
    // hijack mouseDown and start a window drag instead of forwarding the
    // event to us. That's why dragging the resize strip was moving the
    // whole window. Returning false here makes AppKit dispatch the click
    // to our `mouseDown` overrides.
    override var mouseDownCanMoveWindow: Bool { false }

    // Receive clicks even if the window isn't yet key (resize-on-first-click).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Window-level cursor rect: the system reapplies `.resizeLeftRight`
    // automatically every time the cursor is inside `bounds`, on every
    // mouse move, regardless of what other SwiftUI siblings are doing
    // with `NSCursor.set()`. This is the most reliable mechanism and is
    // the primary reason the resize cursor stays sticky across the whole
    // 10-pt strip. The tracking-area paths below are belt-and-braces.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
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

    // Some other view (likely SwiftUI's hosting machinery or a sibling
    // sidebar row) is calling `NSCursor.set(.arrow)` during the same event
    // tick that we run our own cursorUpdate/mouseMoved overrides, so its
    // call lands AFTER ours and the resize cursor never sticks while just
    // hovering. Workaround: install an app-wide local monitor for
    // `.mouseMoved`, and when the cursor is inside our bounds defer
    // `NSCursor.resizeLeftRight.set()` to the next runloop turn via
    // `DispatchQueue.main.async`. That guarantees our `.set()` runs after
    // every other view has finished processing the event, so we win the
    // race deterministically.
    private func installMoveMonitor() {
        guard moveMonitor == nil else { return }
        moveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved]
        ) { [weak self] event in
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
            // Re-check bounds at dispatch time using the CURRENT mouse
            // position, not the event's. Between the synchronous check
            // above and this dispatch the cursor may have left our strip
            // (the user moves fast into the sidebar). Setting the resize
            // cursor here would then strand it: the cursor is already
            // outside our `addCursorRect`, so the system won't see a
            // boundary crossing to reset it back to arrow until the user
            // re-enters and exits again. Result: the resize cursor
            // sticks while the user is navigating the sidebar.
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let local = self.convert(windowPoint, from: nil)
            guard self.bounds.contains(local) else { return }
            NSCursor.resizeLeftRight.set()
        }
    }

    deinit {
        removeMoveMonitor()
    }

    // Cursor is reapplied on every mouseMoved inside the strip, not just on
    // enter. `cursorUpdate` only fires once per entry, so whenever a sibling
    // SwiftUI view (text, buttons) calls `NSCursor.set()` afterwards it pins
    // the wrong cursor until the user leaves and re-enters. With `.mouseMoved`
    // the tracking area receives every move event regardless of the window's
    // `acceptsMouseMovedEvents`, and we re-set the resize cursor each time.
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
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator?.hovered.wrappedValue = true
        NSCursor.resizeLeftRight.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            coordinator?.hovered.wrappedValue = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else { return }
        isDragging = true
        dragStartLocationX = event.locationInWindow.x
        dragStartWidth = CGFloat(coordinator.widthRaw.wrappedValue)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        // During a drag the cursor often leaves the 10-pt strip, which
        // means mouseMoved/cursorUpdate stop firing. Force the resize
        // cursor on every drag tick so it stays sticky.
        NSCursor.resizeLeftRight.set()
        let side = coordinator.side
        let maxW = min(side.maxWidth, coordinator.maxWidthOverride ?? .greatestFiniteMagnitude)
        let delta = (event.locationInWindow.x - dragStartLocationX) * side.deltaSign
        let proposed = dragStartWidth + delta
        let clamped = max(side.minWidth, min(maxW, proposed))
        coordinator.widthRaw.wrappedValue = Double(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        guard let coordinator, isDragging else { return }
        isDragging = false
        let side = coordinator.side
        let maxW = min(side.maxWidth, coordinator.maxWidthOverride ?? .greatestFiniteMagnitude)
        let delta = (event.locationInWindow.x - dragStartLocationX) * side.deltaSign
        let proposed = dragStartWidth + delta
        if proposed < side.closeThreshold {
            coordinator.onClose()
            coordinator.widthRaw.wrappedValue = Double(side.defaultWidth)
        } else {
            let clamped = max(side.minWidth, min(maxW, proposed))
            coordinator.widthRaw.wrappedValue = Double(clamped)
        }
        // If the cursor moved out during the drag, fold hover off now.
        let mouse = convert(event.locationInWindow, from: nil)
        if !bounds.contains(mouse) {
            coordinator.hovered.wrappedValue = false
        }
    }
}

/// Inset rounded hover highlight for menu rows. Mirrors the highlight used
/// by the model dropdown: a 7-pt rounded fill that breathes 5pt away from
/// the menu edges.
struct MenuRowHover: View {
    let active: Bool
    var intensity: Double = MenuStyle.rowHoverIntensity
    var body: some View {
        RoundedRectangle(cornerRadius: MenuStyle.rowHoverCornerRadius, style: .continuous)
            .fill(active ? Color.white.opacity(intensity) : Color.clear)
            .padding(.horizontal, MenuStyle.rowHoverInset)
    }
}
