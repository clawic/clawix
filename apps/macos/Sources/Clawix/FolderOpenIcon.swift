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

    var body: some View {
        FolderClosedIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.5 * (size / 18),
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

/// Folder icon that morphs continuously between closed (`progress == 0`) and
/// open (`progress == 1`). The outline is split in two stroked sub-shapes:
/// `Front` (the lid in open state, the bottom rectangle + seam in closed) and
/// `Back` (the back panel in open state, the rest of the outline in closed).
/// The back stroke thins as the folder opens, suggesting depth. Both shapes
/// share a 20-anchor topology so SwiftUI can interpolate via `animatableData`.
struct FolderMorphIcon: View {
    var size: CGFloat = 13
    var progress: CGFloat
    var lineWidthScale: CGFloat = 1.0

    var body: some View {
        let baseWidth = 1.5 * (size / 18) * lineWidthScale
        let backWidth = baseWidth * (1.0 - 0.32 * progress)
        ZStack {
            FolderMorphBackInsetShape(progress: progress, lineWidth: backWidth)
            FolderMorphFrontInsetShape(progress: progress, lineWidth: baseWidth)
        }
        .frame(width: size * 1.18, height: size)
    }
}

private struct FolderMorphFrontInsetShape: Shape {
    var progress: CGFloat
    var lineWidth: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, lineWidth) }
        set {
            progress = newValue.first
            lineWidth = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 18
        let dx = (rect.width  - 18 * s) / 2
        let dy = (rect.height - 18 * s) / 2
        func L(_ cx: CGFloat, _ cy: CGFloat, _ ox: CGFloat, _ oy: CGFloat) -> CGPoint {
            let x = cx + (ox - cx) * progress
            let y = cy + (oy - cy) * progress
            return CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var raw = Path()
        raw.move(to: L(3.0, 15.0,  3.0, 15.0))
        raw.addLine(to: L(3.0, 15.0,  4.5, 10.5))
        raw.addLine(to: L(3.0, 15.0,  5.625, 8.324))
        raw.addCurve(
            to:       L(1.5, 13.5,    6.93, 7.5),
            control1: L(2.172, 15.0,  5.875, 7.828),
            control2: L(1.5, 14.328,  6.375, 7.512)
        )
        raw.addLine(to: L(1.5, 7.5,  15.0, 7.5))
        raw.addCurve(
            to:       L(16.5, 7.5,    16.188, 8.082),
            control1: L(5.5, 7.5,     15.465, 7.5),
            control2: L(12.5, 7.5,    15.902, 7.715)
        )
        raw.addCurve(
            to:       L(16.5, 7.5,    16.453, 9.375),
            control1: L(16.5, 7.5,    16.473, 8.449),
            control2: L(16.5, 7.5,    16.570, 8.926)
        )
        raw.addLine(to: L(16.5, 13.5, 15.301, 13.875))
        raw.addCurve(
            to:       L(15.0, 15.0,   13.836, 15.0),
            control1: L(16.5, 14.328, 15.129, 14.539),
            control2: L(15.828, 15.0, 14.523, 15.004)
        )
        raw.addLine(to: L(3.0, 15.0,  3.0, 15.0))
        return raw.strokedPath(StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round
        ))
    }
}

