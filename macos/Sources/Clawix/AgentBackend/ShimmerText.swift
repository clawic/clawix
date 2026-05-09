import SwiftUI

// Per-character opacity wave painted via `AttributedString`, so the
// label still wraps to multiple lines when the body is long. Same
// visual language as `ThinkingShimmer`, used to mark the row that
// represents whatever Clawix is doing right now (e.g. the running
// shell command) inside an in-flight tool group.

struct ShimmerText: View {
    let text: String
    var font: Font = BodyFont.system(size: 13)
    var color: Color = .white
    var baseOpacity: Double = 0.30
    var peakOpacity: Double = 0.85
    var cycleDuration: Double = 3.0
    var radius: Double = 4.0

    var body: some View {
        TimelineView(.animation) { ctx in
            Text(attributed(now: ctx.date))
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
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
