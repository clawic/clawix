import SwiftUI

/// Two stacked folders icon, shown in the inline work-summary row when
/// the aggregated line includes one or more `list_files` actions
/// (directory listings). Outline language matches the rest of the
/// custom folder family: 24-grid viewBox, hairline stroke that scales
/// with `size`, rounded caps and joins.
struct FolderStackIcon: View {
    var size: CGFloat = 13

    var body: some View {
        FolderStackIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.7 * (size / 24),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size * 1.05, height: size)
    }
}

private struct FolderStackIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(9.0, 3.5))
        path.addLine(to: p(11.7, 3.5))
        path.addCurve(to: p(12.5, 3.9),
                      control1: p(12.2, 3.5), control2: p(12.42, 3.6))
        path.addLine(to: p(13.2, 4.8))
        path.addCurve(to: p(14.0, 5.2),
                      control1: p(13.35, 5.1), control2: p(13.7, 5.2))
        path.addLine(to: p(20.0, 5.2))
        path.addCurve(to: p(21.5, 6.7),
                      control1: p(20.828, 5.2), control2: p(21.5, 5.872))
        path.addLine(to: p(21.5, 13.0))
        path.addCurve(to: p(20.0, 14.5),
                      control1: p(21.5, 13.828), control2: p(20.828, 14.5))

        path.move(to: p(2.5, 17.5))
        path.addLine(to: p(2.5, 8.0))
        path.addCurve(to: p(4.0, 6.5),
                      control1: p(2.5, 7.172), control2: p(3.172, 6.5))
        path.addLine(to: p(7.2, 6.5))
        path.addCurve(to: p(8.0, 6.9),
                      control1: p(7.7, 6.5), control2: p(7.92, 6.6))
        path.addLine(to: p(8.9, 8.1))
        path.addCurve(to: p(9.7, 8.5),
                      control1: p(9.05, 8.4), control2: p(9.4, 8.5))
        path.addLine(to: p(16.5, 8.5))
        path.addCurve(to: p(18.0, 10.0),
                      control1: p(17.328, 8.5), control2: p(18.0, 9.172))
        path.addLine(to: p(18.0, 17.5))
        path.addCurve(to: p(16.5, 19.0),
                      control1: p(18.0, 18.328), control2: p(17.328, 19.0))
        path.addLine(to: p(4.0, 19.0))
        path.addCurve(to: p(2.5, 17.5),
                      control1: p(3.172, 19.0), control2: p(2.5, 18.328))
        path.closeSubpath()

        return path
    }
}
