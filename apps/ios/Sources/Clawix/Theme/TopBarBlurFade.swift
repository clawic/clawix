import SwiftUI
import UIKit

// Pure dark blur backdrop with no SwiftUI vibrancy whitening.
// SwiftUI Materials add a vibrancy layer that lifts dark areas to a
// gray that reads as a halo over a black canvas; UIKit's
// `.systemThickMaterialDark` keeps the blur strong while staying
// neutral against the underlying black.
struct NeutralDarkBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// Compound top-edge effect that floats behind the floating glass top
// bar of the home, project, and chat surfaces. Two layers stacked:
//
//   1. NeutralDarkBlur masked with a top→bottom gradient so scroll
//      content underneath is softly blurred near the chrome and
//      fully unblurred toward the bottom.
//   2. A second LinearGradient of the canvas tint that darkens the
//      same area so the chrome separates cleanly from the content.
//
// `bottomBoost` (0..1) extends the dark/blur further down before the
// fade-out. Used in search mode where there's no section header to
// provide visual padding under the search pill.
struct TopBarBlurFade: View {
    var height: CGFloat
    var bottomBoost: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            NeutralDarkBlur()
                .mask(
                    LinearGradient(
                        stops: blurStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LinearGradient(
                stops: tintStops,
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
    }

    private var blurStops: [Gradient.Stop] {
        let midOpacity = 0.45 + 0.35 * bottomBoost
        let midLocation = 0.80 + 0.10 * bottomBoost
        return [
            .init(color: Color.black, location: 0.0),
            .init(color: Color.black, location: 0.45),
            .init(color: Color.black.opacity(midOpacity), location: midLocation),
            .init(color: Color.clear, location: 1.0)
        ]
    }

    private var tintStops: [Gradient.Stop] {
        let topOpacity = 0.72 + 0.10 * bottomBoost
        let midOpacity = 0.66 + 0.12 * bottomBoost
        let lowOpacity = 0.30 + 0.35 * bottomBoost
        let lowLocation = 0.80 + 0.10 * bottomBoost
        return [
            .init(color: Palette.background.opacity(topOpacity), location: 0.0),
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
