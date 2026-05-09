import SwiftUI

/// Lucide `list-checks` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct ListChecksIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ListChecksIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ListChecksIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M13 5h8"), transform: xform)
        path.addPath(SVGPathBuilder.build("M13 12h8"), transform: xform)
        path.addPath(SVGPathBuilder.build("M13 19h8"), transform: xform)
        path.addPath(SVGPathBuilder.build("m3 17 2 2 4-4"), transform: xform)
        path.addPath(SVGPathBuilder.build("m3 7 2 2 4-4"), transform: xform)
        return path
    }
}
