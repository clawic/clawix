import SwiftUI

/// "Open externally" icon: an outlined squircle with the top-right
/// corner open and an arrow exiting through the gap. Replaces the SF
/// Symbol `arrow.up.right.square` in places where the rest of the
/// chrome is custom-drawn (folder family, file chip). 24-grid viewBox,
/// hairline stroke that scales with `size`, rounded caps and joins.
struct ExternalLinkIcon: View {
    var size: CGFloat = 13

    var body: some View {
        ExternalLinkIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.7 * (size / 24),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct ExternalLinkIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        // Open squircle: starts at the right-edge top terminal, traces
        // bottom-right corner, bottom edge, bottom-left corner, left
        // edge, top-left corner. Top-right corner stays open so the
        // arrow can exit through the gap.
        path.move(to: p(20, 14))
        path.addCurve(to: p(13, 20),
                      control1: p(20, 19), control2: p(19, 20))
        path.addLine(to: p(11, 20))
        path.addCurve(to: p(4, 13),
                      control1: p(5, 20), control2: p(4, 19))
        path.addLine(to: p(4, 11))
        path.addCurve(to: p(10, 4),
                      control1: p(4, 5), control2: p(5, 4))

        // Arrow diagonal from inside the box to the outer corner.
        path.move(to: p(13, 11))
        path.addLine(to: p(21, 3))

        // Arrowhead L at the upper-right corner.
        path.move(to: p(15, 3))
        path.addLine(to: p(21, 3))
        path.addLine(to: p(21, 9))

        return path
    }
}
