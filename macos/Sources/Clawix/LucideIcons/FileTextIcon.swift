import SwiftUI

/// Lucide `file-text` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct FileTextIcon: View {
    var size: CGFloat = 16

    var body: some View {
        FileTextIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct FileTextIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"), transform: xform)
        path.addPath(SVGPathBuilder.build("M14 2v5a1 1 0 0 0 1 1h5"), transform: xform)
        path.addPath(SVGPathBuilder.build("M10 9H8"), transform: xform)
        path.addPath(SVGPathBuilder.build("M16 13H8"), transform: xform)
        path.addPath(SVGPathBuilder.build("M16 17H8"), transform: xform)
        return path
    }
}
