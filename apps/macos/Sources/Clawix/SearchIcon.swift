import SwiftUI

/// Custom magnifying glass icon used in place of SF Symbols `magnifyingglass`.
/// Lens diameter ~66% of the grid and a short 45° handle (0.65 × radius),
/// centered as a single bbox so it visually replaces the SF Symbol without
/// shifting alignment.
struct SearchIcon: View {
    var size: CGFloat = 14

    var body: some View {
        SearchIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 3.15 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct SearchIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        let circleOrigin: CGFloat = 1.5
        let circleDiameter: CGFloat = 23.06
        let handleStart: CGFloat = 21.19
        let handleEnd: CGFloat = 26.49

        var path = Path()
        path.addEllipse(in: CGRect(
            x: dx + circleOrigin * s,
            y: dy + circleOrigin * s,
            width:  circleDiameter * s,
            height: circleDiameter * s
        ))
        path.move(to: p(handleStart, handleStart))
        path.addLine(to: p(handleEnd, handleEnd))
        return path
    }
}
