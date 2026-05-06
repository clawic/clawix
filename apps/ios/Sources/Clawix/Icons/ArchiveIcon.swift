import SwiftUI

/// Custom archivebox glyph used in chat action menus. Outline language
/// matches the rest of the Clawix icon family: 24-grid viewBox, hairline
/// stroke that scales with `size`, rounded caps and joins. Reads as a
/// shoebox with a separate lid: top band carrying a center notch, lower
/// body framing a small handle slit.
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

        // Lid: rounded rectangle 3..21 x 4..9, radius 1.5
        path.addRoundedRect(
            in: CGRect(x: dx + 3 * s, y: dy + 4 * s, width: 18 * s, height: 5 * s),
            cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s)
        )

        // Body: 4..20 x 9..20, radius 1.5
        path.addRoundedRect(
            in: CGRect(x: dx + 4 * s, y: dy + 9 * s, width: 16 * s, height: 11 * s),
            cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s)
        )

        // Handle slit: short horizontal stroke centered at y=14
        path.move(to: p(9.5, 13.5))
        path.addLine(to: p(14.5, 13.5))

        return path
    }
}
