import SwiftUI

/// Custom sign-out icon used in place of SF Symbols
/// `rectangle.portrait.and.arrow.right`. Drawn on a 28-pt grid so it
/// matches the stroke language of `SettingsIcon`, `SearchIcon`, etc.
///
/// Reads as "leave the room": a tall C-shape on the left (top-left and
/// bottom-left corners squircle-soft, no right wall at all) and a 45°
/// chevron arrow exiting to the right. Stroke width follows the
/// `2.5 * (size / 28)` baseline used across the custom icon set, with
/// optional override for adjacent-icon parity.
struct SignOutIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        let s = size / 28
        let lw = lineWidth ?? 2.5 * s
        SignOutIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lw,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct SignOutIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        // Cubic bezier handle for a quarter-circle: 4*(sqrt(2)-1)/3.
        let r: CGFloat = 3.5
        let h: CGFloat = 0.5522847 * r

        var path = Path()

        // Top stub
        path.move(to: p(10.033, 3.5))
        path.addLine(to: p(7, 3.5))
        // Top-left rounded corner
        path.addCurve(
            to: p(3.5, 7),
            control1: p(7 - h, 3.5),
            control2: p(3.5, 7 - h)
        )
        // Left wall
        path.addLine(to: p(3.5, 21))
        // Bottom-left rounded corner
        path.addCurve(
            to: p(7, 24.5),
            control1: p(3.5, 21 + h),
            control2: p(7 - h, 24.5)
        )
        // Bottom stub
        path.addLine(to: p(10.033, 24.5))

        // Arrow shaft
        path.move(to: p(11.667, 14))
        path.addLine(to: p(23.333, 14))

        // Arrowhead chevron (45°, 4-unit reach in the original 24-grid)
        path.move(to: p(18.667, 9.333))
        path.addLine(to: p(23.333, 14))
        path.addLine(to: p(18.667, 18.667))

        return path
    }
}
