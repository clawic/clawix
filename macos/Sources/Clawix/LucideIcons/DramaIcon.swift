import SwiftUI

/// Lucide `drama` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct DramaIcon: View {
    var size: CGFloat = 16

    var body: some View {
        DramaIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct DramaIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M10 11h.01"), transform: xform)
        path.addPath(SVGPathBuilder.build("M14 6h.01"), transform: xform)
        path.addPath(SVGPathBuilder.build("M18 6h.01"), transform: xform)
        path.addPath(SVGPathBuilder.build("M6.5 13.1h.01"), transform: xform)
        path.addPath(SVGPathBuilder.build("M22 5c0 9-4 12-6 12s-6-3-6-12c0-2 2-3 6-3s6 1 6 3"), transform: xform)
        path.addPath(SVGPathBuilder.build("M17.4 9.9c-.8.8-2 .8-2.8 0"), transform: xform)
        path.addPath(SVGPathBuilder.build("M10.1 7.1C9 7.2 7.7 7.7 6 8.6c-3.5 2-4.7 3.9-3.7 5.6 4.5 7.8 9.5 8.4 11.2 7.4.9-.5 1.9-2.1 1.9-4.7"), transform: xform)
        path.addPath(SVGPathBuilder.build("M9.1 16.5c.3-1.1 1.4-1.7 2.4-1.4"), transform: xform)
        return path
    }
}
