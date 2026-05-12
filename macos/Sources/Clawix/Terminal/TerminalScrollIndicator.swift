import AppKit

/// Thin overlay that paints a `ThinScroller`-style capsule mirroring
/// SwiftTerm's hidden native NSScroller. We can't replace SwiftTerm's
/// scroller in-place (it's wired with target/action internal to the
/// terminal view), so this overlay observes its `knobProportion` /
/// `doubleValue` via KVO and forwards mouseDown/dragged to it so click
/// and drag on the visible thin bar still scroll the buffer.
///
/// Match for `ThinScroller` (chat/sidebar): 9pt-wide capsule, 3pt inset
/// from the trailing edge, white at 0.10 idle / 0.18 hovered.
final class TerminalScrollIndicator: NSView {
    private weak var source: NSScroller?
    private var knobProportionObs: NSKeyValueObservation?
    private var doubleValueObs: NSKeyValueObservation?
    private var trackingArea: NSTrackingArea?

    private static let verticalPad: CGFloat = 8
    private static let thumbWidth: CGFloat = 9
    private static let thumbInsetFromRight: CGFloat = 3

    private var hovered: Bool = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { false }

    func attach(to scroller: NSScroller) {
        guard scroller !== source else { return }
        source = scroller
        knobProportionObs = scroller.observe(\.knobProportion, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
        doubleValueObs = scroller.observe(\.doubleValue, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
        needsDisplay = true
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

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        // Forward to the underlying scroller so click-on-track and
        // drag-the-knob both translate into real scrollback movement.
        source?.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let source = source else { return }
        let knobProportion = CGFloat(source.knobProportion)
        // No bar when the content fits inside the viewport.
        guard knobProportion < 0.999 else { return }
        let progress = CGFloat(source.doubleValue)
        let pad = Self.verticalPad
        let thickness = Self.thumbWidth
        let inset = Self.thumbInsetFromRight

        let track = NSRect(
            x: bounds.maxX - thickness - inset,
            y: bounds.minY + pad,
            width: thickness,
            height: max(0, bounds.height - pad * 2)
        )
        let thumbHeight = max(40, track.height * knobProportion)
        // `doubleValue` is 0 at the top of the scrollable content and 1
        // at the bottom. The view is not flipped (`isFlipped == false`),
        // so y=0 is the bottom and the top of the track is `track.maxY`.
        // progress 0 → thumb pinned to the top of the track;
        // progress 1 → thumb pinned to the bottom.
        let thumbY = track.minY + (track.height - thumbHeight) * (1 - progress)
        let rect = NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight)
        let radius = thickness / 2
        let alpha: CGFloat = hovered ? 0.18 : 0.10
        NSColor(white: 1.0, alpha: alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}
