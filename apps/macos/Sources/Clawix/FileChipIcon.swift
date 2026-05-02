import SwiftUI

/// Custom file/document icon used as the leading glyph in the composer
/// attachment chip when a non-image file is attached. Replaces the SF Symbol
/// `doc` family with a hand-drawn page that matches the project's logo:
/// rounded squircle outline, softly cut top-right corner, and two interior
/// horizontal "text" lines (top one slightly higher and longer than the bottom).
struct FileChipIcon: View {
    /// Total height in pt. Width auto-scales to keep the page's aspect ratio.
    var size: CGFloat = 14

    var body: some View {
        FileChipIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.1 * (size / 28),
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

        path.move(to: p(4, 0))
        path.addLine(to: p(19, 0))
        path.addQuadCurve(to: p(20.4, 0.6), control: p(20, 0))
        path.addLine(to: p(25.4, 5.6))
        path.addQuadCurve(to: p(26, 7), control: p(26, 6))
        path.addLine(to: p(26, 24))
        path.addArc(tangent1End: p(26, 28), tangent2End: p(22, 28), radius: 4 * s)
        path.addLine(to: p(4, 28))
        path.addArc(tangent1End: p(0, 28), tangent2End: p(0, 24), radius: 4 * s)
        path.addLine(to: p(0, 4))
        path.addArc(tangent1End: p(0, 0), tangent2End: p(4, 0), radius: 4 * s)
        path.closeSubpath()

        path.move(to: p(5.5, 11))
        path.addLine(to: p(17.5, 11))
        path.move(to: p(5.5, 17.5))
        path.addLine(to: p(14, 17.5))

        return path
    }
}
