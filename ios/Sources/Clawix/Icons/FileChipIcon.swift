import SwiftUI

/// Custom file/document icon used as the leading glyph in file chips and
/// the changed-file row. Hand-drawn page with a rounded squircle outline,
/// a softly folded top-right corner, and two interior horizontal "text"
/// lines (top one slightly higher and longer than the bottom).
struct FileChipIcon: View {
    /// Total height in pt. Width auto-scales to keep the page's aspect ratio.
    var size: CGFloat = 14

    var body: some View {
        FileChipIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.8 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size * 26 / 28, height: size)
    }
}

private struct FileChipIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 26, rect.height / 28)
        let dx = (rect.width - 26 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(7, 1))
        path.addArc(tangent1End: p(17, 1), tangent2End: p(24, 8), radius: 4 * s)
        path.addArc(tangent1End: p(24, 8), tangent2End: p(24, 26), radius: 4 * s)
        path.addArc(tangent1End: p(24, 26), tangent2End: p(2, 26), radius: 5 * s)
        path.addArc(tangent1End: p(2, 26), tangent2End: p(2, 1), radius: 5 * s)
        path.addArc(tangent1End: p(2, 1), tangent2End: p(7, 1), radius: 5 * s)
        path.closeSubpath()

        path.move(to: p(7.5, 11))
        path.addLine(to: p(15, 11))
        path.move(to: p(7.5, 17.5))
        path.addLine(to: p(11.5, 17.5))

        return path
    }
}
