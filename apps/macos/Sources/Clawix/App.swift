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

@main
struct ClawixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var updater = UpdaterController()
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

    private func configure(_ window: NSWindow) {
        window.title = appDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = mainWindowMinSize
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        restoreFrame(window)
        attachFrameObservers(to: window)
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
