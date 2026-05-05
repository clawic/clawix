import SwiftUI

/// Custom pencil glyph used in place of SF Symbols `pencil` in the work
/// summary rows ("Edited N file", "Modified N file"). Tilted 45 degrees,
/// rounded cap upper-right, sharpened tip lower-left, with a single
/// ferrule line marking the eraser/wood transition.
struct PencilIconView: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let baseX = (size.width - s) / 2
            let baseY = (size.height - s) / 2

            let ux: CGFloat = -0.7071
            let uy: CGFloat =  0.7071
            let nx: CGFloat = -uy
            let ny: CGFloat =  ux

            let w: CGFloat = 0.144
            let bodyLen: CGFloat = 0.54
            let taperLen: CGFloat = 0.21
            let transitionLen: CGFloat = 0.060
            let tipCapExt: CGFloat = 0.020
            let taperWidth: CGFloat = 0.132
            let tipWidth: CGFloat = 0.032
            let transitionOvershoot: CGFloat = 0.006
            let ferruleA: CGFloat = 0.065

            let midA = (bodyLen + taperLen + tipCapExt - w) / 2
            let cx: CGFloat = 0.5 - midA * ux
            let cy: CGFloat = 0.5 - midA * uy

            func pt(_ a: CGFloat, _ p: CGFloat) -> CGPoint {
                CGPoint(
                    x: baseX + (cx + a * ux + p * nx) * s,
                    y: baseY + (cy + a * uy + p * ny) * s
                )
            }

            let bTop = pt(0,  w)
            let bBot = pt(0, -w)
            let backApex = pt(-w, 0)
            let mTop = pt(bodyLen,  w)
            let mBot = pt(bodyLen, -w)
            let tTop = pt(bodyLen + transitionLen,  taperWidth)
            let tBot = pt(bodyLen + transitionLen, -taperWidth)
            let tipUpper = pt(bodyLen + taperLen,  tipWidth)
            let tipLower = pt(bodyLen + taperLen, -tipWidth)
            let tipPoint = pt(bodyLen + taperLen + tipCapExt, 0)

            let k: CGFloat = 0.5523
            let bcap1c1 = pt(-w * k, -w)
            let bcap1c2 = pt(-w,     -w * k)
            let bcap2c1 = pt(-w,      w * k)
            let bcap2c2 = pt(-w * k,  w)

            let transTopCtl = pt(bodyLen + transitionLen * 0.45,  w + transitionOvershoot)
            let transBotCtl = pt(bodyLen + transitionLen * 0.45, -(w + transitionOvershoot))

            var pencil = Path()
            pencil.move(to: bTop)
            pencil.addLine(to: mTop)
            pencil.addQuadCurve(to: tTop, control: transTopCtl)
            pencil.addLine(to: tipUpper)
            pencil.addQuadCurve(to: tipLower, control: tipPoint)
            pencil.addLine(to: tBot)
            pencil.addQuadCurve(to: mBot, control: transBotCtl)
            pencil.addLine(to: bBot)
            pencil.addCurve(to: backApex, control1: bcap1c1, control2: bcap1c2)
            pencil.addCurve(to: bTop,     control1: bcap2c1, control2: bcap2c2)
            pencil.closeSubpath()

            var ferrule = Path()
            ferrule.move(to: pt(ferruleA,  w))
            ferrule.addLine(to: pt(ferruleA, -w))

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            context.stroke(pencil, with: .color(color), style: stroke)
            context.stroke(ferrule, with: .color(color), style: stroke)
        }
    }
}
