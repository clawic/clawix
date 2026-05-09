import SwiftUI

/// Word-wrap toggle icon. Morphs between two states based on `progress`:
///   - 0 → curved "return" arrow + right-margin bar (wrap mode active).
///   - 1 → straight horizontal arrow + bar (no-wrap, lines overflow past
///         the bar).
///
/// Designed on a 24×24 canvas. The arrow (shaft + arrowhead) drives the
/// morph; the bar at x=20 stays still. `rightBarOpacity` fades the bar
/// during hover so the morphing arrow remains the visual focus.
///
/// Both states share an M-C-L-C-L shaft and an M-L-L head, so each anchor
/// and control point interpolates linearly with `progress` and SwiftUI's
/// `animatableData` produces a smooth tween.
///
/// Usage in interactive toolbars: drive `progress` from a hover flag so the
/// icon previews the *opposite* mode while the cursor is over it, and lower
/// `rightBarOpacity` at the same time.
///
/// Usage in static menu rows: pass the current mode as `progress` and leave
/// `rightBarOpacity` at 1. No hover, no animation.
struct WordWrapToggleIcon: View {
    /// 0 = wrap mode (curved return arrow).
    /// 1 = no-wrap mode (straight arrow toward the bar).
    var progress: CGFloat = 0
    /// Right vertical bar opacity. Drop to ~0.4 during hover to let the
    /// arrow read as the active visual.
    var rightBarOpacity: CGFloat = 1
    var color: Color = .primary
    var lineWidth: CGFloat = 1.0

    var body: some View {
        ZStack {
            WordWrapArrowShape(progress: progress)
                .stroke(color, style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                ))
            WordWrapBarShape()
                .stroke(color, style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                ))
                .opacity(rightBarOpacity)
        }
    }
}

/// Morphing arrow: shaft (M-C-L-C-L) + arrowhead (M-L-L). Each pair of
/// numbers below is `(stateA, stateB)`, interpolated by `progress`.
private struct WordWrapArrowShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2

        func l(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
            a + (b - a) * progress
        }
        func pt(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) -> CGPoint {
            CGPoint(x: dx + l(ax, bx) * s, y: dy + l(ay, by) * s)
        }

        var path = Path()

        // Shaft. State A (progress 0): a curved return tail starting at
        // (13,5), hooking down past x=15 and curving left to (4,16).
        // State B (progress 1): a straight horizontal segment at y=12 from
        // x=5 to x=17. The cubic control points in state B sit on the line
        // (y=12) so the segment renders perfectly straight without a
        // separate path structure.
        path.move(to: pt(13, 5, 5, 12))
        path.addCurve(
            to:       pt(15, 7,    11, 12),
            control1: pt(14.1, 5,   7, 12),
            control2: pt(15, 5.9,   9, 12)
        )
        path.addLine(to: pt(15, 11, 13, 12))
        path.addCurve(
            to:       pt(10, 16,    16, 12),
            control1: pt(15, 13.76, 14, 12),
            control2: pt(12.76, 16, 15, 12)
        )
        path.addLine(to: pt(4, 16, 17, 12))

        // Arrowhead. State A: V opening right, tip at (4,16).
        // State B: V opening left, tip at (17,12).
        path.move(to: pt(8, 13, 13, 8))
        path.addLine(to: pt(4, 16, 17, 12))
        path.addLine(to: pt(8, 19, 13, 16))

        return path
    }
}

/// Right-margin bar at x=20, y=5..19. Static across both states.
private struct WordWrapBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let dx = (rect.width  - 24 * s) / 2
        let dy = (rect.height - 24 * s) / 2
        var path = Path()
        path.move(to: CGPoint(x: dx + 20 * s, y: dy +  5 * s))
        path.addLine(to: CGPoint(x: dx + 20 * s, y: dy + 19 * s))
        return path
    }
}
