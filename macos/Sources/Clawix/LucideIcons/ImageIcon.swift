import SwiftUI

/// Lucide `image` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct ImageIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ImageIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ImageIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 2, height: 2), transform: xform)
        path.addEllipse(in: CGRect(x: 9 - 2, y: 9 - 2, width: 2 * 2, height: 2 * 2), transform: xform)
        path.addPath(SVGPathBuilder.build("m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"), transform: xform)
        return path
    }
}
