import SwiftUI

/// Custom Clawix settings icon. 6-lobe rosette (smooth bezier petals) +
/// outlined hub. Drawn on a 28-pt grid so it sits next to `SearchIcon` /
/// `GlobeIcon` cleanly and replaces SF Symbols `gearshape` everywhere.
///
/// Geometry decided after iterating against a reference: `rT=10.5`,
/// `rB=8.2`, bezier control `K=0.27`, hub `r=2.8`. `lineWidth` can be
/// passed explicitly so the gear matches the stroke of an adjacent icon
/// rendered at a different `size`.
struct SettingsIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        let s = size / 28
        let lw = lineWidth ?? 3.15 * s
        ZStack {
            SettingsIconShape()
                .stroke(style: StrokeStyle(
                    lineWidth: lw,
                    lineCap: .round,
                    lineJoin: .round
                ))
            Circle()
                .stroke(style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .frame(width: 5.6 * s, height: 5.6 * s)
        }
        .frame(width: size, height: size)
    }
}

private struct SettingsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let cx = rect.midX
        let cy = rect.midY

        // 6-lobe rosette: 12 anchors at 30° intervals, alternating tip
        // (rT) and valley (rB) radii. Each segment is a cubic bezier
        // whose control points are pulled along the cw tangent at each
        // anchor with magnitude K * r — that gives the soft "petal"
        // shape without sharp corners.
        let rT: CGFloat = 10.5
        let rB: CGFloat = 8.2
        let K:  CGFloat = 0.27
        let n  = 12

        struct Node { let p, cOut, cIn: CGPoint }
        var nodes: [Node] = []
        nodes.reserveCapacity(n)
        for i in 0..<n {
            let theta = CGFloat(i) * (2 * .pi / CGFloat(n))
            let r = (i % 2 == 0) ? rT : rB
            let x = cx + r * s * sin(theta)
            let y = cy - r * s * cos(theta)
            let tx = cos(theta), ty = sin(theta)
            let d = K * r * s
            nodes.append(Node(
                p:    CGPoint(x: x,           y: y),
                cOut: CGPoint(x: x + d * tx,  y: y + d * ty),
                cIn:  CGPoint(x: x - d * tx,  y: y - d * ty)
            ))
        }

        var path = Path()
        path.move(to: nodes[0].p)
        for i in 0..<n {
            let cur = nodes[i]
            let nxt = nodes[(i + 1) % n]
            path.addCurve(to: nxt.p, control1: cur.cOut, control2: nxt.cIn)
        }
        path.closeSubpath()
        return path
    }
}
