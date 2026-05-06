import SwiftUI

/// Custom QR mark used in place of SF Symbol `qrcode` / `qrcode.viewfinder`.
/// Drawn on a 13x13 module grid: simple rounded squares at the three finder
/// corners, plus a sparse field of inset rounded "dots" with a visible gap
/// between neighbours, so the icon reads as an abstract QR rather than a
/// dense matrix.
struct QRIcon: View {
    var size: CGFloat = 28

    var body: some View {
        QRIconShape()
            .fill(style: FillStyle(eoFill: true, antialiased: true))
            .frame(width: size, height: size)
    }
}

struct QRIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = CGFloat(QRIconLayout.grid)
        let s = min(rect.width, rect.height) / g
        let dx = (rect.width  - g * s) / 2
        let dy = (rect.height - g * s) / 2

        var path = Path()

        for (fx, fy) in QRIconLayout.finders {
            QRIconLayout.appendFinder(to: &path, fx: CGFloat(fx), fy: CGFloat(fy), s: s, dx: dx, dy: dy)
        }

        let inset = QRIconLayout.moduleInset * s
        let moduleSide = s - 2 * inset
        let moduleCorner = QRIconLayout.moduleRadiusRatio * moduleSide
        for (mx, my) in QRIconLayout.modules {
            path.addRoundedRect(
                in: CGRect(
                    x: dx + CGFloat(mx) * s + inset,
                    y: dy + CGFloat(my) * s + inset,
                    width: moduleSide,
                    height: moduleSide
                ),
                cornerSize: CGSize(width: moduleCorner, height: moduleCorner),
                style: .continuous
            )
        }

        return path
    }
}

/// Shared 13x13 grid coordinates for both static and animated renderings.
enum QRIconLayout {
    static let grid: Int = 13

    // Top-left module of each 3x3 finder square.
    static let finders: [(Int, Int)] = [(0, 0), (10, 0), (0, 10)]
    static let finderSide: CGFloat = 3
    static let finderRadiusRatio: CGFloat = 0.40

    // Each data module is drawn inset inside its grid cell so adjacent
    // modules show a clear gap. The corner radius is expressed as a
    // fraction of the inset module side, not of the grid cell.
    static let moduleInset: CGFloat = 0.10
    static let moduleRadiusRatio: CGFloat = 0.45

    // Pre-computed data modules: deterministic ~42% density pseudo-random
    // fill in the remaining grid cells. Excludes the 4x4 finder + separator
    // zones at the three QR corners.
    static let modules: [(Int, Int)] = {
        var result: [(Int, Int)] = []
        for x in 0..<grid {
            for y in 0..<grid {
                if isFinderZone(x: x, y: y) { continue }
                if isDataFilled(x: x, y: y) {
                    result.append((x, y))
                }
            }
        }
        return result
    }()

    static func appendFinder(to path: inout Path, fx: CGFloat, fy: CGFloat, s: CGFloat, dx: CGFloat, dy: CGFloat) {
        let side = finderSide * s
        path.addRoundedRect(
            in: CGRect(x: dx + fx * s, y: dy + fy * s, width: side, height: side),
            cornerSize: CGSize(width: finderRadiusRatio * side, height: finderRadiusRatio * side),
            style: .continuous
        )
    }

    private static func isFinderZone(x: Int, y: Int) -> Bool {
        // 4x4 zone = 3x3 finder + 1 module separator on the inner sides.
        (x <= 3 && y <= 3) ||
        (x >= 9 && y <= 3) ||
        (x <= 3 && y >= 9)
    }

    private static func isDataFilled(x: Int, y: Int) -> Bool {
        var h: UInt32 = 2_166_136_261
        h = (h ^ UInt32(truncatingIfNeeded: x &* 73_856_093)) &* 16_777_619
        h = (h ^ UInt32(truncatingIfNeeded: y &* 19_349_663)) &* 16_777_619
        h = (h ^ UInt32(truncatingIfNeeded: (x &+ 1) &* (y &+ 7) &* 83_492_791)) &* 16_777_619
        return (h & 0xFFFF) < UInt32(0xFFFF) * 42 / 100
    }

