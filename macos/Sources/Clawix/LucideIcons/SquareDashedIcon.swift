import SwiftUI

/// Lucide `square-dashed` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct SquareDashedIcon: View {
    var size: CGFloat = 16

    var body: some View {
        SquareDashedIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct SquareDashedIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M5 3a2 2 0 0 0-2 2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M19 3a2 2 0 0 1 2 2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21 19a2 2 0 0 1-2 2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M5 21a2 2 0 0 1-2-2"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9 3h1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9 21h1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M14 3h1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M14 21h1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 9v1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21 9v1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 14v1"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21 14v1"), transform: xform)
        return path
    }
}
