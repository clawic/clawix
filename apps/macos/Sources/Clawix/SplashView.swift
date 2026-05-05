import SwiftUI

/// First-paint screen shown until the app's window has settled. Uses the
/// same frosted-sidebar material that fills the real chrome behind the
/// content panel, so the swap to `ContentView` is invisible. The brand
/// mark is painted from frame 1 (no fade-in) and then hidden with a very
/// quick fade-out before `onComplete` fires, so the icon never shares a
/// frame with the laid-out window.
struct SplashView: View {
    var onComplete: () -> Void

    @State private var logoOpacity: CGFloat = 0.75

    private let hold: Double = 1.1
    private let fadeOut: Double = 0.16

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .overlay(Color.black.opacity(0.08))
                .ignoresSafeArea()

            ClawixLogoIcon(size: 84)
                .opacity(logoOpacity)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                withAnimation(.easeIn(duration: fadeOut)) {
                    logoOpacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + hold + fadeOut + 0.03) {
                onComplete()
            }
        }
    }
}

/// Wraps `ContentView` with the splash. Lives in `App.swift`'s
/// `WindowGroup` so the splash is the very first thing painted. The real
/// chrome is gated behind `splashShown` so the icon never shares a frame
/// with the laid-out window. The persistent frosted backdrop matches the
/// one `ContentView` paints, so the swap leaves no visible seam.
struct AppRootView: View {
    @State private var splashShown = true

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .overlay(Color.black.opacity(0.08))
                .ignoresSafeArea()

            if splashShown {
                SplashView(onComplete: {
                    splashShown = false
                })
            } else {
                ContentView()
            }
        }
    }
}