private struct FolderMorphBackInsetShape: Shape {
    var progress: CGFloat
    var lineWidth: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, lineWidth) }
        set {
            progress = newValue.first
            lineWidth = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 18
        let dx = (rect.width  - 18 * s) / 2
        let dy = (rect.height - 18 * s) / 2
        func L(_ cx: CGFloat, _ cy: CGFloat, _ ox: CGFloat, _ oy: CGFloat) -> CGPoint {
            let x = cx + (ox - cx) * progress
            let y = cy + (oy - cy) * progress
            return CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var raw = Path()
        raw.move(to: L(3.0, 15.0,  3.0, 15.0))
        raw.addCurve(
            to:       L(1.5, 13.5,    1.5, 13.5),
            control1: L(2.172, 15.0,  2.172, 15.0),
            control2: L(1.5, 14.328,  1.5, 14.328)
        )
        raw.addLine(to: L(1.5, 3.75,  1.5, 3.75))
        raw.addCurve(
            to:       L(3.0, 2.25,    3.0, 2.25),
            control1: L(1.5, 2.922,   1.5, 2.922),
            control2: L(2.172, 2.25,  2.172, 2.25)
        )
        raw.addLine(to: L(5.949, 2.25, 5.949, 2.25))
        raw.addCurve(
            to:       L(7.191, 2.926, 7.191, 2.926),
            control1: L(6.449, 2.254, 6.449, 2.254),
            control2: L(6.918, 2.508, 6.918, 2.508)
        )
        raw.addLine(to: L(7.809, 3.824, 7.809, 3.824))
        raw.addCurve(
            to:       L(9.051, 4.5,   9.051, 4.5),
            control1: L(8.082, 4.242, 8.082, 4.242),
            control2: L(8.551, 4.496, 8.551, 4.496)
        )
        raw.addLine(to: L(15.0, 4.5,  13.5, 4.5))
        raw.addCurve(
            to:       L(16.5, 6.0,    15.0, 6.0),
            control1: L(15.828, 4.5,  14.328, 4.5),
            control2: L(16.5, 5.172,  15.0, 5.172)
        )
        raw.addLine(to: L(16.5, 13.5, 15.0, 7.5))
        return raw.strokedPath(StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round
        ))
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
    var lineWidth: CGFloat? = nil

    var body: some View {
        PinIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth ?? (1.2 * (size / 18)),
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

/// Archive / box icon used in the sidebar's trailing slot on row hover.
/// Outline style, drawn directly with SwiftUI Path so it tints with
/// `.foregroundColor` and scales cleanly without a PDF asset round trip.
struct ArchiveIcon: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat? = nil

    var body: some View {
        ArchiveIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: lineWidth ?? (1.5 * (size / 24)),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct ArchiveIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(3.25, 5.6))
        path.addArc(tangent1End: p(3.25, 4.2),  tangent2End: p(4.65, 4.2),  radius: 1.4 * s)
        path.addLine(to: p(19.35, 4.2))
        path.addArc(tangent1End: p(20.75, 4.2), tangent2End: p(20.75, 5.6), radius: 1.4 * s)
        path.addLine(to: p(20.75, 7.6))
        path.addArc(tangent1End: p(20.75, 8.8), tangent2End: p(19.55, 8.8), radius: 1.2 * s)
        path.addLine(to: p(4.45, 8.8))
        path.addArc(tangent1End: p(3.25, 8.8),  tangent2End: p(3.25, 7.6),  radius: 1.2 * s)
        path.closeSubpath()

        path.move(to: p(4, 9))
        path.addLine(to: p(20, 9))
        path.addLine(to: p(20, 16.6))
        path.addArc(tangent1End: p(20, 20.2), tangent2End: p(16.4, 20.2), radius: 3.6 * s)
        path.addLine(to: p(7.6, 20.2))
        path.addArc(tangent1End: p(4, 20.2),  tangent2End: p(4, 16.6),    radius: 3.6 * s)
        path.closeSubpath()

        path.move(to: p(10, 12.6))
        path.addLine(to: p(14, 12.6))

        return path
    }
}

/// Unarchive icon: same outline language as `ArchiveIcon` but the lid is
/// reduced to two corner stubs and the body's top edge is cut by the same
/// amount, so an upward arrow rises from inside the box without crossing
/// any silhouette stroke. Used in the sidebar's archived rows in place of
/// the pin slot.
struct UnarchiveIcon: View {
    var size: CGFloat = 14

