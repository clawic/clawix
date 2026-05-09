import SwiftUI

/// Custom Clawix usage gauge icon. A near-complete circle with a 90°
/// opening at the bottom and a teardrop needle pointing NE drawn on a
/// 24-pt grid so it tints with `.foregroundColor` and stays crisp at
/// 11–14 pt point sizes. Replaces SF Symbols `chart.bar` and
/// `gauge.with.dots.needle.33percent` everywhere we surface usage
/// limits, so the visual matches the rest of the custom icon set.
///
/// Geometry (24-grid, y-down): arc r=9 centered at (12, 12) with
/// endpoints at angles 135° (5.64, 18.36) and 45° (18.36, 18.36)
/// going through the top of the canvas. The 270° arc is approximated
/// with three cubic bezier segments of 90° each (Bezier magic
/// constant `(4/3)·tan(22.5°) ≈ 0.5523`, control distance ≈ 4.97).
/// Needle tip at (16.60, 7.40); rounded back centered at (12, 12)
/// with radius 2.4; body curves are tangent-continuous with the back
/// arc, only the tip is a sharp corner so the silhouette reads as
/// "afilada" but soft. The wider back vs the narrow tip gives the
/// needle visible variance between its fat and pointy halves.
struct UsageIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        let s = size / 24
        let lw = lineWidth ?? 1.6 * s
        ZStack {
            UsageGaugeArcShape()
                .stroke(style: StrokeStyle(
                    lineWidth: lw,
                    lineCap: .round,
                    lineJoin: .round
                ))
            UsageNeedleShape()
        }
        .frame(width: size, height: size)
    }
}

private struct UsageGaugeArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(5.64, 18.36))
        path.addCurve(to: p(5.64, 5.64),
                      control1: p(2.125, 14.845), control2: p(2.125, 9.155))
        path.addCurve(to: p(18.36, 5.64),
                      control1: p(9.155, 2.125),  control2: p(14.845, 2.125))
        path.addCurve(to: p(18.36, 18.36),
                      control1: p(21.875, 9.155), control2: p(21.875, 14.845))
        return path
    }
}

private struct UsageNeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(16.60, 7.40))
        path.addCurve(to: p(13.70, 13.70),
                      control1: p(17.02, 8.38),  control2: p(14.40, 12.99))
        path.addCurve(to: p(10.30, 13.70),
                      control1: p(12.76, 14.63), control2: p(11.24, 14.63))
        path.addCurve(to: p(10.30, 10.30),
                      control1: p(9.37, 12.76),  control2: p(9.37, 11.24))
        path.addCurve(to: p(16.60, 7.40),
                      control1: p(11.01, 9.60),  control2: p(15.62, 6.98))
        path.closeSubpath()
        return path
    }
}
