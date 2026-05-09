import SwiftUI

/// Lucide `database` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct DatabaseIcon: View {
    var size: CGFloat = 16

    var body: some View {
        DatabaseIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct DatabaseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 12 - 9, y: 5 - 3, width: 2 * 9, height: 2 * 3), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 5V19A9 3 0 0 0 21 19V5"), transform: xform)
        path.addPath(SVGPathBuilder.build("M3 12A9 3 0 0 0 21 12"), transform: xform)
        return path
    }
}
