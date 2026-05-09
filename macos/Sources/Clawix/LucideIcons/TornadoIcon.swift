import SwiftUI

/// Lucide `tornado` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct TornadoIcon: View {
    var size: CGFloat = 16

    var body: some View {
        TornadoIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct TornadoIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M21 4H3"), transform: xform)
        path.addPath(SVGPathBuilder.build("M18 8H6"), transform: xform)
        path.addPath(SVGPathBuilder.build("M19 12H9"), transform: xform)
        path.addPath(SVGPathBuilder.build("M16 16h-6"), transform: xform)
        path.addPath(SVGPathBuilder.build("M11 20H9"), transform: xform)
        return path
    }
}
