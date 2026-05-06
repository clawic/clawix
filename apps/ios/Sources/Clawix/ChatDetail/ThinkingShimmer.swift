import SwiftUI

// "Thinking" indicator: a per-character opacity wave that travels left
// to right in a continuous loop. Used at the tail of an in-progress
// assistant message while Clawix is still working. Mirrors the Mac
// app's ThinkingShimmer so the streaming feedback feels identical
// across platforms.

struct ThinkingShimmer: View {
    let text: String
    var font: Font = Typography.bodyFont
    var baseOpacity: Double = 0.40
    var peakOpacity: Double = 0.78
    var cycleDuration: Double = 3.0
    var radius: Double = 3.4

    var body: some View {
        let chars = Array(text)
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let raw = (t.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
            let eased = raw * raw * (3 - 2 * raw)
            let span = Double(chars.count) + 2 * radius
            let center = -radius + eased * span

            HStack(spacing: 0) {
                ForEach(Array(chars.enumerated()), id: \.offset) { index, ch in
                    Text(String(ch))
                        .font(font)
                        .tracking(-0.2)
                        .opacity(opacity(at: Double(index), center: center))
                }
            }
            .foregroundStyle(Palette.textPrimary)
        }
        .accessibilityLabel(text)
    }

    private func opacity(at index: Double, center: Double) -> Double {
        let d = (index - center) / radius
        let factor = exp(-d * d * 1.4)
        return baseOpacity + (peakOpacity - baseOpacity) * factor
    }
}
