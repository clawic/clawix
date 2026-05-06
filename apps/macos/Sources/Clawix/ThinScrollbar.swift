import SwiftUI
import AppKit

/// SwiftUI scroll container backed by a real `NSScrollView` and a custom
/// `NSScroller` that paints a thin, low-opacity capsule. Scrolling and
/// thumb tracking are 100% native — we don't observe scroll offset from
/// SwiftUI at all, so the bar moves with the content reliably.
struct ThinScrollView<Content: View>: NSViewRepresentable {
    private let axes: Axis.Set
    private let trailingGutter: CGFloat
    private let content: Content

    /// `trailingGutter`: width (in pt) of an empty strip reserved on the
    /// right edge of the clip view that the SwiftUI content does NOT
    /// extend into. The overlay scroller paints into this strip. Setting
    /// it > 0 sidesteps the recurring "scroller's left edge gets clipped
    /// by the SwiftUI hosting layer" bug entirely: with the hosting view
    /// physically stopping before the scroller's column, there's no
    /// overlap to z-fight over. Default 0 keeps the legacy overlay
    /// behaviour for menus where the content already pads itself.
    init(_ axes: Axis.Set = .vertical,
         trailingGutter: CGFloat = 0,
         @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.trailingGutter = trailingGutter
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = axes.contains(.vertical)
        scrollView.hasHorizontalScroller = axes.contains(.horizontal)
        scrollView.borderType = .noBorder
        // Legacy style: the overlay style runs a private NSScrollerImp
        // collapse/expand animation on the scroller's layer that we can't
        // intercept from the public NSView API. The collapse shrinks the
        // bar's bounds while idle, which clips our right-anchored knob's
        // left edge. Legacy doesn't collapse, so the knob stays at its
        // full width regardless of hover. The bar still effectively
        // disappears when content fits because `drawKnob()` short-circuits
        // at `knobProportion >= 0.999`.
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScrollElasticity = .allowed

        let scroller = ThinScroller()
        scroller.scrollerStyle = .legacy
        scroller.controlSize = .regular
        // The document view (NSHostingView) is layer-backed by SwiftUI,
        // and on macOS layer-backed siblings always composite above
        // non-layer-backed siblings regardless of subview order. Without
        // a layer of its own the scroller paints into the window backing
        // store and the SwiftUI layer covers it. Forcing wantsLayer
        // brings the scroller into the layer tree so the explicit z
        // order (scroller above clip view) is honoured.
        scroller.wantsLayer = true
        scrollView.verticalScroller = scroller

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hosting

        let clipView = scrollView.contentView
        clipView.wantsLayer = true

        // Sibling subview order alone isn't enough: the SwiftUI hosting
        // view's layer can still composite over the left edge of the
        // overlay knob in some layouts. Pinning the scroller's layer
        // zPosition above the clip view guarantees the knob always
        // paints on top, regardless of how AppKit orders the children.
        scroller.layer?.zPosition = 1
        scrollView.addSubview(scroller, positioned: .above, relativeTo: clipView)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: clipView.trailingAnchor,
                                              constant: -trailingGutter),
            hosting.topAnchor.constraint(equalTo: clipView.topAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hosting = scrollView.documentView as? NSHostingView<Content> {
            hosting.rootView = content
        }
    }
}

