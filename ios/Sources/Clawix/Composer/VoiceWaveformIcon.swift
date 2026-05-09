import SwiftUI

/// Four-bar waveform glyph on a 24×24 canvas. Pattern: short, tallest, tall, short
/// (vertically centered). Solid fill; sized via `.frame`.
struct VoiceWaveformIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let viewBox: CGFloat = 24
            let scale = min(size.width / viewBox, size.height / viewBox)
            let drawn = viewBox * scale
            ctx.translateBy(x: (size.width - drawn) / 2,
                            y: (size.height - drawn) / 2)
            ctx.scaleBy(x: scale, y: scale)

            var path = Path()
            path.addRoundedRect(
                in: CGRect(x: 0.25, y: 8, width: 4, height: 8),
                cornerSize: CGSize(width: 2, height: 2)
            )
            path.addRoundedRect(
                in: CGRect(x: 6.75, y: 1, width: 4, height: 22),
                cornerSize: CGSize(width: 2, height: 2)
            )
            path.addRoundedRect(
                in: CGRect(x: 13.25, y: 5, width: 4, height: 14),
                cornerSize: CGSize(width: 2, height: 2)
            )
            path.addRoundedRect(
                in: CGRect(x: 19.75, y: 8, width: 4, height: 8),
                cornerSize: CGSize(width: 2, height: 2)
            )
            ctx.fill(path, with: .style(.foreground))
        }
    }
}
