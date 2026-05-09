import SwiftUI

/// Custom thin "X" used in place of SF Symbol `xmark`. Drawn as two stroked
/// diagonals on a 28-unit grid so the line weight scales linearly with
/// `size` and stays crisp at any pixel density. Use on its own for the
/// big close affordance ("close search"); use `CloseChipIcon` for the
/// inline clear-text button inside the search field.
struct CloseIcon: View {
    var size: CGFloat = 18
    /// Stroke thickness expressed in 28-unit grid points. Default keeps the
    /// glyph hairline; bump to ~2.4 for buttons that need more presence.
    var lineWidth: CGFloat = 1.9

    var body: some View {
        CloseIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth * (size / 28),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

struct CloseIconShape: Shape {
    /// Inset of the X arms from the bbox edges, in 28-unit grid points.
    /// Smaller value = arms reach closer to the corners (bigger X inside
    /// the same bbox). 6 leaves a comfortable optical margin.
    var inset: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 28
        let dx = (rect.width  - 28 * s) / 2
        let dy = (rect.height - 28 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        let lo = inset
        let hi = 28 - inset

        var path = Path()
        path.move(to: p(lo, lo))
        path.addLine(to: p(hi, hi))
        path.move(to: p(hi, lo))
        path.addLine(to: p(lo, hi))
        return path
    }
}

/// White chip with an X inside, used as the "clear text" button at the
/// trailing edge of the search field. Both circle diameter and X arm
/// thickness scale with `size` so the proportions stay locked.
struct CloseChipIcon: View {
    var size: CGFloat = 16
    /// X stroke thickness in 28-unit grid points (interpreted relative to
    /// the inner X bbox, not the outer circle).
    var lineWidth: CGFloat = 3.2
    var fill: Color = .white
    var foreground: Color = .black

    var body: some View {
        ZStack {
            Circle().fill(fill)
            CloseIconShape(inset: 9)
                .stroke(style: StrokeStyle(
                    lineWidth: lineWidth * (size / 28),
                    lineCap: .round,
                    lineJoin: .round
                ))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}
