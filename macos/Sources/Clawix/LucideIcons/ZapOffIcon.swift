import SwiftUI

/// Lucide `zap-off` glyph, ported 1:1 from the lucide-icons/lucide
/// source SVG. Sits on the project's 28-grid (24-grid centered with a
/// 2-unit margin) with `.round` caps and joins and the shared 2.5/28
/// stroke ratio so it renders next to `SearchIcon`, `GlobeIcon` etc.
/// at the same visual weight.
struct ZapOffIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ZapOffIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.5 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct ZapOffIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2 + 2 * s
        let dy = (rect.height - 28 * s) / 2 + 2 * s
        let xform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
        var path = Path()
        path.addPath(SVGPathBuilder.build("M10.513 4.856 13.12 2.17a.5.5 0 0 1 .86.46l-1.377 4.317"), transform: xform)
        path.addPath(SVGPathBuilder.build("M15.656 10H20a1 1 0 0 1 .78 1.63l-1.72 1.773"), transform: xform)
        path.addPath(SVGPathBuilder.build("M16.273 16.273 10.88 21.83a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14H4a1 1 0 0 1-.78-1.63l4.507-4.643"), transform: xform)
        path.addPath(SVGPathBuilder.build("m2 2 20 20"), transform: xform)
        return path
    }
}
