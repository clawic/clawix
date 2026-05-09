import SwiftUI

/// Filled "stop" glyph used wherever the composer or voice recorder
/// shows a Stop affordance: composer's interrupt button when an
/// assistant turn is active, the recorder's stop pill, the QuickAsk
/// stop bubble. Drawn as a true superellipse (Apple's iOS app-icon
/// mask shape) instead of `RoundedRectangle(.continuous)` so the
/// curvature builds smoothly across the full edge instead of meeting a
/// straight midsection. Mirrors the iOS `StopSquircle` so both targets
/// render the same glyph.
struct StopSquircle: Shape {
    /// Superellipse exponent. `n = 2` is a circle, `n → ∞` is a
    /// square. `n = 5` matches the iOS app-icon mask and is the
    /// stop-button shape we want everywhere.
    var n: Double = 5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let cy = rect.midY
        let a = rect.width / 2
        let b = rect.height / 2
        let segments = 96
        for i in 0...segments {
            let t = Double(i) / Double(segments) * 2 * .pi
            let cosT = cos(t)
            let sinT = sin(t)
            let x = cx + CGFloat(copysign(pow(abs(cosT), 2.0 / n), cosT)) * a
            let y = cy + CGFloat(copysign(pow(abs(sinT), 2.0 / n), sinT)) * b
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }
        p.closeSubpath()
        return p
    }
}
