import SwiftUI

/// Lucide `share-2` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct Share2Icon: View {
    var size: CGFloat = 16

    var body: some View {
        Share2IconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct Share2IconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 18 - 3, y: 5 - 3, width: 2 * 3, height: 2 * 3), transform: xform)
        path.addEllipse(in: CGRect(x: 6 - 3, y: 12 - 3, width: 2 * 3, height: 2 * 3), transform: xform)
        path.addEllipse(in: CGRect(x: 18 - 3, y: 19 - 3, width: 2 * 3, height: 2 * 3), transform: xform)
        do { var p = Path(); p.move(to: CGPoint(x: 8.59, y: 13.51)); p.addLine(to: CGPoint(x: 15.42, y: 17.49)); path.addPath(p, transform: xform) }
        do { var p = Path(); p.move(to: CGPoint(x: 15.41, y: 6.51)); p.addLine(to: CGPoint(x: 8.59, y: 10.49)); path.addPath(p, transform: xform) }
        return path
    }
}
