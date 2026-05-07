import SwiftUI

// Per-character opacity wave used in chat list rows when an
// assistant turn is in flight. Matches the macOS ShimmerText
// behavior: a soft glow travels left to right (with smoothstep
// easing) and decays back, looping forever. Painted via
// `AttributedString` so the regular `Text` semantics (truncation,
// line limit, dynamic type) keep working — the chat row enforces
// `.lineLimit(1)` and we want the truncation to land cleanly when
// the title overflows.

struct ChatTitleShimmer: View {
    let text: String
    var font: Font = BodyFont.system(size: 17)
    var tracking: CGFloat = -0.2
    var color: Color = Palette.textPrimary
    var baseOpacity: Double = 0.30
    var peakOpacity: Double = 1.0
    var cycleDuration: Double = 2.4
    var radius: Double = 3.4

    var body: some View {
        TimelineView(.animation) { ctx in
            Text(attributed(now: ctx.date))
                .font(font)
                .tracking(tracking)
                .lineLimit(1)
        }
    }

    private func attributed(now: Date) -> AttributedString {
        let chars = Array(text)
        guard !chars.isEmpty else { return AttributedString() }
        let t = now.timeIntervalSinceReferenceDate
        let raw = (t.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration
        let eased = raw * raw * (3 - 2 * raw)
        let span = Double(chars.count) + 2 * radius
        let center = -radius + eased * span
        var result = AttributedString()
        for (i, ch) in chars.enumerated() {
            var part = AttributedString(String(ch))
            let d = (Double(i) - center) / radius
            let factor = exp(-d * d * 1.4)
            let op = baseOpacity + (peakOpacity - baseOpacity) * factor
            part.foregroundColor = color.opacity(op)
            result.append(part)
        }
        return result
    }
}
