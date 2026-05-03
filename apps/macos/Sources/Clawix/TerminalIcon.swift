import SwiftUI

/// Custom terminal icon used in place of SF Symbols whenever the UI
/// references shell commands (e.g. the inline "Running" prefix and the
/// "Ran N commands" aggregate row). Outline drawn with `Path` so it
/// tints with `.foregroundColor` and renders the project-wide squircle
/// (continuous corners).
struct TerminalIcon: View {
    var size: CGFloat = 14

    var body: some View {
        TerminalIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 2.0 * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            // Square icons next to baseline-aligned text otherwise hang
            // above the line because SwiftUI maps the icon's baseline to
            // the bottom of the frame. Pull the baseline up by ~25% of
            // the icon size so the icon's optical center sits at the
            // surrounding text's x-height.
            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - size * 0.2 }
    }
}

private struct TerminalIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        let border = CGRect(x: dx + 2 * s, y: dy + 2 * s, width: 24 * s, height: 24 * s)
        path.addPath(Path(
            roundedRect: border,
            cornerSize: CGSize(width: 6 * s, height: 6 * s),
            style: .continuous
        ))

        path.move(to: p(8, 11))
        path.addLine(to: p(11, 14))
        path.addLine(to: p(8, 17))

        path.move(to: p(16, 17))
        path.addLine(to: p(20, 17))

        return path
    }
}
