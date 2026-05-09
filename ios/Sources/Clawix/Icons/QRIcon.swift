import SwiftUI

/// Animated QR mark used in place of SF Symbol `qrcode` /
/// `qrcode.viewfinder` on the pairing screen. Authentic 3-layer
/// finders (filled border + transparent gap + inner squircle), gradient
/// viewfinder corner brackets fading out from each icon corner, and a
/// soft top-to-bottom scan wave that modulates dot opacity and scale.
/// All curves use `style: .continuous` (squircle, never circular arcs).
struct AnimatedQRIcon: View {
    var size: CGFloat = 156
    var period: Double = 3.0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, sz in
                QRIconRenderer.render(into: &ctx, size: sz, time: t, period: period)
            }
        }
        .frame(width: size, height: size)
    }
}

private enum QRIconRenderer {
    static let grid: Int = 13

    static func render(
        into ctx: inout GraphicsContext,
        size sz: CGSize,
        time t: TimeInterval,
        period: Double
    ) {
        let bracketRect = CGRect(origin: .zero, size: sz)
            .insetBy(dx: sz.width * 0.025, dy: sz.height * 0.025)
        let qrRect = CGRect(origin: .zero, size: sz)
            .insetBy(dx: sz.width * 0.10, dy: sz.height * 0.10)

        drawScanBrackets(into: &ctx, in: bracketRect)
        drawFinders(into: &ctx, in: qrRect)
        drawWaveDots(into: &ctx, in: qrRect, time: t, period: period)
    }

    // MARK: viewfinder corner brackets

    /// Stroke the full perimeter of a continuous-style rounded rect once
    /// per icon corner, each time with its own radial gradient centered
    /// at that corner. The stroke width is constant, so the bracket
    /// thickness is uniform; the gradient kills the stroke past a short
    /// radius, so what remains is four bright corner arcs that fade out
    /// toward the middle of each edge instead of meeting up.
    private static func drawScanBrackets(into ctx: inout GraphicsContext, in rect: CGRect) {
        let cornerRadius = rect.width * 0.20
        let stroke = max(1.4, rect.width * 0.012)

        let perimeter = Path(
            roundedRect: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )

        let endRadius = rect.width * 0.34
        let gradient = Gradient(stops: [
            .init(color: .white.opacity(0.90), location: 0.00),
            .init(color: .white.opacity(0.85), location: 0.30),
            .init(color: .white.opacity(0.30), location: 0.70),
            .init(color: .white.opacity(0.00), location: 1.00),
        ])

        let cornerCenters: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]