    /// Stable per-module phase in [0, 1) used by the animated variant so
    /// each dot breathes on its own offset without forming a directional
    /// wave across the grid.
    static func modulePhase(x: Int, y: Int) -> Double {
        var h: UInt32 = 2_166_136_261
        h = (h ^ UInt32(truncatingIfNeeded: x &* 2_654_435_761)) &* 16_777_619
        h = (h ^ UInt32(truncatingIfNeeded: y &* 40_503)) &* 16_777_619
        h = (h ^ UInt32(truncatingIfNeeded: (x &+ 11) &* (y &+ 31))) &* 16_777_619
        return Double(h & 0xFFFF) / Double(0xFFFF)
    }
}

/// Animated variant. Every dot keeps its position and just grows/shrinks
/// slightly on a simple sine curve. Each dot has its own small phase so
/// the icon twinkles softly without forming a directional wave; the three
/// finder squares share a slower, in-unison breath.
struct AnimatedQRIcon: View {
    var size: CGFloat = 28
    var period: Double = 2.6

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas(
                opaque: false,
                colorMode: .nonLinear,
                rendersAsynchronously: false
            ) { ctx, sz in
                Self.render(into: &ctx, size: sz, time: t, period: period)
            }
        }
        .frame(width: size, height: size)
    }

    private static func render(
        into ctx: inout GraphicsContext,
        size sz: CGSize,
        time t: TimeInterval,
        period: Double
    ) {
        let g = CGFloat(QRIconLayout.grid)
        let s = min(sz.width, sz.height) / g
        let dx = (sz.width  - g * s) / 2
        let dy = (sz.height - g * s) / 2

        let finderScale = scaleAt(time: t, period: period * 1.25, phase: 0, range: 0.05)
        let finderSide = QRIconLayout.finderSide * s
        let finderCorner = QRIconLayout.finderRadiusRatio * finderSide
        for (fx, fy) in QRIconLayout.finders {
            let originX = dx + CGFloat(fx) * s
            let originY = dy + CGFloat(fy) * s
            let scaledSide = finderSide * finderScale
            let scaledCorner = finderCorner * finderScale
            let r = CGRect(
                x: originX + (finderSide - scaledSide) / 2,
                y: originY + (finderSide - scaledSide) / 2,
                width: scaledSide,
                height: scaledSide
            )
            let p = Path(
                roundedRect: r,
                cornerSize: CGSize(width: scaledCorner, height: scaledCorner),
                style: .continuous
            )
            ctx.fill(p, with: .style(.foreground))
        }

        let inset = QRIconLayout.moduleInset * s
        let moduleSide = s - 2 * inset
        let moduleCorner = QRIconLayout.moduleRadiusRatio * moduleSide
        for (mx, my) in QRIconLayout.modules {
            let phase = QRIconLayout.modulePhase(x: mx, y: my)
            let scale = scaleAt(time: t, period: period, phase: phase, range: 0.18)
            let cellOriginX = dx + CGFloat(mx) * s
            let cellOriginY = dy + CGFloat(my) * s
            let cx = cellOriginX + s / 2
            let cy = cellOriginY + s / 2
            let scaledSide = moduleSide * scale
            let scaledCorner = moduleCorner * scale
            let r = CGRect(
                x: cx - scaledSide / 2,
                y: cy - scaledSide / 2,
                width: scaledSide,
                height: scaledSide
            )
            let p = Path(
                roundedRect: r,
                cornerSize: CGSize(width: scaledCorner, height: scaledCorner),
                style: .continuous
            )
            ctx.fill(p, with: .style(.foreground))
        }
    }

    /// Maps a time + per-element phase to a scale factor that breathes
    /// between `1 - range` and `1` along a simple sine curve.
    private static func scaleAt(time t: TimeInterval, period: Double, phase: Double, range: Double) -> Double {
        let v = sin((t / period + phase) * 2 * .pi)
        let unit = v * 0.5 + 0.5
        return (1.0 - range) + range * unit
    }
}

#Preview("QR icon") {
    VStack(spacing: 24) {
        QRIcon(size: 28)
        QRIcon(size: 60)
        QRIcon(size: 96)
        AnimatedQRIcon(size: 220)
    }
    .foregroundStyle(.white)
    .padding(40)
    .background(Color.black)
}
