import SwiftUI

/// Custom new-conversation glyph: open rounded square with a tilted
/// pencil exiting through the top-right corner. Built around a 45 deg
/// pencil axis so the eraser cap (true semicircle), the shoulder
/// fillets, and the tip apex stay symmetric about that axis.
struct ComposeIcon: View {
    var size: CGFloat = 14

    var body: some View {
        ComposeIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.7 * (size / 24),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ComposeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        // Box (open rounded square, corner radius 5.5 in 24-grid).
        path.move(to: p(10.5, 1.5))
        path.addLine(to: p(7, 1.5))
        path.addCurve(to: p(1.5, 7),
                      control1: p(3.96, 1.5),
                      control2: p(1.5, 3.96))
        path.addLine(to: p(1.5, 17))
        path.addCurve(to: p(7, 22.5),
                      control1: p(1.5, 20.04),
                      control2: p(3.96, 22.5))
        path.addLine(to: p(17, 22.5))
        path.addCurve(to: p(22.5, 17),
                      control1: p(20.04, 22.5),
                      control2: p(22.5, 20.04))
        path.addLine(to: p(22.5, 13.5))

        // Pencil (45 deg axis from eraser center (20, 4) to tip apex
        // (7.17, 16.83), body half-width 3). Eraser is a true
        // semicircle, the two shoulders and the tip apex are filleted.
        // Arcs are written as two-cubic Bezier approximations so the
        // geometry renders identically on iOS and macOS.
        path.move(to: p(17.88, 1.88))
        path.addCurve(to: p(22.12, 1.88),
                      control1: p(19.05, 0.71),
                      control2: p(20.95, 0.71))
        path.addCurve(to: p(22.12, 6.12),
                      control1: p(23.29, 3.05),
                      control2: p(23.29, 4.95))
        path.addLine(to: p(13.45, 14.79))
        path.addCurve(to: p(12.81, 15.17),
                      control1: p(13.27, 14.97),
                      control2: p(13.05, 15.10))
        path.addLine(to: p(8.58, 16.42))
        path.addCurve(to: p(7.78, 16.22),
                      control1: p(8.30, 16.50),
                      control2: p(7.99, 16.43))
        path.addCurve(to: p(7.58, 15.42),
                      control1: p(7.57, 16.01),
                      control2: p(7.50, 15.70))
        path.addLine(to: p(8.83, 11.19))
        path.addCurve(to: p(9.21, 10.55),
                      control1: p(8.90, 10.95),
                      control2: p(9.03, 10.73))
        path.closeSubpath()
        return path
    }
}
