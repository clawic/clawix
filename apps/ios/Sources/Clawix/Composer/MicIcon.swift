import SwiftUI

/// Custom microphone glyph rendered as a filled shape (Phosphor-style mic-fill geometry),
/// with a 6% horizontal stretch around x=128 and a 6% vertical compression of the body
/// around y=96, plus a U-arc cup trimmed 10° on each side.
///
/// `lineWidth` adds an optional outline stroke on top of the fill to nudge perceived
/// thickness up at small render sizes; 0 = pure fill.
struct MicIcon: View {
    var lineWidth: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let glyphSize: CGFloat = 256
            let scale = min(size.width / glyphSize, size.height / glyphSize)
            let drawn = glyphSize * scale
            ctx.translateBy(x: (size.width - drawn) / 2,
                            y: (size.height - drawn) / 2)
            ctx.scaleBy(x: scale, y: scale)

            let stretchX = CGAffineTransform.identity
                .translatedBy(x: 128, y: 0)
                .scaledBy(x: 1.06, y: 1)
                .translatedBy(x: -128, y: 0)

            var bodyPath = Path()
            bodyPath.addRoundedRect(
                in: CGRect(x: 80, y: 16, width: 96, height: 160),
                cornerSize: CGSize(width: 48, height: 48)
            )
            bodyPath.addRoundedRect(
                in: CGRect(x: 96, y: 32, width: 64, height: 128),
                cornerSize: CGSize(width: 32, height: 32)
            )
            let compressY = CGAffineTransform.identity
                .translatedBy(x: 0, y: 96)
                .scaledBy(x: 1, y: 0.94)
                .translatedBy(x: 0, y: -96)
            bodyPath = bodyPath.applying(compressY).applying(stretchX)

            var cupPath = Path()
            cupPath.move(to: CGPoint(x: 136, y: 207.6))
            cupPath.addLine(to: CGPoint(x: 136, y: 224))
            cupPath.addLine(to: CGPoint(x: 152, y: 224))
            cupPath.addRelativeArc(
                center: CGPoint(x: 152, y: 232), radius: 8,
                startAngle: .degrees(270), delta: .degrees(180)
            )
            cupPath.addLine(to: CGPoint(x: 104, y: 240))
            cupPath.addRelativeArc(
                center: CGPoint(x: 104, y: 232), radius: 8,
                startAngle: .degrees(90), delta: .degrees(180)
            )
            cupPath.addLine(to: CGPoint(x: 120, y: 224))
            cupPath.addLine(to: CGPoint(x: 120, y: 207.6))
            cupPath.addRelativeArc(
                center: CGPoint(x: 128, y: 128), radius: 80,
                startAngle: .degrees(95.74), delta: .degrees(74.26)
            )
            cupPath.addRelativeArc(
                center: CGPoint(x: 57.095, y: 140.5), radius: 8,
                startAngle: .degrees(170), delta: .degrees(180)
            )
            cupPath.addRelativeArc(
                center: CGPoint(x: 128, y: 128), radius: 64,
                startAngle: .degrees(170), delta: .degrees(-160)
            )
            cupPath.addRelativeArc(
                center: CGPoint(x: 198.905, y: 140.5), radius: 8,
                startAngle: .degrees(190), delta: .degrees(180)
            )
            cupPath.addRelativeArc(
                center: CGPoint(x: 128, y: 128), radius: 80,
                startAngle: .degrees(10), delta: .degrees(74.26)
            )
            cupPath.closeSubpath()
            cupPath = cupPath.applying(stretchX)

            ctx.fill(bodyPath, with: .style(.foreground), style: FillStyle(eoFill: true))
            ctx.fill(cupPath, with: .style(.foreground))

            if lineWidth > 0 {
                let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                ctx.stroke(bodyPath, with: .style(.foreground), style: stroke)
                ctx.stroke(cupPath, with: .style(.foreground), style: stroke)
            }
        }
    }
}