    var body: some View {
        UnarchiveIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 1.5 * (size / 24),
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct UnarchiveIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var path = Path()

        path.move(to: p(5.7, 4.2))
        path.addLine(to: p(4.65, 4.2))
        path.addArc(tangent1End: p(3.25, 4.2), tangent2End: p(3.25, 5.6), radius: 1.4 * s)
        path.addLine(to: p(3.25, 7.6))
        path.addArc(tangent1End: p(3.25, 8.8), tangent2End: p(4.45, 8.8), radius: 1.2 * s)

        path.move(to: p(18.3, 4.2))
        path.addLine(to: p(19.35, 4.2))
        path.addArc(tangent1End: p(20.75, 4.2), tangent2End: p(20.75, 5.6), radius: 1.4 * s)
        path.addLine(to: p(20.75, 7.6))
        path.addArc(tangent1End: p(20.75, 8.8), tangent2End: p(19.55, 8.8), radius: 1.2 * s)

        path.move(to: p(5.7, 9))
        path.addLine(to: p(4, 9))
        path.addLine(to: p(4, 16.6))
        path.addArc(tangent1End: p(4, 20.2), tangent2End: p(7.6, 20.2), radius: 3.6 * s)
        path.addLine(to: p(16.4, 20.2))
        path.addArc(tangent1End: p(20, 20.2), tangent2End: p(20, 16.6), radius: 3.6 * s)
        path.addLine(to: p(20, 9))
        path.addLine(to: p(18.3, 9))

        path.move(to: p(12, 12))
        path.addLine(to: p(12, 3))
        path.move(to: p(9, 5.5))
        path.addLine(to: p(12, 3))
        path.addLine(to: p(15, 5.5))

        return path
    }
}

/// Archive box icon that morphs into an unarchive arrow on hover.
///
/// At rest it draws a closed lid plus a body silhouette (left side + bottom
/// arcs + right side) with a horizontal slot bar inside. The body has NO
/// top edge — the lid's bottom is the only horizontal at the lid–body
/// interface, so reducing the stroke colour does not produce a darker
/// band wherever two strokes overlap.
///
/// On hover it plays a staggered morph: slot collapses fast toward its
/// centre, body's bottom edge opens symmetrically, an upward arrow grows
/// from `(12, 12.6)` (the slot's collapse point), and the silhouette
/// shifts to a darker grey + slightly thinner stroke. Un-hover reverses
/// the order: arrow retracts first, body closes, slot grows back.
struct ArchiveUnarchiveMorphIcon: View {
    var size: CGFloat = 12
    var hovered: Bool
    /// True when the cursor is over the icon's own hit area (not the
    /// surrounding row). Mirrors the pin button's pattern: hovering the
    /// row triggers the morph animation, but the box's stroke colour
    /// only jumps to full white when the cursor lands on the icon
    /// itself, signalling that the click target is the icon.
    var iconHovered: Bool = false

    @State private var slotProgress: Double = 0
    @State private var bodyProgress: Double = 0
    @State private var shaftProgress: Double = 0
    @State private var headProgress: Double = 0
    /// Pending hover-in trigger. The morph starts only after the cursor
    /// has rested on the row for `hoverInDelay`, so brushing over the
    /// archived list doesn't flash the arrow. Cancelled if the cursor
    /// leaves before the delay expires.
    @State private var pendingHoverIn: DispatchWorkItem?

    private let hoverInDelay: TimeInterval = 0.3

