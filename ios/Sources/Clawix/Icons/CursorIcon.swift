import SwiftUI

/// Custom cursor / pointer icon used whenever the work summary surfaces
/// integrated-browser activity (the agent driving a real browser through
/// the codex `browser` tool). Drawn with `Path` in a 28-point grid so it
/// tints with `.foregroundColor` and stays crisp at 11 to 14 pt point
/// sizes.
struct CursorIcon: View {
    var size: CGFloat = 14

    var body: some View {
        CursorIconShape()
            .frame(width: size, height: size)
    }
}

private struct CursorIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(9.00, 6.22))
        path.addLine(to: p(19.28, 9.74))
        path.addQuadCurve(to: p(19.43, 13.01), control: p(23.52, 11.20))
        path.addLine(to: p(17.03, 14.08))
        path.addQuadCurve(to: p(14.08, 17.03), control: p(14.98, 14.98))
        path.addLine(to: p(13.01, 19.43))
        path.addQuadCurve(to: p(9.74, 19.28), control: p(11.20, 23.52))
        path.addLine(to: p(6.22, 9.00))
        path.addQuadCurve(to: p(9.00, 6.22), control: p(4.76, 4.76))
        path.closeSubpath()
        return path
    }
}
