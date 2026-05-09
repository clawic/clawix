import SwiftUI

/// Custom wrench/tool icon used as the leading icon of the "Tools" section
/// header in the sidebar. Outline drawn directly with SwiftUI `Path` so it
/// tints with `.foregroundColor` and scales without a PDF asset round trip,
/// matching the rest of the project's custom glyphs (`ArchiveIcon`,
/// `SecretsIcon`, `PinIcon`, `SettingsIcon`).
///
/// Silhouette is the canonical "wrench gripping a hex bolt" shape on a
/// 24-pt grid: a head with a hex notch cut into the upper-left, a diagonal
/// shaft going lower-left, and a rounded cap at the handle end. Each arc
/// segment is approximated by one or two cubic Béziers (kappa ≈ 0.5523 for
/// 90° quarter arcs, plus a generic factor for the wider 130° head curves)
/// so continuous curvature is preserved at every join.
struct WrenchIcon: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat? = nil

    var body: some View {
        WrenchIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth ?? (1.6 * (size / 24)),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct WrenchIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        // Inner notch: starts at the upper inner edge of the hex bite, traces
        // the four visible faces of where the bolt sits, and exits on the
        // outer right side of the head. Two quarter arcs + a diagonal line
        // between them, mirroring the lucide-wrench silhouette.
        path.move(to: p(14.7, 6.3))
        path.addCurve(to: p(14.7, 7.7),
                      control1: p(14.306, 6.687),
                      control2: p(14.306, 7.313))
        path.addLine(to: p(16.3, 9.3))
        path.addCurve(to: p(17.7, 9.3),
                      control1: p(16.694, 9.687),
                      control2: p(17.306, 9.687))
        path.addLine(to: p(20.806, 6.195))

        // Tiny connector cubic between the notch's outer corner and the
        // start of the head's outer arc. Keeps the join continuous instead
        // of breaking into a sharp angle.
        path.addCurve(to: p(21.789, 6.413),
                      control1: p(21.126, 5.873),
                      control2: p(21.669, 5.975))

        // Right-side outer arc of the head (~130° around center (16, 8),
        // radius 6). Split into two ~65° sub-arcs at the equator point so a
        // single cubic per half remains a tight fit.
        path.addCurve(to: p(19.886, 12.572),
                      control1: p(22.405, 8.661),
                      control2: p(21.662, 11.062))
        path.addCurve(to: p(13.53, 13.47),
                      control1: p(18.110, 14.082),
                      control2: p(15.649, 14.440))

        // Diagonal shaft going lower-left toward the handle end.
        path.addLine(to: p(5.62, 21.38))

        // Rounded handle cap: 180° semicircle around (4.1205, 19.88) with
        // effective radius 2.121 (the 1×1 SVG arc auto-scales because the
        // chord length exceeds 2r). Two 90° sub-arcs.
        path.addCurve(to: p(2.6205, 21.38),
                      control1: p(4.7916, 22.2084),
                      control2: p(3.4489, 22.2084))
        path.addCurve(to: p(2.621, 18.38),
                      control1: p(1.7921, 20.5516),
                      control2: p(1.7926, 19.2084))

        // Other side of the shaft, going up-right back to the head.
        path.addLine(to: p(10.531, 10.47))

        // Left-side outer arc of the head, mirror of the right-side arc.
        path.addCurve(to: p(11.440, 4.100),
                      control1: p(9.572, 8.346),
                      control2: p(9.925, 5.872))
        path.addCurve(to: p(17.588, 2.211),
                      control1: p(12.955, 2.328),
                      control2: p(15.339, 1.598))

        // Closing twiddle that mirrors the opening connector cubic.
        path.addCurve(to: p(17.807, 3.195),
                      control1: p(18.026, 2.331),
                      control2: p(18.128, 2.873))

        path.closeSubpath()
        return path
    }
}
