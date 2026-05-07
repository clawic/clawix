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
    @StateObject private var dictation = DictationCoordinator.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        // Apply the user-chosen language process-wide BEFORE any view
        // renders. This sets AppleLanguages so the very first
        // String(localized:bundle:) call resolves against the right
        // xcstrings entry, no restart required.
        AppLanguage.bootstrap()
        // Register Manrope before any SwiftUI view resolves Font.custom("Manrope-…").
        BodyFont.register()
        // One-shot migration of pre-existing UserDefaults values from the
        // old `SidebarOrganizationMode` key into the new `SidebarViewMode`
        // + `ProjectSortMode` keys. Idempotent — does nothing on a fresh
        // install or after the legacy key has been cleared.
        SidebarPrefs.migrateLegacySidebarPrefs()
        let state = AppState()
        // Hand the QuickAsk HUD a back-reference into the live AppState
        // so it can submit prompts into the real chat list and surface
        // streaming replies inline. Done here (instead of from a view's
        // .onAppear) so the panel works the very first time the user
        // hits the global hotkey, even before any window appears.
        QuickAskController.shared.attach(appState: state)
        _appState = StateObject(wrappedValue: state)
        // Dictation hotkey + overlay are wired from
        // `applicationDidFinishLaunching`, NOT here. Calling
        // `addGlobalMonitorForEvents(matching: .flagsChanged)` from
        // App.init() before Input Monitoring is granted freezes event
        // delivery to the app on macOS 26 (Tahoe). The bootstrap path
        // gates the global monitor behind an explicit TCC check.
    }

    var body: some Scene {
        WindowGroup(appDisplayName, id: FileMenuActions.mainWindowID) {
            AppRootView()
                .environmentObject(appState)
                .environmentObject(appState.composer)
                .environmentObject(updater)
                .environmentObject(windowState)
                .environmentObject(dictation)
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

        // Menu bar status item. Lets the user reopen the main window
        // when they've closed it (the app keeps running in the
        // background to host the iPhone bridge), trigger pairing, and
        // quit explicitly. The icon stays visible whenever the app is
        // running, so the user always knows the bridge is alive.
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
        } label: {
            Image(nsImage: ClawixLogoTemplateImage.make(size: 18))
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var micPrefs = MicrophonePreferences.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open \(appDisplayName)") {
            openMainWindow()
        }
        .keyboardShortcut("o")

        Divider()

        Menu(L10n.t("Audio Input")) {
            if micPrefs.devices.isEmpty {
                Text(L10n.t("No input devices"))
            } else {
                ForEach(micPrefs.devices) { device in
                    Button {
                        micPrefs.selectPreferred(uid: device.uid)
                    } label: {
                        if device.uid == micPrefs.activeUID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        }

        Button(L10n.t("Pair iPhone…")) {
            openWindow(id: "clawix-pair")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(L10n.t("Quit \(appDisplayName)")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Reuse the existing main-window NSWindow if SwiftUI is still
    /// holding it (the typical case after the user clicked the close
    /// button); otherwise open a fresh window through the SwiftUI
    /// environment so the WindowGroup re-mounts ContentView.
    private func openMainWindow() {
        for window in NSApp.windows where window.identifier?.rawValue == FileMenuActions.mainWindowID {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        openWindow(id: FileMenuActions.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
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
        // If the previous launch was interrupted by a Sparkle update
        // mid-install, the LaunchAgent was unregistered to release
        // file handles. Restore it now so the user does not have to
        // re-enable "Run bridge in background" after every update.
        BackgroundBridgeService.shared.restoreAfterUpdateIfNeeded()
        // Register the system-wide QuickAsk hotkey. The default combo
        // (⌃⌥⌘K) is set in `QuickAskHotkey.defaultValue`; the user
        // can change it from Settings → QuickAsk.
        QuickAskController.shared.install()
        // Wire the dictation overlay (cheap: only creates an offscreen
        // NSPanel that ignoresMouseEvents, no run-loop side effects)
        // and bootstrap the dictation hotkey monitors. The hotkey
        // bootstrap installs the local monitor unconditionally and
        // gates the global monitor behind Input Monitoring (TCC) so a
        // pre-grant launch doesn't freeze event delivery — the user
        // grants from Settings → Voice to Text where the consent
        // dialog has visible context.
        DictationOverlay.shared.install(coordinator: DictationCoordinator.shared)
        HotkeyManager.shared.bootstrapIfPermitted(coordinator: DictationCoordinator.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.windows.forEach(saveFrame)
    }

    /// Closing the main window does NOT quit the app. The bridge that
    /// serves the paired iPhone lives in this process today; if the
    /// user closing their window also tore down the bridge, the iPhone
    /// would lose its session and have to reconnect on every relaunch.
    /// We keep the process alive in the menu bar (see `MenuBarScene`)
    /// so the iPhone keeps working, and the user reopens the window
    /// from the menu or by clicking the Dock icon.
    ///
    /// `Cmd+Q` still quits the process the standard way, since that
    /// is the user's explicit intent.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// When the app has no visible windows and the user clicks the
    /// Dock icon (or activates from Spotlight), reopen the main
    /// window instead of doing nothing.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            // Re-show the existing main window if it's still around;
            // SwiftUI keeps the WindowGroup instance alive even after
            // the window is closed, so `makeKeyAndOrderFront` is the
            // correct call.
            for window in NSApp.windows where window.identifier?.rawValue == FileMenuActions.mainWindowID {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return true
            }
            // No window object cached. Fall through to AppKit's default
            // behaviour, which will re-instantiate via SwiftUI.
        }
        return true
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