    var body: some View {
        // Box stroke sits at the same intermediate opacity as the pin
        // icon (slightly above white 0.5 so the silhouette still reads
        // when only the lid is closed) and only goes full bright when
        // the icon itself is hovered. The morph animation no longer
        // dims the box — the row-hover state opens the hole, the box
        // keeps its resting weight.
        let strokeColor = iconHovered ? Color(white: 0.94) : Color(white: 0.55)
        let arrowColor = Color(white: 0.96)
        // Stroke width matches the section header's ArchiveIcon (1.28pt
        // fixed) so the per-row morph reads at the same visual weight as
        // the "Archived" section icon. Without this, the formula-derived
        // 1.5 * (size/24) ≈ 1.03pt makes the row icon look thinner and
        // therefore "smaller" than the header.
        let style = StrokeStyle(lineWidth: 1.28, lineCap: .round, lineJoin: .round)
        let arrowStyle = StrokeStyle(lineWidth: 1.28, lineCap: .round, lineJoin: .round)

        ZStack {
            ArchiveMorphLidShape()
                .stroke(strokeColor, style: style)
            ArchiveMorphBodyHalfShape(side: .left)
                .trim(from: 0, to: 1 - 0.2493 * bodyProgress)
                .stroke(strokeColor, style: style)
            ArchiveMorphBodyHalfShape(side: .right)
                .trim(from: 0, to: 1 - 0.2493 * bodyProgress)
                .stroke(strokeColor, style: style)
            ArchiveMorphSlotHalfShape(side: .left)
                .trim(from: 0, to: 1 - slotProgress)
                .stroke(strokeColor, style: style)
            ArchiveMorphSlotHalfShape(side: .right)
                .trim(from: 0, to: 1 - slotProgress)
                .stroke(strokeColor, style: style)
            ArchiveMorphArrowShaftShape()
                .trim(from: 0, to: shaftProgress)
                .stroke(arrowColor, style: arrowStyle)
            ArchiveMorphArrowHeadShape(side: .left)
                .trim(from: 0, to: headProgress)
                .stroke(arrowColor, style: arrowStyle)
            ArchiveMorphArrowHeadShape(side: .right)
                .trim(from: 0, to: headProgress)
                .stroke(arrowColor, style: arrowStyle)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.16), value: iconHovered)
        .onChange(of: hovered) { _, isHovering in
            pendingHoverIn?.cancel()
            pendingHoverIn = nil
            if isHovering {
                let work = DispatchWorkItem { animate(toHover: true) }
                pendingHoverIn = work
                DispatchQueue.main.asyncAfter(deadline: .now() + hoverInDelay, execute: work)
            } else {
                animate(toHover: false)
            }
        }
    }

    private func animate(toHover v: Bool) {
        let target: Double = v ? 1.0 : 0.0
        if v {
            // Hover order: slot collapses → body opens → arrow grows.
            withAnimation(.easeOut(duration: 0.14)) { slotProgress = target }
            withAnimation(.easeOut(duration: 0.30).delay(0.06)) { bodyProgress = target }
            withAnimation(.easeOut(duration: 0.26).delay(0.14)) { shaftProgress = target }
            withAnimation(.easeOut(duration: 0.22).delay(0.18)) { headProgress = target }
        } else {
            // Un-hover order: arrow retracts → body closes → slot regrows.
            withAnimation(.easeOut(duration: 0.18)) { shaftProgress = target }
            withAnimation(.easeOut(duration: 0.18)) { headProgress = target }
            withAnimation(.easeOut(duration: 0.18).delay(0.06)) { bodyProgress = target }
            withAnimation(.easeOut(duration: 0.14).delay(0.22)) { slotProgress = target }
        }
    }
}

private enum ArchiveMorphSide { case left, right }

private struct ArchiveMorphLidShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()
        path.move(to: p(3.25, 5.6))
        path.addArc(tangent1End: p(3.25, 4.2), tangent2End: p(4.65, 4.2), radius: 1.4 * s)
        path.addLine(to: p(19.35, 4.2))
        path.addArc(tangent1End: p(20.75, 4.2), tangent2End: p(20.75, 5.6), radius: 1.4 * s)
        path.addLine(to: p(20.75, 7.6))
        path.addArc(tangent1End: p(20.75, 8.8), tangent2End: p(19.55, 8.8), radius: 1.2 * s)
        path.addLine(to: p(4.45, 8.8))
        path.addArc(tangent1End: p(3.25, 8.8), tangent2End: p(3.25, 7.6), radius: 1.2 * s)
        path.closeSubpath()
        return path
    }
}

