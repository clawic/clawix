import SwiftUI

/// Custom check glyph that replaces lucide-check across the chat,
/// composer, dropdowns and settings UI. Same anchors as lucide
/// (`(20, 6) → (9, 17) → (4, 12)` on a 24-pt grid) so it still reads
/// as a tick, but the 90° elbow at `(9, 17)` is rebuilt with the
/// continuous-corner squircle math the rest of the project's custom
/// glyphs use (see `BotIcon`, `WrenchIcon`): three cubic Béziers with
/// the Apple app-icon magic ratios and corner extension `E = 1.4`.
struct CheckIcon: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat? = nil

    var body: some View {
        CheckIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth ?? (2.0 * (size / 24)),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct CheckIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(20, 6))
        path.addLine(to: p(9.99, 16.01))

        // Squircle elbow (E = 1.4): three cubics with Apple's app-icon
        // ratios mapped onto the 90° turn between the down-left
        // incoming leg and the up-left outgoing leg.
        path.addCurve(to: p(9.26, 16.60),
                      control1: p(9.64, 16.36),
                      control2: p(9.47, 16.54))
        path.addCurve(to: p(8.74, 16.60),
                      control1: p(9.09, 16.66),
                      control2: p(8.91, 16.66))
        path.addCurve(to: p(8.01, 16.01),
                      control1: p(8.53, 16.54),
                      control2: p(8.36, 16.36))

        path.addLine(to: p(4, 12))

        return path
    }
}
