import SwiftUI

// Recording waveform. Behaviour:
//   - the strip starts as a uniform pattern of low-opacity placeholder
//     bars filling the full width
//   - while the take is running we add ~`barsPerSecond` real bars per
//     second (right edge = "now"); each new bar pushes the older real
//     bars left so they slowly replace the placeholder column by column
//   - the right edge fades out so a freshly-spawned bar slides in
//     instead of popping; the left edge fades out so older real bars
//     dissolve as they reach the leading rim
//   - when `isActive == false` (paused / pre-roll) the scroll freezes
//     so the user can still see the bars they captured up to that point
//
// When `levels` is non-empty the bar amplitudes come straight from the
// audio recorder's `averagePower`-derived buffer (one entry per ~50ms,
// most recent at the tail). When it is empty the strip falls back to a
// synthetic envelope so previews/mockups still animate convincingly.
struct RecordingWaveform: View {
    var isActive: Bool = true
    var levels: [CGFloat] = []

    private let barWidth: CGFloat = 2.4
    private let barSpacing: CGFloat = 3.6
    private let minBarHeight: CGFloat = 2.4
    private let placeholderAmp: Double = 0.10
    private let realOpacity: Double = 0.95
    private let placeholderOpacity: Double = 0.18
    private let syntheticBarsPerSecond: Double = 5
    private let realBarsPerSecond: Double = 5

    private var barsPerSecond: Double {
        levels.isEmpty ? syntheticBarsPerSecond : realBarsPerSecond
    }

    @State private var startTime: Date = .now
    @State private var pausedElapsed: Double = 0
    @State private var pausedAt: Date? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
            Canvas { ctx, size in
                draw(in: ctx, size: size, elapsed: currentElapsed(now: context.date))
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white, location: 0.08),
                    .init(color: .white, location: 0.92),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .onChange(of: isActive) { _, nowActive in
            // Freeze the scroll exactly where it was when the take is
            // paused, then resume from that same offset on the next
            // start so the bars don't jump.
            if nowActive {
                if let pausedAt {
                    let drift = Date.now.timeIntervalSince(pausedAt)
                    startTime = startTime.addingTimeInterval(drift)
                }
                pausedAt = nil
            } else {
                pausedAt = .now
                pausedElapsed = Date.now.timeIntervalSince(startTime)
            }
        }
    }

    private func currentElapsed(now: Date) -> Double {
        if isActive {
            return max(0, now.timeIntervalSince(startTime))
        } else {
            return max(0, pausedElapsed)
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        let pitch = barWidth + barSpacing
        // +2 so a freshly spawned bar can ride in from beyond the
        // right edge without popping.
        let count = max(1, Int(ceil(size.width / pitch)) + 2)
        let centerY = size.height / 2

        let progressed = elapsed * barsPerSecond
        let realCount = Int(floor(progressed))
        let phase = CGFloat(progressed - floor(progressed))

        for slot in 0..<count {
            let x = size.width - (CGFloat(slot) + phase) * pitch - barWidth / 2
            if x + barWidth < 0 { break }

            let realIdx = realCount - 1 - slot
            let amp: Double
            let alpha: Double
            if !levels.isEmpty {
                // Real path: slot 0 = most recent sample. Older samples
                // walk left until they fall off the buffer's head, at
                // which point the column reverts to a placeholder.
                let bufferIdx = levels.count - 1 - slot
                if bufferIdx >= 0 {
                    amp = max(Double(levels[bufferIdx]), 0.04)
                    alpha = realOpacity
                } else {
                    amp = placeholderAmp
                    alpha = placeholderOpacity
                }
            } else if realIdx >= 0 {
                amp = realAmplitude(index: realIdx)
                alpha = realOpacity
            } else {
                amp = placeholderAmp
                alpha = placeholderOpacity
            }

            let h = max(minBarHeight, CGFloat(amp) * size.height)
            let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
            var path = Path()
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2),
                style: .continuous
            )
            ctx.fill(path, with: .color(.white.opacity(alpha)))
        }
    }

    // Voice-like envelope: a slow swell modulated by per-bar hash noise
    // so consecutive bars vary believably (loud syllables next to soft
    // ones) without the regularity of pure sines.
    private func realAmplitude(index: Int) -> Double {
        let i = Double(index)
        let macro = (sin(i * 0.27) * 0.5 + 0.5) * 0.6
                  + (sin(i * 0.91 + 1.7) * 0.5 + 0.5) * 0.4
        let noise = hashNoise(index: index)
        let mixed = 0.18 + 0.62 * macro * (0.45 + 0.55 * noise)
        return min(0.96, mixed)
    }

    private func hashNoise(index: Int) -> Double {
        let x = sin(Double(index) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }
}

#Preview("Waveform") {
    RecordingWaveform()
        .frame(height: 36)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Waveform paused") {
    RecordingWaveform(isActive: false)
        .frame(height: 36)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
