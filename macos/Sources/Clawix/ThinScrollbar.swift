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
        if axes.contains(.vertical) {
            scrollView.verticalScroller = scroller
        }

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
        if axes.contains(.vertical) {
            scrollView.addSubview(scroller, positioned: .above, relativeTo: clipView)
        }
        if axes.contains(.horizontal) {
            let horizontal = ThinScroller()
            horizontal.scrollerStyle = .legacy
            horizontal.controlSize = .regular
            horizontal.wantsLayer = true
            scrollView.horizontalScroller = horizontal
            horizontal.layer?.zPosition = 1
            scrollView.addSubview(horizontal, positioned: .above, relativeTo: clipView)
        }
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

    private var isHorizontal: Bool {
        // The scroller's bounds are laid out by NSScrollView along its
        // dominant axis, so a wider-than-tall frame implies a horizontal
        // scroller (bottom edge of the scroll view). Vertical scrollers
        // sit on the right edge with bounds taller than wide.
        return bounds.width > bounds.height
    }

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
        let thickness = ThinScroller.thumbWidth
        let inset = ThinScroller.thumbInsetFromRight
        if isHorizontal {
            // Bottom-anchored thin capsule, mirrors the right-anchored
            // vertical layout: same numbers swapped along axes.
            return NSRect(
                x: b.minX + pad,
                y: b.maxY - thickness - inset,
                width: max(0, b.width - pad * 2),
                height: thickness
            )
        }
        return NSRect(
            x: b.maxX - thickness - inset,
            y: b.minY + pad,
            width: thickness,
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
        let progress = CGFloat(self.doubleValue)
        if isHorizontal {
            let thumbWidth = max(40, track.width * knobProp)
            let maxThumbX = max(0, track.width - thumbWidth)
            let thumbX = track.minX + maxThumbX * progress
            return NSRect(x: thumbX, y: track.minY, width: thumbWidth, height: track.height)
        }
        let thumbHeight = max(40, track.height * knobProp)
        let maxThumbY = max(0, track.height - thumbHeight)
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
    private let style: NSScroller.Style

    init(style: NSScroller.Style = .overlay) {
        self.style = style
    }

    func makeNSView(context: Context) -> ThinScrollerInstallerView {
        ThinScrollerInstallerView(style: style)
    }

    func updateNSView(_ nsView: ThinScrollerInstallerView, context: Context) {
        nsView.installIfNeeded()
    }
}

final class ThinScrollerInstallerView: NSView {
    private weak var installedScrollView: NSScrollView?
    private let style: NSScroller.Style

    init(style: NSScroller.Style) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.installIfNeeded()
        }
    }

    func installIfNeeded() {
        // Re-install when either the vertical or the horizontal scroller
        // is still the system one. AppKit can re-tile a scroll view (e.g.
        // when its axis flips after a `showsIndicators` update or when a
        // SwiftUI parent rebuilds the host view) and replace our scroller
        // with a fresh `NSScroller`; the second condition catches that.
        if let already = installedScrollView,
           already.verticalScroller is ThinScroller,
           (!already.hasHorizontalScroller || already.horizontalScroller is ThinScroller) {
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
        scrollView.scrollerStyle = style
        // `.overlay` autohides while idle; `.legacy` keeps the scroller
        // permanently visible (its 14pt column lives outside the clipView,
        // so the knob can't get clipped by the SwiftUI hosting layer or
        // by the private collapse animation).
        scrollView.autohidesScrollers = (style == .overlay)

        let clipView = scrollView.contentView
        clipView.wantsLayer = true

        // Vertical scroller is installed unconditionally: a SwiftUI
        // `ScrollView` with a vertical or default axis maps to an
        // NSScrollView that needs the vertical scroller swap. For
        // horizontal-only scroll views the overlay autohides the unused
        // vertical scroller, so this is a no-op visually.
        let vertical = ThinScroller()
        vertical.scrollerStyle = style
        vertical.controlSize = .regular
        vertical.wantsLayer = true
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = vertical
        vertical.layer?.zPosition = 1
        if style == .overlay {
            scrollView.addSubview(vertical, positioned: .above, relativeTo: clipView)
        }

        // If the scroll view already exposes a horizontal scroller (axis
        // includes `.horizontal`), swap it for the same thin capsule
        // anchored at the bottom edge. We do not force-enable the
        // horizontal scroller for vertical-only scroll views: that would
        // either reserve a phantom strip or paint a bar where the user
        // didn't ask for one.
        if scrollView.hasHorizontalScroller {
            let horizontal = ThinScroller()
            horizontal.scrollerStyle = style
            horizontal.controlSize = .regular
            horizontal.wantsLayer = true
            scrollView.horizontalScroller = horizontal
            horizontal.layer?.zPosition = 1
            if style == .overlay {
                scrollView.addSubview(horizontal, positioned: .above, relativeTo: clipView)
            }
        }
    }
}

extension View {
    /// Replace the underlying SwiftUI `ScrollView`'s vertical scroller
    /// with the same thin, low-opacity capsule used by the sidebar.
    func thinScrollers(style: NSScroller.Style = .overlay) -> some View {
        background(ThinScrollerInstaller(style: style).allowsHitTesting(false))
    }
}
