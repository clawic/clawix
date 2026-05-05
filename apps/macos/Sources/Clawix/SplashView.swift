import SwiftUI

/// First-paint screen shown until the app's window has settled. Fills the
/// window with the same near-black `Palette.background` used everywhere
/// else and animates the brand mark in. Cross-fades out under the real
/// chrome once the entry animation has finished, so there is never a
/// frame where the user sees a half-laid-out window.
struct SplashView: View {
    var onComplete: () -> Void

    @State private var logoOpacity: CGFloat = 0
    @State private var logoScale: CGFloat = 0.86

    var body: some View {
        ZStack {
            Palette.background
                .ignoresSafeArea()

            ClawixLogoIcon(size: 96)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                logoOpacity = 1
                logoScale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                onComplete()
            }
        }
    }
}

/// Wraps `ContentView` with the splash overlay. Lives in `App.swift`'s
/// `WindowGroup` so the splash is the very first thing painted.
struct AppRootView: View {
    @State private var splashShown = true

    var body: some View {
        ContentView()
            .overlay {
                if splashShown {
                    SplashView(onComplete: {
                        withAnimation(.easeOut(duration: 0.35)) {
                            splashShown = false
                        }
                    })
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
    }
}
