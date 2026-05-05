import SwiftUI

// "Thinking" indicator: a per-character opacity wave that travels left
// to right in a continuous loop. Used at the tail of an in-progress
// assistant message while Clawix is still working.

struct ThinkingShimmer: View {
    let text: String
    var font: Font = .system(size: 13.5)
    var baseOpacity: Double = 0.40
    var peakOpacity: Double = 0.78
    var cycleDuration: Double = 3.0
    var radius: Double = 3.4

    var body: some View {
        let chars = Array(text)
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let raw = (t.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
            // Smoothstep on the sweep: the wave decelerates at the edges
            // and accelerates through the middle, so it breathes through
            // the word instead of marching at constant speed.
            let eased = raw * raw * (3 - 2 * raw)
            let span = Double(chars.count) + 2 * radius
            let center = -radius + eased * span

            HStack(spacing: 0) {
                ForEach(Array(chars.enumerated()), id: \.offset) { index, ch in
                    Text(String(ch))
                        .font(font)
                        .opacity(opacity(at: Double(index), center: center))
                }
            }
            .foregroundColor(.white)
        }
        .accessibilityLabel(text)
    }

    private func opacity(at index: Double, center: Double) -> Double {
        let d = (index - center) / radius
        // Gaussian falloff: no hard edge at the radius boundary, so the
        // light spills smoothly across the word like a soft glow.
        let factor = exp(-d * d * 1.4)
        return baseOpacity + (peakOpacity - baseOpacity) * factor
    }
}
