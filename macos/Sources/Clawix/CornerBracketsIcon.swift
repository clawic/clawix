import SwiftUI

/// Two diagonally placed corner brackets (top-right + bottom-left).
/// Replaces SF Symbols `arrow.up.right.and.arrow.down.left` (`.expanded`)
/// and `arrow.down.right.and.arrow.up.left` (`.collapsed`). The shape
/// interpolates control points between variants so toggling `variant`
/// inside an animation context morphs the brackets smoothly.
struct CornerBracketsIcon: View {
    enum Variant { case collapsed, expanded }

    var size: CGFloat = 14
    var variant: Variant = .collapsed
    var lineWidth: CGFloat = 1.6

    var body: some View {
        CornerBracketsShape(t: variant == .expanded ? 1 : 0)
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.32), value: variant)
    }
}

struct CornerBracketsShape: Shape {
    var t: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }

        // t=0 collapsed: TR  M(20,9) L(17,9) Arc→(15,7) L(15,4)
        // t=1 expanded:  TR  M(14,4) L(18,4) Arc→(20,6) L(20,10)
        let trStart  = (lerp(20, 14), lerp(9,  4))
        let trVertex = (lerp(15, 20), lerp(9,  4))
        let trEnd    = (lerp(15, 20), lerp(4, 10))
        // t=0 collapsed: BL  M(4,15) L(7,15) Arc→(9,17) L(9,20)
        // t=1 expanded:  BL  M(10,20) L(6,20) Arc→(4,18) L(4,14)
        let blStart  = (lerp(4, 10), lerp(15, 20))
        let blVertex = (lerp(9,  4), lerp(15, 20))
        let blEnd    = (lerp(9,  4), lerp(20, 14))

        let r = 2 * s
        var path = Path()
        path.move(to: p(trStart.0, trStart.1))
        path.addArc(tangent1End: p(trVertex.0, trVertex.1),
                    tangent2End: p(trEnd.0,    trEnd.1),
                    radius: r)
        path.addLine(to: p(trEnd.0, trEnd.1))
        path.move(to: p(blStart.0, blStart.1))
        path.addArc(tangent1End: p(blVertex.0, blVertex.1),
                    tangent2End: p(blEnd.0,    blEnd.1),
                    radius: r)
        path.addLine(to: p(blEnd.0, blEnd.1))
        return path
    }
}
