import SwiftUI

/// Custom padlock icon used across the Secrets feature and the Tools entry
/// in the sidebar. Drawn from cubic-Bézier squircle paths (continuous
/// curvature at every join) instead of arcs, to match the project's other
/// custom glyphs. When `isLocked` is false the right side of the shackle
/// lifts, suggesting an open lock.
struct SecretsIcon: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.28
    var color: Color = Color(white: 0.86)
    var isLocked: Bool = true

    var body: some View {
        Canvas { context, sz in
            let s = min(sz.width, sz.height) / 24

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: y * s)
            }

            var body = Path()
            body.move(to: p(7, 11))
            body.addLine(to: p(17, 11))
            body.addCurve(to: p(20, 14), control1: p(18.6, 11), control2: p(20, 12.4))
            body.addLine(to: p(20, 19))
            body.addCurve(to: p(17, 22), control1: p(20, 20.6), control2: p(18.6, 22))
            body.addLine(to: p(7, 22))
            body.addCurve(to: p(4, 19), control1: p(5.4, 22), control2: p(4, 20.6))
            body.addLine(to: p(4, 14))
            body.addCurve(to: p(7, 11), control1: p(4, 12.4), control2: p(5.4, 11))
            body.closeSubpath()

            var shackle = Path()
            shackle.move(to: p(7, 11))
            shackle.addLine(to: p(7, 7))
            shackle.addCurve(to: p(12, 2), control1: p(7, 3.5), control2: p(9, 2))
            if isLocked {
                shackle.addCurve(to: p(17, 7), control1: p(15, 2), control2: p(17, 3.5))
                shackle.addLine(to: p(17, 11))
            } else {
                shackle.addCurve(to: p(18, 4), control1: p(15, 2), control2: p(17, 2.5))
            }

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(body, with: .color(color), style: stroke)
            context.stroke(shackle, with: .color(color), style: stroke)
        }
        .frame(width: size, height: size)
    }
}
