import SwiftUI

/// Custom settings (gear) icon used in place of SF Symbols `gearshape` on
/// the Home toolbar. Drawn as a proper 8-tooth cogwheel: radial tooth
/// sides + round-fillet corners (no central hub), on a 28-point grid that
/// shares the same outline language as `SearchIcon`, `GlobeIcon`, etc.
/// `lineWidth` can be passed explicitly so the gear matches the stroke of
/// an adjacent icon rendered at a different `size` (e.g. the search lens
/// next to it on the home toolbar).
struct SettingsIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        SettingsIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth ?? 3.15 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct SettingsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        let cx = dx + 14 * s
        let cy = dy + 14 * s

        // Cogwheel geometry, all measurements in the 28-pt grid.
        let nTeeth = 8
        let cycle: CGFloat = 2 * .pi / CGFloat(nTeeth)
        let alpha: CGFloat = 12.5 * .pi / 180     // angular half-width of tooth
        let rT: CGFloat = 11.5                    // tooth-tip radius
        let rB: CGFloat = 7.5                     // valley radius
        let rF: CGFloat = 1.0                     // corner fillet radius

        // Where the fillets carve the tip / valley arcs and the radial sides.
        let deltaT = asin(rF / (rT - rF))                       // tip-side fillet (convex)
        let deltaB = asin(rF / (rB + rF))                       // valley-side fillet (concave)
        let rTopTan = (rT - rF) * cos(deltaT)                   // side tangent radius near tip
        let rBotTan = (rB + rF) * cos(deltaB)                   // side tangent radius near valley

        // Cubic bezier circle approximations.
        let dTip    = (4.0/3.0) * tan((alpha - deltaT) / 2) * rT * s
        let dValley = (4.0/3.0) * tan(((cycle - 2 * alpha) - 2 * deltaB) / 4) * rB * s
        let dFillet = (4.0/3.0) * tan(.pi / 8) * rF * s         // 90° quarter circle

        func pt(_ r: CGFloat, _ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + r * s * sin(t), y: cy - r * s * cos(t))
        }
        func tDir(_ t: CGFloat) -> CGPoint { CGPoint(x: cos(t), y: sin(t)) }
        func oDir(_ t: CGFloat) -> CGPoint { CGPoint(x: sin(t), y: -cos(t)) }
        func iDir(_ t: CGFloat) -> CGPoint { CGPoint(x: -sin(t), y: cos(t)) }

        var path = Path()

        for i in 0..<nTeeth {
            let thetaT = CGFloat(i) * cycle
            let thetaL = thetaT - alpha
            let thetaR = thetaT + alpha

            let valleyEnd     = pt(rB, thetaL - deltaB)
            let sideBL        = pt(rBotTan, thetaL)
            let sideTL        = pt(rTopTan, thetaL)
            let tipL          = pt(rT, thetaL + deltaT)
            let tipR          = pt(rT, thetaR - deltaT)
            let sideTR        = pt(rTopTan, thetaR)
            let sideBR        = pt(rBotTan, thetaR)
            let valleyStart   = pt(rB, thetaR + deltaB)
            let nextValleyEnd = pt(rB, thetaR + (cycle - 2 * alpha) - deltaB)

            let tValEnd     = tDir(thetaL - deltaB)
            let radOutL     = oDir(thetaL)
            let tTipL       = tDir(thetaL + deltaT)
            let tTipR       = tDir(thetaR - deltaT)
            let radInR      = iDir(thetaR)
            let tValStart   = tDir(thetaR + deltaB)
            let tNextValEnd = tDir(thetaR + (cycle - 2 * alpha) - deltaB)

            if i == 0 { path.move(to: valleyEnd) }

            // BL fillet (concave): valley arc → left side
            do {
                let c1 = CGPoint(x: valleyEnd.x + dFillet * tValEnd.x, y: valleyEnd.y + dFillet * tValEnd.y)
                let c2 = CGPoint(x: sideBL.x - dFillet * radOutL.x,    y: sideBL.y - dFillet * radOutL.y)
                path.addCurve(to: sideBL, control1: c1, control2: c2)
            }
            // Left radial side
            path.addLine(to: sideTL)
            // TL fillet (convex): side → tip arc
            do {
                let c1 = CGPoint(x: sideTL.x + dFillet * radOutL.x, y: sideTL.y + dFillet * radOutL.y)
                let c2 = CGPoint(x: tipL.x - dFillet * tTipL.x,     y: tipL.y - dFillet * tTipL.y)
                path.addCurve(to: tipL, control1: c1, control2: c2)
            }
            // Tip arc
            do {
                let c1 = CGPoint(x: tipL.x + dTip * tTipL.x, y: tipL.y + dTip * tTipL.y)
                let c2 = CGPoint(x: tipR.x - dTip * tTipR.x, y: tipR.y - dTip * tTipR.y)
                path.addCurve(to: tipR, control1: c1, control2: c2)
            }
            // TR fillet (convex): tip arc → side
            do {
                let c1 = CGPoint(x: tipR.x + dFillet * tTipR.x,   y: tipR.y + dFillet * tTipR.y)
                let c2 = CGPoint(x: sideTR.x - dFillet * radInR.x, y: sideTR.y - dFillet * radInR.y)
                path.addCurve(to: sideTR, control1: c1, control2: c2)
            }
            // Right radial side
            path.addLine(to: sideBR)
            // BR fillet (concave): side → valley arc
            do {
                let c1 = CGPoint(x: sideBR.x + dFillet * radInR.x,         y: sideBR.y + dFillet * radInR.y)
                let c2 = CGPoint(x: valleyStart.x - dFillet * tValStart.x, y: valleyStart.y - dFillet * tValStart.y)
                path.addCurve(to: valleyStart, control1: c1, control2: c2)
            }
            // Valley arc to next tooth's BL fillet
            do {
                let c1 = CGPoint(x: valleyStart.x + dValley * tValStart.x,        y: valleyStart.y + dValley * tValStart.y)
                let c2 = CGPoint(x: nextValleyEnd.x - dValley * tNextValEnd.x,    y: nextValleyEnd.y - dValley * tNextValEnd.y)
                path.addCurve(to: nextValleyEnd, control1: c1, control2: c2)
            }
        }

        path.closeSubpath()
        return path
    }
}
