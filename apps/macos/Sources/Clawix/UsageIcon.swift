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
/// Needle tip at (15.89, 8.11); rounded back centered at (12, 12)
/// with radius 1.8; body curves are tangent-continuous with the back
/// arc, only the tip is a sharp corner so the silhouette reads as
/// "afilada" but soft.
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
        path.move(to: p(15.89, 8.11))
        path.addCurve(to: p(13.27, 13.27),
                      control1: p(16.31, 9.08),  control2: p(13.98, 12.56))
        path.addCurve(to: p(10.73, 13.27),
                      control1: p(12.57, 13.97), control2: p(11.43, 13.97))
        path.addCurve(to: p(10.73, 10.73),
                      control1: p(10.03, 12.57), control2: p(10.03, 11.43))
        path.addCurve(to: p(15.89, 8.11),
                      control1: p(11.44, 10.02), control2: p(14.93, 7.69))
        path.closeSubpath()
        return path
    }
}
