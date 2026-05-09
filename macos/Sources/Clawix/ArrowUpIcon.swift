import SwiftUI

/// Custom up-arrow icon used in send buttons (composer, QuickAsk) and
/// keyboard hints. Replaces `LucideIcon(.arrowUp, …)` so the chevron
/// apex carries a softer squircle round (continuous-curvature, not the
/// font's stroke-linejoin) and the tail extends a touch longer for a
/// slightly more confident silhouette.
struct ArrowUpIcon: View {
    var size: CGFloat = 14

    var body: some View {
        ArrowUpIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ArrowUpIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        // Chevron with squircle-rounded apex (cubic with tangent-matched
        // controls along the 45-degree arms, peak just above y = 5.75).
        path.move(to: p(5, 14))
        path.addLine(to: p(12.5, 6.5))
        path.addCurve(
            to: p(15.5, 6.5),
            control1: p(13.5, 5.5),
            control2: p(14.5, 5.5)
        )
        path.addLine(to: p(23, 14))
        // Tail. Lucide's reaches y=22.17 (in this grid); we run to 24 so
        // the stem sits a hair longer than the original glyph.
        path.move(to: p(14, 24))
        path.addLine(to: p(14, 5.75))
        return path
    }
}
