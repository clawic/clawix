import SwiftUI

/// Lucide `maximize-2` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct Maximize2Icon: View {
    var size: CGFloat = 16

    var body: some View {
        Maximize2IconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct Maximize2IconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M15 3h6v6"), transform: xform)
        path.addPath(SVGPathBuilder.build("m21 3-7 7"), transform: xform)
        path.addPath(SVGPathBuilder.build("m3 21 7-7"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9 21H3v-6"), transform: xform)
        return path
    }
}
