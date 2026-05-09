import SwiftUI

/// Custom archivebox glyph used in chat action menus. Direct port of the
/// macOS sidebar's `ArchiveIcon` so the iOS dropdown renders the same
/// canonical Clawix mark instead of a generic SF Symbol look-alike. The
/// shape is two stacked rounded boxes (lid + body) with a centered handle
/// slit; outlined with a hairline stroke that scales with `size`.
struct ArchiveIconView: View {
    let color: Color
    let lineWidth: CGFloat
    var size: CGFloat = 13

    var body: some View {
        ArchiveIconShape()
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size, height: size)
    }
}

private struct ArchiveIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(3.25, 5.6))
        path.addArc(tangent1End: p(3.25, 4.2),  tangent2End: p(4.65, 4.2),  radius: 1.4 * s)
        path.addLine(to: p(19.35, 4.2))
        path.addArc(tangent1End: p(20.75, 4.2), tangent2End: p(20.75, 5.6), radius: 1.4 * s)
        path.addLine(to: p(20.75, 7.6))
        path.addArc(tangent1End: p(20.75, 8.8), tangent2End: p(19.55, 8.8), radius: 1.2 * s)
        path.addLine(to: p(4.45, 8.8))
        path.addArc(tangent1End: p(3.25, 8.8),  tangent2End: p(3.25, 7.6),  radius: 1.2 * s)
        path.closeSubpath()

        path.move(to: p(4, 9))
        path.addLine(to: p(20, 9))
        path.addLine(to: p(20, 16.6))
        path.addArc(tangent1End: p(20, 20.2), tangent2End: p(16.4, 20.2), radius: 3.6 * s)
        path.addLine(to: p(7.6, 20.2))
        path.addArc(tangent1End: p(4, 20.2),  tangent2End: p(4, 16.6),    radius: 3.6 * s)
        path.closeSubpath()

        path.move(to: p(10, 12.6))
        path.addLine(to: p(14, 12.6))

        return path
    }
}
