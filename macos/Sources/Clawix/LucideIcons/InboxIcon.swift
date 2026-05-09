import SwiftUI

/// Lucide `inbox` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct InboxIcon: View {
    var size: CGFloat = 16

    var body: some View {
        InboxIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct InboxIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        do { var p = Path(); p.addLines([CGPoint(x: 22, y: 12), CGPoint(x: 16, y: 12), CGPoint(x: 14, y: 15), CGPoint(x: 10, y: 15), CGPoint(x: 8, y: 12), CGPoint(x: 2, y: 12)]); path.addPath(p, transform: xform) }
        path.addPath(SVGPathBuilder.build("M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"), transform: xform)
        return path
    }
}
