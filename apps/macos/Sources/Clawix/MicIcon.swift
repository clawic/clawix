import SwiftUI

/// Custom microphone glyph used in place of the SF Symbol "mic".
/// Shape matches the project's house style: continuous-corner capsule body
/// over a slightly squashed elliptical yoke (rx=13.5, ry=12) that opens
/// 30° wider than 180°, with stem and base.
struct MicIcon: View {
    var lineWidth: CGFloat = 2.4

    var body: some View {
        Canvas { ctx, size in
            // Source coordinate system: 66×68 (matches design SVG viewBox).
            // The drawn glyph occupies x∈[18,48], y∈[18,53] including stroke.
            let glyphRect = CGRect(x: 18, y: 18, width: 30, height: 36)
            let scale = min(size.width / glyphRect.width,
                            size.height / glyphRect.height)
            let drawnW = glyphRect.width * scale
            let drawnH = glyphRect.height * scale
            ctx.translateBy(x: (size.width - drawnW) / 2,
                            y: (size.height - drawnH) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -glyphRect.minX, y: -glyphRect.minY)

            var path = Path()

            path.addRoundedRect(
                in: CGRect(x: 26, y: 21, width: 14, height: 21),
                cornerSize: CGSize(width: 7, height: 7),
                style: .continuous
            )

            var arc = Path()
            arc.addArc(
                center: .zero,
                radius: 13.5,
                startAngle: .degrees(165),
                endAngle: .degrees(15),
                clockwise: true
            )
            arc = arc.applying(CGAffineTransform(scaleX: 1, y: 12.0 / 13.5))
            arc = arc.applying(CGAffineTransform(translationX: 33, y: 35))
            path.addPath(arc)

            path.move(to: CGPoint(x: 33, y: 47))
            path.addLine(to: CGPoint(x: 33, y: 52))

            path.move(to: CGPoint(x: 28, y: 52))
            path.addLine(to: CGPoint(x: 38, y: 52))

            ctx.stroke(
                path,
                with: .style(.foreground),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}
