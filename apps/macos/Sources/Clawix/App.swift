import SwiftUI
import AppKit

let appDisplayName: String = {
    let info = Bundle.main.infoDictionary
    return (info?["CFBundleDisplayName"] as? String)
        ?? (info?["CFBundleName"] as? String)
        ?? "Clawix"
}()

/// Identifier used for UserDefaults suites and Application Support paths.
/// Resolves to whatever bundle id the binary was packaged with, so a fork
/// that builds with its own BUNDLE_ID gets isolated prefs without touching
/// the code. Falls back to a stable string when the binary runs unbundled.
let appPrefsSuite: String = Bundle.main.bundleIdentifier ?? "clawix.desktop"

// Shared between debug and release bundles so the window position survives
// switching between them.
private let frameDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
private let frameKey = "ClawixMainWindowFrame"

private let mainWindowMinSize = NSSize(width: 1100, height: 720)

/// Tracks window-level state that views need to reflow on, namely the
/// fullscreen toggle. macOS hides the traffic lights in fullscreen, so the
/// chrome reservation that protects the sidebar toggle from sitting under
/// them must collapse to zero whenever any window enters fullscreen.
@MainActor
final class WindowState: ObservableObject {
    @Published var isFullscreen: Bool = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isFullscreen = true
        })
        observers.append(nc.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isFullscreen = false
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

@main
struct ClawixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var updater = UpdaterController()
    @StateObject private var windowState = WindowState()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Apply the user-chosen language process-wide BEFORE any view
        // renders. This sets AppleLanguages so the very first
        // String(localized:bundle:) call resolves against the right
        // xcstrings entry, no restart required.
        AppLanguage.bootstrap()
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup(appDisplayName, id: FileMenuActions.mainWindowID) {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.composer)
                .environmentObject(updater)
                .environmentObject(windowState)
                .environment(\.locale, appState.preferredLanguage.locale)
                // Re-mount the view tree on language change. Some
                // SwiftUI Text nodes cache their resolved string until
                // the locale changes; re-keying forces a fresh lookup.
                .id(appState.preferredLanguage.rawValue)
                .preferredColorScheme(.dark)
                .frame(minWidth: mainWindowMinSize.width, minHeight: mainWindowMinSize.height)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.t("Check for Updates…")) {
                    updater.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) {
                FileMenuCommands(appState: appState)
            }
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .importExport) {}
            // Drop SwiftUI's auto "Show/Hide Toolbar, Customize Toolbar"
            // so the View menu only carries our items.
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {
                ViewMenuCommands(appState: appState)
            }
            CommandGroup(after: .windowSize) {
                Divider()
                Button("Pair iPhone…") {
                    openWindow(id: "clawix-pair")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                HelpMenuCommands(appState: appState)
            }
        }

        WindowGroup("Pair iPhone", id: "clawix-pair") {
            PairWindowView()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 360, height: 540)
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.windows.forEach(configure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.forEach(self.configure)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.windows.forEach(saveFrame)
    }

    // Custom inset for the native traffic lights. macOS plants them very
    // close to the top-left corner; we nudge them right and down so they
    // sit comfortably inside the larger titlebar band the app paints.
    private let trafficLightLeftInset: CGFloat = 18
    private let trafficLightTopInset: CGFloat = 14
    private let trafficLightSpacing: CGFloat = 22.5

    private func configure(_ window: NSWindow) {
        window.title = appDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Window drag is opt-in, restricted to the explicit `WindowDragArea`
        // strip painted under the top chrome. Background drag would let the
        // user move the whole window by clicking anywhere in the chat scroll
        // view, which feels broken on macOS.
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = mainWindowMinSize

        restoreFrame(window)
        attachFrameObservers(to: window)
        attachTrafficLightObservers(to: window)
        layoutTrafficLights(window)
    }

    private func layoutTrafficLights(_ window: NSWindow) {
        // In fullscreen the OS hides the buttons, no point repositioning.
        if window.styleMask.contains(.fullScreen) { return }

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var x = trafficLightLeftInset
        for type in buttons {
            guard let btn = window.standardWindowButton(type),
                  let host = btn.superview else { continue }
            let y = host.bounds.height - trafficLightTopInset - btn.frame.height
            let target = CGPoint(x: x, y: y)
            if btn.frame.origin != target {
                var f = btn.frame
                f.origin = target
                btn.frame = f
            }
            x += trafficLightSpacing
        }
    }

    private func attachTrafficLightObservers(to window: NSWindow) {
        let nc = NotificationCenter.default
        // Defer to next runloop so AppKit's own relayout finishes before we
        // re-snap. didExitFullScreen / didBecomeKey occasionally beat us
        // otherwise and the buttons land at the default origin.
        let relayout: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.layoutTrafficLights(window) }
        }
        observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: relayout))
        observers.append(nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main, using: relayout))
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: relayout))
        observers.append(nc.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main, using: relayout))
    }

    private func restoreFrame(_ window: NSWindow) {
        guard let raw = frameDefaults.string(forKey: frameKey) else { return }
        let rect = NSRectFromString(raw)
        guard rect.width >= 100, rect.height >= 100 else { return }
        // Clamp to a visible screen so a saved frame from a disconnected
        // monitor doesn't park the window off-screen.
        guard let visible = visibleFrame(intersecting: rect) else { return }
        let width = min(max(rect.width, mainWindowMinSize.width), visible.width)
        let height = min(max(rect.height, mainWindowMinSize.height), visible.height)
        let clamped = NSRect(
            x: max(visible.minX, min(rect.minX, visible.maxX - width)),
            y: max(visible.minY, min(rect.minY, visible.maxY - height)),
            width: width,
            height: height
        )
        window.setFrame(clamped, display: true, animate: false)
    }

    private func visibleFrame(intersecting rect: NSRect) -> NSRect? {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.visibleFrame.intersects(rect) }) {
            return s.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame
    }

    private func attachFrameObservers(to window: NSWindow) {
        let nc = NotificationCenter.default
        let save: (Notification) -> Void = { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            self?.saveFrame(win)
        }
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save))
        observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: save))
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: save))
    }

    private func saveFrame(_ window: NSWindow) {
        // Skip the brief moment SwiftUI shows a tiny default-sized window
        // before our restoreFrame applies — never persist that.
        guard window.frame.width >= 200, window.frame.height >= 200 else { return }
        frameDefaults.set(NSStringFromRect(window.frame), forKey: frameKey)
    }
}