/// One half of the body silhouette. Each half traces from the top-corner
/// (4, 9) or (20, 9) through the side, around the bottom arc, ending at
/// bottom-centre (12, 20.2). Total length 17.65; the last 4.4 is the
/// half of the bottom edge so trimming `to: 0.7507` retracts exactly that.
private struct ArchiveMorphBodyHalfShape: Shape {
    let side: ArchiveMorphSide

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()
        switch side {
        case .left:
            path.move(to: p(4, 9))
            path.addLine(to: p(4, 16.6))
            path.addArc(tangent1End: p(4, 20.2), tangent2End: p(7.6, 20.2), radius: 3.6 * s)
            path.addLine(to: p(12, 20.2))
        case .right:
            path.move(to: p(20, 9))
            path.addLine(to: p(20, 16.6))
            path.addArc(tangent1End: p(20, 20.2), tangent2End: p(16.4, 20.2), radius: 3.6 * s)
            path.addLine(to: p(12, 20.2))
        }
        return path
    }
}

private struct ArchiveMorphSlotHalfShape: Shape {
    let side: ArchiveMorphSide

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()
        path.move(to: p(12, 12.6))
        path.addLine(to: p(side == .left ? 10 : 14, 12.6))
        return path
    }
}

private struct ArchiveMorphArrowShaftShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()
        path.move(to: p(12, 12.6))
        path.addLine(to: p(12, 20.2))
        return path
    }
}

private struct ArchiveMorphArrowHeadShape: Shape {
    let side: ArchiveMorphSide

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        var path = Path()
        path.move(to: p(12, 12.6))
        path.addLine(to: p(side == .left ? 9 : 15, 15))
        return path
    }
}

/// "Add new folder/project" icon. Closed-folder silhouette with the bottom
/// half of the right edge and the right half of the bottom edge cut away;
/// a thin elongated "+" sits inside that L-shaped notch.
/// Substitute for SF Symbol `folder.badge.plus`, whose plus floats outside
/// the folder bounds in a way the user rejected.
struct FolderAddIcon: View {
    var size: CGFloat = 13
    /// Plus stroke width in viewBox units (24×24 grid). 1.55 matches the
    /// visual weight of the folder's chunky outline; smaller values
    /// disappear at sidebar-header sizes.
    var plusStrokeWidth: CGFloat = 1.55

    var body: some View {
        ZStack {
            FolderAddBodyShape()
                .fill()
            FolderAddPlusShape()
                .stroke(style: StrokeStyle(
                    lineWidth: plusStrokeWidth * (size / 24),
                    lineCap: .round
                ))
        }
        .frame(width: size, height: size)
    }
}

