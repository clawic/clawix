import CoreGraphics
import SwiftUI

extension SVGPathBuilder.Builder {
    // SVG arc -> cubic Beziers per
    // https://www.w3.org/TR/SVG/implnote.html#ArcImplementationNotes
    mutating func appendArc(from p0: CGPoint, to p1: CGPoint,
                            rx rxIn: Double, ry ryIn: Double,
                            xRotDeg: Double,
                            largeArc: Bool, sweep: Bool) {
        if p0 == p1 { return }
        if rxIn == 0 || ryIn == 0 {
            path.addLine(to: p1)
            return
        }
        let phi = xRotDeg * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (Double(p0.x) - Double(p1.x)) / 2
        let dy = (Double(p0.y) - Double(p1.y)) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }
        let rx2 = rx * rx
        let ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        var num = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2
        let den = rx2 * y1p2 + ry2 * x1p2
        if num < 0 { num = 0 }
        let factor = sqrt(num / den) * (largeArc == sweep ? -1 : 1)
        let cxp = factor * (rx * y1p) / ry
        let cyp = -factor * (ry * x1p) / rx
        let cx = cosPhi * cxp - sinPhi * cyp + Double(p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + Double(p0.y + p1.y) / 2
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = vectorAngle(1, 0, ux, uy)
        var dTheta = vectorAngle(ux, uy, vx, vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }
        let segments = max(Int(ceil(abs(dTheta) / (.pi / 2))), 1)
        let delta = dTheta / Double(segments)
        let t = (4.0 / 3.0) * tan(delta / 4)
        var theta = theta1
        for _ in 0..<segments {
            let t2 = theta + delta
            let cosTheta = cos(theta)
            let sinTheta = sin(theta)
            let cosT2 = cos(t2)
            let sinT2 = sin(t2)
            let p1Local = CGPoint(x: cosTheta - t * sinTheta, y: sinTheta + t * cosTheta)
            let p2Local = CGPoint(x: cosT2 + t * sinT2, y: sinT2 - t * cosT2)
            let p3Local = CGPoint(x: cosT2, y: sinT2)
            let c1 = applyArcTransform(p1Local, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, cx: cx, cy: cy)
            let c2 = applyArcTransform(p2Local, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, cx: cx, cy: cy)
            let pt = applyArcTransform(p3Local, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, cx: cx, cy: cy)
            path.addCurve(to: pt, control1: c1, control2: c2)
            theta = t2
        }
    }

    private func applyArcTransform(_ p: CGPoint,
                                   rx: Double, ry: Double,
                                   cosPhi: Double, sinPhi: Double,
                                   cx: Double, cy: Double) -> CGPoint {
        let xr = Double(p.x) * rx
        let yr = Double(p.y) * ry
        let x = cosPhi * xr - sinPhi * yr + cx
        let y = sinPhi * xr + cosPhi * yr + cy
        return CGPoint(x: x, y: y)
    }

    private func vectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        let sign: Double = (ux * vy - uy * vx) >= 0 ? 1 : -1
        let dot = ux * vx + uy * vy
        let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        let cosA = max(-1.0, min(1.0, dot / len))
        return sign * acos(cosA)
    }
}
