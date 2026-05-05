import SwiftUI

/// Custom open-folder icon used in place of SF Symbols `folder`.
/// Outline drawn directly with SwiftUI Path so it tints with `.foregroundColor`
/// and scales cleanly without a PDF asset round trip.
struct FolderOpenIcon: View {
    var size: CGFloat = 13

    var body: some View {
        FolderOpenIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.5 * (size / 18),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size * 1.18, height: size)
    }
}

private struct FolderOpenIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 18
        let dx = (rect.width  - 18 * s) / 2
        let dy = (rect.height - 18 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(3.0, 15.0))
        path.addLine(to: p(4.5, 10.5))
        path.addLine(to: p(5.625, 8.324))
        path.addCurve(to: p(6.93, 7.5),
                      control1: p(5.875, 7.828), control2: p(6.375, 7.512))
        path.addLine(to: p(15.0, 7.5))
        path.addCurve(to: p(16.188, 8.082),
                      control1: p(15.465, 7.5), control2: p(15.902, 7.715))
        path.addCurve(to: p(16.453, 9.375),
                      control1: p(16.473, 8.449), control2: p(16.570, 8.926))
        path.addLine(to: p(15.301, 13.875))
        path.addCurve(to: p(13.836, 15.0),
                      control1: p(15.129, 14.539), control2: p(14.523, 15.004))
        path.addLine(to: p(3.0, 15.0))
        path.addCurve(to: p(1.5, 13.5),
                      control1: p(2.172, 15.0), control2: p(1.5, 14.328))
        path.addLine(to: p(1.5, 3.75))
        path.addCurve(to: p(3.0, 2.25),
                      control1: p(1.5, 2.922), control2: p(2.172, 2.25))
        path.addLine(to: p(5.949, 2.25))
        path.addCurve(to: p(7.191, 2.926),
                      control1: p(6.449, 2.254), control2: p(6.918, 2.508))
        path.addLine(to: p(7.809, 3.824))
        path.addCurve(to: p(9.051, 4.5),
                      control1: p(8.082, 4.242), control2: p(8.551, 4.496))
        path.addLine(to: p(13.5, 4.5))
        path.addCurve(to: p(15.0, 6.0),
                      control1: p(14.328, 4.5), control2: p(15.0, 5.172))
        path.addLine(to: p(15.0, 7.5))
        return path
    }
}

/// Closed-folder counterpart used when a project is collapsed.
struct FolderClosedIcon: View {
    var size: CGFloat = 13
    var weight: CGFloat = 1.5

    var body: some View {
        FolderClosedIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: weight * (size / 18),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size * 1.05, height: size)
    }
}

private struct FolderClosedIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 18
        let dx = (rect.width  - 18 * s) / 2
        let dy = (rect.height - 18 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(15.0, 15.0))
        path.addCurve(to: p(16.5, 13.5),
                      control1: p(15.828, 15.0), control2: p(16.5, 14.328))
        path.addLine(to: p(16.5, 6.0))
        path.addCurve(to: p(15.0, 4.5),
                      control1: p(16.5, 5.172), control2: p(15.828, 4.5))
        path.addLine(to: p(9.051, 4.5))
        path.addCurve(to: p(7.809, 3.824),
                      control1: p(8.551, 4.496), control2: p(8.082, 4.242))
        path.addLine(to: p(7.191, 2.926))
        path.addCurve(to: p(5.949, 2.25),
                      control1: p(6.918, 2.508), control2: p(6.449, 2.254))
        path.addLine(to: p(3.0, 2.25))
        path.addCurve(to: p(1.5, 3.75),
                      control1: p(2.172, 2.25), control2: p(1.5, 2.922))
        path.addLine(to: p(1.5, 13.5))
        path.addCurve(to: p(3.0, 15.0),
                      control1: p(1.5, 14.328), control2: p(2.172, 15.0))
        path.closeSubpath()

        path.move(to: p(1.5, 7.5))
        path.addLine(to: p(16.5, 7.5))
        return path
    }
}

/// Custom git-branch icon used in place of SF Symbols `arrow.triangle.branch`.
struct BranchIcon: View {
    var size: CGFloat = 13

    var body: some View {
        BranchIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.5 * (size / 18),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct BranchIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 18
        let dx = (rect.width  - 18 * s) / 2
        let dy = (rect.height - 18 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        let r: CGFloat = 2.023
        path.addEllipse(in: CGRect(x: dx + (3.75 - r) * s, y: dy + (3.75 - r) * s,
                                   width: 2 * r * s, height: 2 * r * s))
        path.addEllipse(in: CGRect(x: dx + (14.25 - r) * s, y: dy + (3.75 - r) * s,
                                   width: 2 * r * s, height: 2 * r * s))
        path.addEllipse(in: CGRect(x: dx + (3.75 - r) * s, y: dy + (14.25 - r) * s,
                                   width: 2 * r * s, height: 2 * r * s))

        path.move(to: p(3.75, 5.773))
        path.addLine(to: p(3.75, 12.227))

        path.move(to: p(14.25, 5.773))
        path.addLine(to: p(14.25, 7.5))
        path.addCurve(to: p(12.75, 9.0),
                      control1: p(14.25, 8.5), control2: p(13.75, 9.0))
        path.addLine(to: p(3.75, 9.0))
        return path
    }
}

/// Custom pin icon used in place of SF Symbols `pin` / `pin.fill`.
struct PinIcon: View {
    var size: CGFloat = 13