/// Mirrors the previous SwiftUI thumb 1:1 — 8pt-wide capsule, 3pt inset
/// from the trailing edge, white at 0.07 (0.14 hovered). The system can't
/// fade the bar out: `alphaValue` is pinned to 1 so the thumb stays put
/// whenever content overflows, matching the always-visible behaviour the
/// SwiftUI version had.
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        return 14
    }

    private static let verticalPad: CGFloat = 8
    private static let thumbWidth: CGFloat = 9
    private static let thumbInsetFromRight: CGFloat = 3
    private static let knobZPosition: CGFloat = 100

    private var mouseInside: Bool = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installLayer()
    }

    private func installLayer() {
        wantsLayer = true
        // Eagerly create the backing layer so the zPosition we set below
        // lands on an actual layer instead of being lost. Without this,
        // AppKit can defer layer creation past our first writes and leave
        // the scroller composited under the SwiftUI hosting view until a
        // later redraw (e.g. mouseEntered) finally reasserts the order.
        if layer == nil {
            layer = CALayer()
        }
        layer?.zPosition = ThinScroller.knobZPosition
    }

    private func trackRect() -> NSRect {
        let b = self.bounds
        let pad = ThinScroller.verticalPad
        let w = ThinScroller.thumbWidth
        let inset = ThinScroller.thumbInsetFromRight
        return NSRect(
            x: b.maxX - w - inset,
            y: b.minY + pad,
            width: w,
            height: max(0, b.height - pad * 2)
        )
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight: Bool) {
        // No track background.
    }

    override func rect(for part: NSScroller.Part) -> NSRect {
        guard part == .knob else { return super.rect(for: part) }
        let track = trackRect()
        let knobProp = max(0.05, min(1.0, CGFloat(self.knobProportion)))
        let thumbHeight = max(40, track.height * knobProp)
        let maxThumbY = max(0, track.height - thumbHeight)
        let progress = CGFloat(self.doubleValue)
        let thumbY = track.minY + maxThumbY * progress
        return NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Skip arrows / track entirely; only the knob renders.
        drawKnob()
    }

    override func drawKnob() {
        // No knob when the content fits — the whole point is that an
        // unscrollable list shouldn't show a bar.
        guard knobProportion < 0.999 else { return }
        let thumb = self.rect(for: .knob)
        guard thumb.width > 0, thumb.height > 0 else { return }
        let radius = min(thumb.width, thumb.height) / 2
        let path = NSBezierPath(roundedRect: thumb, xRadius: radius, yRadius: radius)
        let alpha: CGFloat = mouseInside ? 0.18 : 0.10
        NSColor(white: 1.0, alpha: alpha).setFill()
        path.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        needsDisplay = true
    }

    // Defeat the system's overlay-scroller fade-out. The scroll view will
    // still pin alpha to 0 when the scroller is unused (knob proportion
    // ~1), but `drawKnob` already short-circuits in that case, so this is
    // safe — we just refuse to fade while there's something to scroll.
    override var alphaValue: CGFloat {
        get { super.alphaValue }
        set { super.alphaValue = 1.0 }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        super.alphaValue = 1.0
        // Re-assert z-order after AppKit reattaches the scroller. Without
        // this the knob's left edge can disappear under the SwiftUI
        // hosting layer when the scroll view is re-tiled.
        layer?.zPosition = ThinScroller.knobZPosition
    }

    // Re-pin zPosition on every layout pass: the SwiftUI hosting view's
    // layer composites above ours unless this stays high, and AppKit can
    // reset implicit layer state during overlay-scroller re-tiles.
    override func layout() {
        super.layout()
        layer?.zPosition = ThinScroller.knobZPosition
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        layer?.zPosition = ThinScroller.knobZPosition
    }
}

// MARK: - ThinScrollerInstaller
//
// Swaps the system NSScroller of a SwiftUI `ScrollView` with our
// `ThinScroller` so the chat (and any other view that needs a real
// `ScrollViewReader`) gets the same low-opacity, thin capsule as the
// sidebar without giving up SwiftUI's programmatic scrolling.
//
// SwiftUI's ScrollView is backed by an NSScrollView at runtime, but it
// doesn't expose the scroller. The trick is to drop a hidden NSView
// sibling inside the scroll view's content via `.background`, then walk
// up the superview chain to find the NSScrollView and replace its
// verticalScroller. We re-apply on every `viewDidMoveToWindow` and on
// the next runloop after layout in case AppKit re-tiles.
struct ThinScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> ThinScrollerInstallerView {
        ThinScrollerInstallerView()
    }

    func updateNSView(_ nsView: ThinScrollerInstallerView, context: Context) {
        nsView.installIfNeeded()
    }
}

final class ThinScrollerInstallerView: NSView {
    private weak var installedScrollView: NSScrollView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.installIfNeeded()
        }
    }

    func installIfNeeded() {
        guard installedScrollView == nil || installedScrollView?.verticalScroller is ThinScroller == false else {
            return
        }
        var current: NSView? = self.superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                attachThinScroller(to: scrollView)
                installedScrollView = scrollView
                return
            }
            current = view.superview
        }
    }

    private func attachThinScroller(to scrollView: NSScrollView) {
        let scroller = ThinScroller()
        scroller.scrollerStyle = .overlay
        scroller.controlSize = .regular
        scroller.wantsLayer = true

        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = scroller

        scroller.layer?.zPosition = 1
        if let clipView = scrollView.contentView as NSClipView? {
            clipView.wantsLayer = true
            scrollView.addSubview(scroller, positioned: .above, relativeTo: clipView)
        }
    }
}

extension View {
    /// Replace the underlying SwiftUI `ScrollView`'s vertical scroller
    /// with the same thin, low-opacity capsule used by the sidebar.
    func thinScrollers() -> some View {
        background(ThinScrollerInstaller().allowsHitTesting(false))
    }
}
