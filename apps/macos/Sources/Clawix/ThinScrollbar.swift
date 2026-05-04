import SwiftUI
import AppKit

/// SwiftUI scroll container backed by a real `NSScrollView` and a custom
/// `NSScroller` that paints a thin, low-opacity capsule. Scrolling and
/// thumb tracking are 100% native — we don't observe scroll offset from
/// SwiftUI at all, so the bar moves with the content reliably.
struct ThinScrollView<Content: View>: NSViewRepresentable {
    private let axes: Axis.Set
    private let content: Content

    init(_ axes: Axis.Set = .vertical, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = axes.contains(.vertical)
        scrollView.hasHorizontalScroller = axes.contains(.horizontal)
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed

        let scroller = ThinScroller()
        scroller.scrollerStyle = .overlay
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
            hosting.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
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
    private static let thumbWidth: CGFloat = 8
    private static let thumbInsetFromRight: CGFloat = 3

    private var mouseInside: Bool = false
    private var trackingArea: NSTrackingArea?

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
        let alpha: CGFloat = mouseInside ? 0.14 : 0.07
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
        layer?.zPosition = 1
    }
}
