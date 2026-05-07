import SwiftUI

/// In-composer scrolling waveform shown while a voice note is being
/// recorded. Ported from the iOS composer so both platforms feel
/// identical: a steady stream of bars enters from the right at a known
/// cadence, the leading edge fades into the composer fill, and the
/// trailing edge fades out as bars drift left.
///
/// Bars come from `DictationCoordinator.barLevels`, which downsamples
/// the 50 Hz `levels` stream to one entry every `barCadence` seconds so
/// the visual phase advances in clean increments. Feeding the raw
/// audio-callback levels here made the scroll feel "buggy fast" because
/// every callback would reset the bar phase.
struct ComposerRecordingWaveform: View {
    var isActive: Bool = true
    var levels: [CGFloat] = []

    private let barWidth: CGFloat = 2.4
    private let barSpacing: CGFloat = 3.6
    private let minBarHeight: CGFloat = 2.4
    private let placeholderAmp: Double = 0.10
    private let realOpacity: Double = 0.95
    private let placeholderOpacity: Double = 0.18
    private let barsPerSecond: Double = 5

    @State private var startTime: Date = .now
    @State private var pausedElapsed: Double = 0
    @State private var pausedAt: Date? = nil
    /// Wall-clock instant of the most recent `levels.append`. The
    /// scroll phase is computed relative to this, NOT to `startTime`,
    /// so the rightmost bar lands exactly when a new sample arrives.
    @State private var lastBarAt: Date = .now
    @State private var lastLevelCount: Int = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { context in
            Canvas { ctx, size in
                draw(in: ctx, size: size, now: context.date)
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
        .onChange(of: levels.count) { _, newCount in
            if newCount != lastLevelCount {
                lastBarAt = .now
                lastLevelCount = newCount
            }
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                if let pausedAt {
                    let drift = Date.now.timeIntervalSince(pausedAt)
                    startTime = startTime.addingTimeInterval(drift)
                    lastBarAt = lastBarAt.addingTimeInterval(drift)
                }
                pausedAt = nil
            } else {
                pausedAt = .now
                pausedElapsed = Date.now.timeIntervalSince(startTime)
            }
        }
    }

    private func draw(in ctx: GraphicsContext, size: CGSize, now: Date) {
        let pitch = barWidth + barSpacing
        let count = max(1, Int(ceil(size.width / pitch)) + 2)
        let centerY = size.height / 2

        let phase: CGFloat
        let realCount: Int
        if levels.isEmpty {
            let elapsed = isActive ? max(0, now.timeIntervalSince(startTime)) : pausedElapsed
            let progressed = elapsed * barsPerSecond
            realCount = Int(floor(progressed))
            phase = CGFloat(progressed - floor(progressed))
        } else {
            let dt = max(0, now.timeIntervalSince(lastBarAt))
            phase = CGFloat(min(dt * barsPerSecond, 1.0))
            realCount = levels.count
        }

        for slot in 0..<count {
            let x = size.width - (CGFloat(slot) + phase) * pitch - barWidth / 2
            if x + barWidth < 0 { break }

            let realIdx = realCount - 1 - slot
            let amp: Double
            let alpha: Double
            if !levels.isEmpty {
                if realIdx >= 0 && realIdx < levels.count {
                    amp = max(Double(levels[realIdx]), 0.04)
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

#Preview("Composer waveform") {
    ComposerRecordingWaveform()
        .frame(height: 28)
        .padding()
        .background(Color(white: 0.135))
        .preferredColorScheme(.dark)
}