/// Filled folder body with three regions removed: upper compartment cutout,
/// lower compartment cutout, and the L-shaped notch in the bottom-right
/// corner. Two small caps are unioned back in to round off the raw stroke
/// endings exposed by the notch.
///
/// Built with `Path.subtracting` / `Path.union` (macOS 13+) instead of
/// even-odd fill, because even-odd would re-fill regions where the notch
/// rect extends past the folder's outer silhouette (the rounded corner) or
/// overlaps the inner-compartment cutouts.
private struct FolderAddBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }

        var outer = Path()
        outer.move(to: p(3.4, 6.2))
        outer.addQuadCurve(to: p(5.2, 4.4), control: p(3.4, 4.4))
        outer.addLine(to: p(9.6, 4.4))
        outer.addQuadCurve(to: p(11.25, 5.15), control: p(10.6, 4.4))
        outer.addLine(to: p(12.55, 6.65))
        outer.addQuadCurve(to: p(13.85, 7.2), control: p(13.0, 7.2))
        outer.addLine(to: p(18.8, 7.2))
        outer.addQuadCurve(to: p(20.6, 9.0), control: p(20.6, 7.2))
        outer.addLine(to: p(20.6, 18.8))
        outer.addQuadCurve(to: p(18.8, 20.6), control: p(20.6, 20.6))
        outer.addLine(to: p(5.2, 20.6))
        outer.addQuadCurve(to: p(3.4, 18.8), control: p(3.4, 20.6))
        outer.closeSubpath()

        var upper = Path()
        upper.move(to: p(5.0, 6.2))
        upper.addQuadCurve(to: p(5.2, 6.0), control: p(5.0, 6.0))
        upper.addLine(to: p(9.4, 6.0))
        upper.addQuadCurve(to: p(10.15, 6.35), control: p(9.85, 6.0))
        upper.addLine(to: p(11.45, 7.85))
        upper.addQuadCurve(to: p(13.0, 8.6), control: p(12.05, 8.55))
        upper.addLine(to: p(18.8, 8.6))
        upper.addQuadCurve(to: p(19.0, 8.8), control: p(19.0, 8.6))
        upper.addLine(to: p(19.0, 10.0))
        upper.addLine(to: p(5.0, 10.0))
        upper.closeSubpath()

        var lower = Path()
        lower.move(to: p(5.0, 11.6))
        lower.addLine(to: p(19.0, 11.6))
        lower.addLine(to: p(19.0, 18.4))
        lower.addQuadCurve(to: p(18.4, 19.0), control: p(19.0, 19.0))
        lower.addLine(to: p(5.6, 19.0))
        lower.addQuadCurve(to: p(5.0, 18.4), control: p(5.0, 19.0))
        lower.closeSubpath()

        let notch = Path(CGRect(
            x: dx + 13 * s,
            y: dy + 13 * s,
            width: 11 * s,
            height: 11 * s
        ))

        let r: CGFloat = 0.8
        let capBottom = Path(ellipseIn: CGRect(
            x: dx + (13 - r) * s,
            y: dy + (19.8 - r) * s,
            width: 2 * r * s,
            height: 2 * r * s
        ))
        let capRight = Path(ellipseIn: CGRect(
            x: dx + (19.8 - r) * s,
            y: dy + (13 - r) * s,
            width: 2 * r * s,
            height: 2 * r * s
        ))

        return outer
            .subtracting(upper)
            .subtracting(lower)
            .subtracting(notch)
            .union(capBottom)
            .union(capRight)
    }
}

/// The "+" centered at (16.8, 16.8) with arm length 2.2.
private struct FolderAddPlusShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * s, y: dy + y * s)
        }
        // Pushed toward the bottom-right corner so the larger plus stays
        // within the L-notch and visually centers in the cut zone.
        let cx: CGFloat = 18.9, cy: CGFloat = 18.9, arm: CGFloat = 3.4

        var path = Path()
        path.move(to: p(cx - arm, cy))
        path.addLine(to: p(cx + arm, cy))
        path.move(to: p(cx, cy - arm))
        path.addLine(to: p(cx, cy + arm))
        return path
    }
}

/// Use in row helpers that pass icon names as strings.
/// Special-cases `"folder"` and `"pin"`/`"pin.fill"` to render the custom icons,
/// falls back to SF Symbols otherwise.
struct IconImage: View {
    let name: String
    var size: CGFloat = 13

    init(_ name: String, size: CGFloat = 13) {
        self.name = name
        self.size = size
    }

    var body: some View {
        switch name {
        case "folder":
            FolderOpenIcon(size: size)
        case "pin", "pin.fill":
            PinIcon(size: size)
        case "arrow.triangle.branch":
            BranchIcon(size: size)
        case "cursor":
            CursorIcon(size: size)
        case "chart.bar", "gauge.with.dots.needle.33percent":
            UsageIcon(size: size)
        default:
            Image(systemName: name)
                .font(BodyFont.system(size: size))
        }
    }
}
