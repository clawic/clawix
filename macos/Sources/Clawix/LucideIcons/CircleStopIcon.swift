import SwiftUI

/// Lucide `circle-stop` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct CircleStopIcon: View {
    var size: CGFloat = 16

    var body: some View {
        CircleStopIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct CircleStopIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addEllipse(in: CGRect(x: 12 - 10, y: 12 - 10, width: 2 * 10, height: 2 * 10), transform: xform)
        path.addRoundedRect(in: CGRect(x: 9, y: 9, width: 6, height: 6), cornerSize: CGSize(width: 1, height: 1), transform: xform)
        return path
    }
}
