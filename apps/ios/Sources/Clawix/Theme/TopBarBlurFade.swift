import SwiftUI

// Top-edge tint that floats behind the floating glass top bar of the
// home, project, and chat surfaces. Mirrors the bottom-edge gradient
// used under the composer (`Palette.background.opacity(0) → 1`) so
// both edges read as the same canvas fading out.
//
// We deliberately do NOT stack a `UIVisualEffectView` material here.
// Even `.systemThickMaterialDark` carries a baseline luminosity to
// keep the blur visible over flat content; on a pure black canvas
// that lifts the area above the surrounding black and reads as a
// gray halo. A plain gradient over the same canvas color renders as
// true black at full opacity, which is what the bottom edge already
// does correctly.
//
// `bottomBoost` (0..1) extends the dark area further down before the
// fade-out. Used in search mode where there's no section header to
// provide visual padding under the search pill.
struct TopBarBlurFade: View {
    var height: CGFloat
    var bottomBoost: CGFloat = 0

    var body: some View {
        LinearGradient(
            stops: tintStops,
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
    }

    private var tintStops: [Gradient.Stop] {
        let midOpacity = 0.92 + 0.06 * bottomBoost
        let lowOpacity = 0.30 + 0.35 * bottomBoost
        let lowLocation = 0.80 + 0.10 * bottomBoost
        return [
            .init(color: Palette.background, location: 0.0),
            .init(color: Palette.background.opacity(midOpacity), location: 0.45),
            .init(color: Palette.background.opacity(lowOpacity), location: lowLocation),
            .init(color: Palette.background.opacity(0.0), location: 1.0)
        ]
    }
}

extension View {
    func topBarBlurFade(height: CGFloat, bottomBoost: CGFloat = 0) -> some View {
        overlay(alignment: .top) {
            TopBarBlurFade(height: height, bottomBoost: bottomBoost)
        }
    }
}
