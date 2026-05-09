import SwiftUI

/// Lucide `minimize-2` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct Minimize2Icon: View {
    var size: CGFloat = 16

    var body: some View {
        Minimize2IconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct Minimize2IconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("m14 10 7-7"), transform: xform)
        path.addPath(SVGPathBuilder.build("M20 10h-6V4"), transform: xform)
        path.addPath(SVGPathBuilder.build("m3 21 7-7"), transform: xform)
        path.addPath(SVGPathBuilder.build("M4 14h6v6"), transform: xform)
        return path
    }
}