        for center in cornerCenters {
            ctx.stroke(
                perimeter,
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: 0,
                    endRadius: endRadius
                ),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: finder marks

    /// Three layers, all `.continuous`: a thin filled border, a punched
    /// hole inside it (even-odd fill), and a smaller filled squircle in
    /// the center, deliberately leaving a generous gap between the
    /// border's inner edge and the inner squircle.
    private static func drawFinders(into ctx: inout GraphicsContext, in rect: CGRect) {
        let g = CGFloat(grid)
        let s = min(rect.width, rect.height) / g
        let dx = rect.minX + (rect.width  - g * s) / 2
        let dy = rect.minY + (rect.height - g * s) / 2

        let borderFraction: CGFloat = 0.18
        let innerSizeRatio: CGFloat = 0.30
        let innerOpacity: Double = 0.65

        for (fx, fy) in [(0, 0), (10, 0), (0, 10)] {
            let outerRect = CGRect(
                x: dx + CGFloat(fx) * s,
                y: dy + CGFloat(fy) * s,
                width: 3 * s,
                height: 3 * s
            )
            let outerCorner = 0.30 * outerRect.width

            let holeInset = outerRect.width * borderFraction
            let holeRect = outerRect.insetBy(dx: holeInset, dy: holeInset)
            let holeCorner = max(1.0, 0.28 * holeRect.width)

            var ring = Path()
            ring.addRoundedRect(
                in: outerRect,
                cornerSize: CGSize(width: outerCorner, height: outerCorner),
                style: .continuous
            )
            ring.addRoundedRect(
                in: holeRect,
                cornerSize: CGSize(width: holeCorner, height: holeCorner),
                style: .continuous
            )
            ctx.fill(ring, with: .style(.foreground), style: FillStyle(eoFill: true, antialiased: true))

            let innerSide = outerRect.width * innerSizeRatio
            let innerRect = CGRect(
                x: outerRect.midX - innerSide / 2,
                y: outerRect.midY - innerSide / 2,
                width: innerSide,
                height: innerSide
            )
            let innerCorner = innerSide * 0.32
            ctx.fill(
                Path(
                    roundedRect: innerRect,
                    cornerSize: CGSize(width: innerCorner, height: innerCorner),
                    style: .continuous
                ),
                with: .color(.white.opacity(innerOpacity))
            )
        }
    }

    // MARK: wave-of-opacity-and-scale dots

    /// A virtual scan line travels from above the icon to below it on a
    /// constant linear cadence. Each dot's opacity and scale rise
    /// together as the wave's centerline passes its row, falling back
    /// to a quiet idle state otherwise. The brightness/scale curve is a
    /// quintic smoothstep so peaks feel rounded, not pulsed. The wave
    /// starts and ends fully outside the icon so the loop wrap-around
    /// lands on a frame where every dot is at base — the seam is
    /// invisible.
    private static func drawWaveDots(
        into ctx: inout GraphicsContext,
        in rect: CGRect,
        time t: TimeInterval,
        period: Double
    ) {
        let g = CGFloat(grid)
        let s = min(rect.width, rect.height) / g
        let dx = rect.minX + (rect.width  - g * s) / 2
        let dy = rect.minY + (rect.height - g * s) / 2

        let inset = s * 0.05
        let baseSide = s - 2 * inset
        let baseCorner = 0.40 * baseSide

        let cycle = CGFloat((t / period).truncatingRemainder(dividingBy: 1.0))
        let bandHalf = rect.height * 0.20
        let waveStart = rect.minY - bandHalf * 2
        let waveEnd   = rect.maxY + bandHalf * 2
        let waveY = waveStart + (waveEnd - waveStart) * cycle

        let baseOpacity: Double = 0.62
        let peakOpacity: Double = 1.00
        let baseScale: Double = 0.93
        let peakScale: Double = 1.07

        for (mx, my) in standardDots {
            let cellCenterX = dx + CGFloat(mx) * s + s / 2
            let cellCenterY = dy + CGFloat(my) * s + s / 2
            let dist = abs(cellCenterY - waveY)
            let n = max(0, min(1, 1 - Double(dist / bandHalf)))
            // Quintic smoothstep: 6n^5 - 15n^4 + 10n^3.
            let smooth = n * n * n * (n * (6 * n - 15) + 10)

            let opacity = baseOpacity + (peakOpacity - baseOpacity) * smooth
            let scale = baseScale + (peakScale - baseScale) * smooth

            let scaledSide = baseSide * CGFloat(scale)
            let scaledCorner = baseCorner * CGFloat(scale)
            let r = CGRect(
                x: cellCenterX - scaledSide / 2,
                y: cellCenterY - scaledSide / 2,
                width: scaledSide,
                height: scaledSide
            )
            ctx.fill(
                Path(
                    roundedRect: r,
                    cornerSize: CGSize(width: scaledCorner, height: scaledCorner),
                    style: .continuous
                ),
                with: .color(.white.opacity(opacity))
            )
        }
    }

    // MARK: dot field (deterministic ~46% density, finder zones excluded)

    private static func deterministicHash(x: Int, y: Int) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        h = (h ^ UInt32(truncatingIfNeeded: x &* 73_856_093)) &* 16_777_619
        h = (h ^ UInt32(truncatingIfNeeded: y &* 19_349_663)) &* 16_777_619
        h = (h ^ UInt32(truncatingIfNeeded: (x &+ 1) &* (y &+ 7) &* 83_492_791)) &* 16_777_619
        return h
    }

    private static func isFinderZone(x: Int, y: Int) -> Bool {
        (x <= 3 && y <= 3) || (x >= 9 && y <= 3) || (x <= 3 && y >= 9)
    }

    static let standardDots: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for x in 0..<grid {
            for y in 0..<grid {
                if isFinderZone(x: x, y: y) { continue }
                let h = deterministicHash(x: x, y: y) & 0xFFFF
                if h < UInt32(0xFFFF) * 46 / 100 {
                    out.append((x, y))
                }
            }
        }
        return out
    }()
}

#Preview("AnimatedQRIcon") {
    AnimatedQRIcon(size: 220)
        .foregroundStyle(.white)
        .padding(40)
        .background(Color.black)
}