    var body: some View {
        PinIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.2 * (size / 18),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct PinIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 18
        let dx = (rect.width  - 18 * s) / 2
        let dy = (rect.height - 18 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()
        path.move(to: p(1.5, 16.359))
        path.addCurve(to: p(2.887, 15.172),
                      control1: p(1.734, 16.156), control2: p(2.445, 15.594))
        path.addCurve(to: p(4.184, 13.859),
                      control1: p(3.336, 14.762), control2: p(3.734, 14.281))
        path.addCurve(to: p(5.594, 12.699),
                      control1: p(4.637, 13.453), control2: p(5.363, 12.887))

        path.move(to: p(5.594, 12.609))
        path.addCurve(to: p(4.934, 11.527), control1: p(5.484, 12.426), control2: p(5.191, 11.859))
        path.addCurve(to: p(4.066, 10.598), control1: p(4.672, 11.199), control2: p(4.344, 10.922))
        path.addCurve(to: p(3.227, 9.637),  control1: p(3.773, 10.281), control2: p(3.414, 10.004))
        path.addCurve(to: p(2.934, 8.414),  control1: p(3.039, 9.277),  control2: p(2.918, 8.828))
        path.addCurve(to: p(3.262, 7.215),  control1: p(2.934, 8.016),  control2: p(3.016, 7.492))
        path.addCurve(to: p(4.387, 6.699),  control1: p(3.496, 6.922),  control2: p(3.984, 6.809))
        path.addCurve(to: p(5.648, 6.539),  control1: p(4.777, 6.586),  control2: p(5.227, 6.629))
        path.addCurve(to: p(6.855, 6.137),  control1: p(6.059, 6.449),  control2: p(6.465, 6.309))
        path.addCurve(to: p(7.957, 5.527),  control1: p(7.238, 5.969),  control2: p(7.637, 5.789))
        path.addCurve(to: p(8.805, 4.574),  control1: p(8.289, 5.273),  control2: p(8.551, 4.914))
        path.addCurve(to: p(9.465, 3.480),  control1: p(9.047, 4.230),  control2: p(9.227, 3.840))
        path.addCurve(to: p(10.215, 2.461), control1: p(9.703, 3.137),  control2: p(9.922, 2.754))
        path.addCurve(to: p(11.266, 1.754), control1: p(10.516, 2.176), control2: p(10.875, 1.867))
        path.addCurve(to: p(12.516, 1.793), control1: p(11.648, 1.641), control2: p(12.129, 1.680))
        path.addCurve(to: p(13.605, 2.422), control1: p(12.906, 1.898), control2: p(13.273, 2.168))
        path.addCurve(to: p(14.504, 3.324), control1: p(13.934, 2.676), control2: p(14.203, 3.023))
        path.addCurve(to: p(15.367, 4.262), control1: p(14.789, 3.629), control2: p(15.090, 3.938))
        path.addCurve(to: p(16.164, 5.258), control1: p(15.645, 4.582), control2: p(15.977, 4.883))
        path.addCurve(to: p(16.449, 6.473), control1: p(16.336, 5.625), control2: p(16.500, 6.098))
        path.addCurve(to: p(15.840, 7.547), control1: p(16.395, 6.855), control2: p(16.109, 7.238))
        path.addCurve(to: p(14.797, 8.289), control1: p(15.570, 7.836), control2: p(15.148, 8.031))
        path.addCurve(to: p(13.770, 9.039), control1: p(14.461, 8.527), control2: p(14.102, 8.773))
        path.addCurve(to: p(12.809, 9.871), control1: p(13.441, 9.301), control2: p(13.109, 9.570))
        path.addCurve(to: p(11.977, 10.828),control1: p(12.512, 10.172),control2: p(12.156, 10.461))
        path.addCurve(to: p(11.699, 12.051),control1: p(11.789, 11.199),control2: p(11.762, 11.633))
        path.addCurve(to: p(11.641, 13.320),control1: p(11.648, 12.473),control2: p(11.754, 12.922))
        path.addCurve(to: p(11.047, 14.438),control1: p(11.520, 13.727),control2: p(11.316, 14.129))
        path.addCurve(to: p(10.004, 15.137),control1: p(10.770, 14.738),control2: p(10.379, 15.059))
        path.addCurve(to: p(8.773, 14.902), control1: p(9.621, 15.219), control2: p(9.156, 15.051))
        path.addCurve(to: p(7.703, 14.219), control1: p(8.391, 14.746), control2: p(8.039, 14.484))
        path.addCurve(to: p(6.773, 13.359), control1: p(7.363, 13.965), control2: p(7.102, 13.613))
        path.addCurve(to: p(5.684, 12.699), control1: p(6.434, 13.102), control2: p(5.863, 12.809))
        return path
    }
}
