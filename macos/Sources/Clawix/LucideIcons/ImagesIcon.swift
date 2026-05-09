import SwiftUI

/// Lucide `images` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Two-pass render (filled inner primitives + stroke for
/// the outline) on the project's 28-grid with `.round` caps/joins and
/// the shared 2.5/28 stroke ratio.
struct ImagesIcon: View {
    var size: CGFloat = 16

    var body: some View {
        let stroke = StrokeStyle(
            lineWidth: 2.5 * (size / 28),
            lineCap: .round,
            lineJoin: .round
        )
        ZStack {
            ImagesIconShape(layer: .fill).fill()
            ImagesIconShape(layer: .stroke).stroke(style: stroke)
        }
        .frame(width: size, height: size)
    }
}

struct ImagesIconShape: Shape {
    enum Layer { case stroke, fill }
    var layer: Layer = .stroke

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        switch layer {
        case .stroke:
            path.addPath(SVGPathBuilder.build("m22 11-1.296-1.296a2.4 2.4 0 0 0-3.408 0L11 16"), transform: xform)
            path.addPath(SVGPathBuilder.build("M4 8a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2"), transform: xform)
            path.addEllipse(in: CGRect(x: 13 - 1, y: 7 - 1, width: 2 * 1, height: 2 * 1), transform: xform)
            path.addRoundedRect(in: CGRect(x: 8, y: 2, width: 14, height: 14), cornerSize: CGSize(width: 2, height: 2), transform: xform)
        case .fill:
            path.addEllipse(in: CGRect(x: 13 - 1, y: 7 - 1, width: 2 * 1, height: 2 * 1), transform: xform)
        }
        return path
    }
}
