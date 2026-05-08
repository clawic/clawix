import SwiftUI

/// "Open in app" icon: an open-corner squircle whose bottom-right
/// quadrant is removed, paired with a smaller squircle nested in the
/// missing corner (sharing its imaginary BR vertex with the big one),
/// and a small TL-style isolated corner accent floating in the
/// diagonal gap between the two. Replaces the SF Symbol
/// `arrow.up.right.square` in QuickAsk's hover controls so the
/// "send this conversation back to the main Clawix window" action
/// reads as "stack this into another container", in keeping with the
/// rest of the custom-drawn chrome around it. 24-grid viewBox; the
/// caller strokes it with `lineCap: .round` and `lineJoin: .round`.
struct OpenInAppIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        func len(_ v: CGFloat) -> CGFloat { v * s }

        var path = Path()

        // Big squircle, traced as an open path. Starts ~0.6u into the
        // BL arc at (5.5, 21.5) so the cut sits on the curve itself
        // rather than on a flat bottom-edge stub; runs BL → left →
        // TL → top → TR; ends symmetrically inside the TR arc at
        // (21.5, 5.5). The bottom-right quadrant is fully missing.
        path.move(to: p(5.5, 21.5))
        path.addArc(
            center: p(6.1, 16.9),
            radius: len(4.6),
            startAngle: .degrees(97.49),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: p(1.5, 6.1))
        path.addArc(
            center: p(6.1, 6.1),
            radius: len(4.6),
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: p(16.9, 1.5))
        path.addArc(
            center: p(16.9, 6.1),
            radius: len(4.6),
            startAngle: .degrees(270),
            endAngle: .degrees(352.51),
            clockwise: false
        )

        // Small squircle nested in the missing corner. Its BR
        // (21.5, 21.5) coincides with the imaginary BR vertex of the
        // big square.
        path.addRoundedRect(
            in: CGRect(
                x: dx + 9.7 * s,
                y: dy + 9.7 * s,
                width: 11.8 * s,
                height: 11.8 * s
            ),
            cornerSize: CGSize(width: len(3), height: len(3))
        )

        // Corner accent: TL-style L floating in the diagonal gap.
        // Vertex (imaginary) at (5.7, 5.7); the curve replaces the
        // 90° angle with a squircle quarter, and the two 3.3u-long
        // legs extend down and right. Bounding box centered at
        // (~7.2, 7.2), the midpoint of where each squircle's TL arc
        // crosses the y=x diagonal.
        path.move(to: p(5.7, 9.0))
        path.addLine(to: p(5.7, 7.2))
        path.addArc(
            center: p(7.2, 7.2),
            radius: len(1.5),
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: p(9.0, 5.7))

        return path
    }
}
