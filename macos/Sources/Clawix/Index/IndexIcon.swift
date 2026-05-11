import SwiftUI

/// Custom icon for the sidebar entry "Index". Reads as a stacked
/// catalog of records over an indexed line: three short horizontal
/// lines with the bottom one underscored, evoking a tagged shelf of
/// captured pages.
struct IndexIcon: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 18
            let lineWidth: CGFloat = 1.5 * scale

            let topY: CGFloat = 4 * scale
            let midY: CGFloat = 9 * scale
            let bottomY: CGFloat = 14 * scale
            let leftX: CGFloat = 3 * scale
            let topRight: CGFloat = 13 * scale
            let midRight: CGFloat = 15 * scale
            let bottomRight: CGFloat = 11 * scale

            for (start, end) in [
                (CGPoint(x: leftX, y: topY), CGPoint(x: topRight, y: topY)),
                (CGPoint(x: leftX, y: midY), CGPoint(x: midRight, y: midY)),
                (CGPoint(x: leftX, y: bottomY), CGPoint(x: bottomRight, y: bottomY)),
            ] {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(
                    path,
                    with: .color(.white.opacity(0.92)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            var underline = Path()
            underline.move(to: CGPoint(x: 1.5 * scale, y: 16.4 * scale))
            underline.addLine(to: CGPoint(x: 16.5 * scale, y: 16.4 * scale))
            context.stroke(
                underline,
                with: .color(.white.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    IndexIcon(size: 36).padding(20).background(Color.black)
}
