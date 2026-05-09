import SwiftUI

/// Custom Clawix CPU icon for the Local models settings page. Squircle
/// body (4 cubic Bézier sides on a 24-pt grid: anchors at the side
/// midpoints, controls inset ~9% of the body width from the adjacent
/// corner so the sides stay flat and the corners get a continuous-
/// curvature roll) and two stub pins protruding from each side at 9 /
/// 15. Replaces the SF Symbol `cpu` so the glyph matches the rest of
/// the custom icon set.
struct LocalModelsIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        let s = size / 24
        let lw = lineWidth ?? 2.4 * s
        LocalModelsIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lw,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct LocalModelsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(6, 12))
        path.addCurve(to: p(12, 6),
                      control1: p(6, 7.1),   control2: p(7.1, 6))
        path.addCurve(to: p(18, 12),
                      control1: p(16.9, 6),  control2: p(18, 7.1))
        path.addCurve(to: p(12, 18),
                      control1: p(18, 16.9), control2: p(16.9, 18))
        path.addCurve(to: p(6, 12),
                      control1: p(7.1, 18),  control2: p(6, 16.9))
        path.closeSubpath()

        path.move(to: p(9, 2));   path.addLine(to: p(9, 6))
        path.move(to: p(15, 2));  path.addLine(to: p(15, 6))
        path.move(to: p(9, 18));  path.addLine(to: p(9, 22))
        path.move(to: p(15, 18)); path.addLine(to: p(15, 22))
        path.move(to: p(2, 9));   path.addLine(to: p(6, 9))
        path.move(to: p(2, 15));  path.addLine(to: p(6, 15))
        path.move(to: p(18, 9));  path.addLine(to: p(22, 9))
        path.move(to: p(18, 15)); path.addLine(to: p(22, 15))

        return path
    }
}
