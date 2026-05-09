import SwiftUI

/// Lucide `image-off` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct ImageOffIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ImageOffIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ImageOffIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        do { var p = Path(); p.move(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: 22, y: 22)); path.addPath(p, transform: xform) }
        path.addPath(SVGPathBuilder.build("M10.41 10.41a2 2 0 1 1-2.83-2.83"), transform: xform)
        do { var p = Path(); p.move(to: CGPoint(x: 13.5, y: 13.5)); p.addLine(to: CGPoint(x: 6, y: 21)); path.addPath(p, transform: xform) }
        do { var p = Path(); p.move(to: CGPoint(x: 18, y: 12)); p.addLine(to: CGPoint(x: 21, y: 15)); path.addPath(p, transform: xform) }
        path.addPath(SVGPathBuilder.build("M3.59 3.59A1.99 1.99 0 0 0 3 5v14a2 2 0 0 0 2 2h14c.55 0 1.052-.22 1.41-.59"), transform: xform)
        path.addPath(SVGPathBuilder.build("M21 15V5a2 2 0 0 0-2-2H9"), transform: xform)
        return path
    }
}
