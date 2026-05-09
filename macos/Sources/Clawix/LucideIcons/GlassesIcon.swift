import SwiftUI

/// Lucide `glasses` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct GlassesIcon: View {
    var size: CGFloat = 16

    var body: some View {
        GlassesIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct GlassesIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 6 - 4, y: 15 - 4, width: 2 * 4, height: 2 * 4), transform: xform)
        path.addEllipse(in: CGRect(x: 18 - 4, y: 15 - 4, width: 2 * 4, height: 2 * 4), transform: xform)
        path.addPath(SVGPathBuilder.build("M14 15a2 2 0 0 0-2-2 2 2 0 0 0-2 2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M2.5 13 5 7c.7-1.3 1.4-2 3-2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21.5 13 19 7c-.7-1.3-1.5-2-3-2"), transform: xform)
        return path
    }
}
