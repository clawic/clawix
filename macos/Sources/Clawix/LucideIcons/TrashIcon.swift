import SwiftUI

/// Lucide `trash` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct TrashIcon: View {
    var size: CGFloat = 16

    var body: some View {
        TrashIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct TrashIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 6h18"), transform: xform)
        path.addPath(SVGPathBuilder.build("M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"), transform: xform)
        return path
    }
}
