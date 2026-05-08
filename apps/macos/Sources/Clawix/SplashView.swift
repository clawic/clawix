import SwiftUI

/// First-paint screen shown until the app's window has settled. Uses the
/// same frosted-sidebar material that fills the real chrome behind the
/// content panel, so the swap to `ContentView` is invisible. The brand
/// mark is painted from frame 1 (no fade-in) and the swap to ContentView
/// is a hard cut (no fade-out), so the splash just disappears the instant
/// the real chrome is ready.
struct SplashView: View {
    var onComplete: () -> Void

    private let hold: Double = 1.1

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .overlay(Color.black.opacity(0.08))
                .ignoresSafeArea()

            ClawixLogoIcon(size: 84)
                .opacity(0.75)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
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
    @State private var quickAddVisible = false
    @State private var dbSearchVisible = false

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

            // App-wide toast bus. Mounted at the root so any feature
            // (browser screenshot, secrets, downloads, …) can call
            // ToastCenter.shared.show(...) and the pill floats over
            // every other surface.
            ToastHost()
                .allowsHitTesting(true)

            // Database global overlays: ⌘⇧N quick-add and ⌘⇧F search.
            // Both rendered as transparent passthrough until invoked.
            if quickAddVisible {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { quickAddVisible = false }
                DatabaseQuickAddOverlay(isPresented: $quickAddVisible)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
            }
            if dbSearchVisible {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { dbSearchVisible = false }
                DatabaseSearchOverlay(isPresented: $dbSearchVisible)
            }
        }
        .background(
            DatabaseHotkeyBridge(
                quickAddVisible: $quickAddVisible,
                dbSearchVisible: $dbSearchVisible
            )
        )
    }
}

/// Hidden Button-bag whose only purpose is to register the global
/// keyboardShortcuts that toggle the database quick-add and search
/// overlays. Lives behind the visual root via `.background`.
private struct DatabaseHotkeyBridge: View {
    @Binding var quickAddVisible: Bool
    @Binding var dbSearchVisible: Bool

    var body: some View {
        ZStack {
            Button("DBQuickAdd") { quickAddVisible.toggle() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("DBSearch") { dbSearchVisible.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
