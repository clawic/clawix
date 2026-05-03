import SwiftUI

/// Custom globe icon used whenever the work summary surfaces web/browser
/// activity. Drawn with `Path` in a 28-point grid so it tints with
/// `.foregroundColor` and stays crisp at 11–14 pt point sizes. The two
/// side meridians sit close to the outer rim so the icon reads as a
/// sphere instead of a flat circle with a vertical bar.
struct GlobeIcon: View {
    var size: CGFloat = 14

    var body: some View {
        GlobeIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.0 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct GlobeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        // Outer circle: the planet's silhouette.
        path.addEllipse(in: CGRect(
            x: dx + 2 * s, y: dy + 2 * s,
            width: 24 * s, height: 24 * s
        ))

        // Equator
        path.move(to: p(2, 14))
        path.addLine(to: p(26, 14))

        // Central meridian: a tall narrow ellipse whose left/right halves
        // are the arcs that divide the visible hemisphere into quarters.
        // Width 16 leaves 4 grid units of margin from each rim — bulged
        // enough that the curves clearly belong to a sphere, not flat.
        path.addEllipse(in: CGRect(
            x: dx + 6 * s, y: dy + 2 * s,
            width: 16 * s, height: 24 * s
        ))

        return path
    }
}
