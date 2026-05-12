import SwiftUI
import AppKit
import ClawixEngine
import KeyboardShortcuts

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

enum ClawixAppRole {
    case main
    case tool(ClawixToolRole)

    static var current: ClawixAppRole {
        if let tool = ClawixToolRole.fromBundle() { return .tool(tool) }
        return .main
    }
}

@main
enum ClawixAppEntry {
    static func main() {
        switch ClawixAppRole.current {
        case .main:    ClawixApp.main()
        case .tool:    ClawixToolApp.main()
        }
    }
}

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

struct ClawixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var updater = UpdaterController()
    @StateObject private var windowState = WindowState()
    @StateObject private var dictation = DictationCoordinator.shared
    @StateObject private var vaultManager = VaultManager.shared
    @StateObject private var databaseManager = DatabaseManager()
    @StateObject private var featureFlags = FeatureFlags.shared
    @StateObject private var terminalStore = TerminalSessionStore.shared
    @StateObject private var iotManager: IoTManager
    @StateObject private var remoteToolsRegistry: RemoteToolsRegistry
    @StateObject private var agentStore = AgentStore.shared
    @StateObject private var badgerManager = BadgerManager()
    @Environment(\.openWindow) private var openWindow

    /// True when this binary is running as one of the sidebar-tool mini-app
    /// bundles (a separate `.app` in the Dock, same executable). Resolved
    /// from the `CLXAppRole` Info.plist key the build script injects.
    static var isToolRole: Bool {
        if case .tool = ClawixAppRole.current { return true }
        return false
    }

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
        if !Self.isToolRole {
            // Hand the QuickAsk HUD a back-reference into the live AppState
            // so it can submit prompts into the real chat list and surface
            // streaming replies inline. Done here (instead of from a view's
            // .onAppear) so the panel works the very first time the user
            // hits the global hotkey, even before any window appears.
            QuickAskController.shared.attach(appState: state)
            // Wire the integrated terminal panel's keyboard shortcuts.
            // Toggle (Ctrl+`), new tab, close tab, next/prev tab, split
            // vertical/horizontal. Installed once; the resolver pulls the
            // current chat id from `state` so the shortcuts only act on the
            // chat the user is viewing.
            TerminalShortcutsInstaller.installIfNeeded(
                store: TerminalSessionStore.shared,
                resolveChatId: { [weak state] in
                    guard case let .chat(id) = state?.currentRoute else { return nil }
                    return id
                }
            )
        }
        _appState = StateObject(wrappedValue: state)
        // IoT observable surface: the manager observes ClawJSServiceManager
        // for the .iot service and the registry aggregates the catalog
        // for Codex. Wired before SwiftUI takes over so the registry
        // catches the IoTManager's first publish.
        let iot = IoTManager()
        let registry = RemoteToolsRegistry()
        registry.attach(feature: "iot", tools: iot.$availableTools)
        _iotManager = StateObject(wrappedValue: iot)
        _remoteToolsRegistry = StateObject(wrappedValue: registry)
        if !Self.isToolRole {
            DictationE2ERunner.runIfRequested()
            // Background refresher for OAuth provider accounts (Anthropic
            // Claude.ai, GitHub Copilot). Pauses while the vault is locked;
            // resumes implicitly because each tick checks the vault state
            // before calling refresh.
            TokenRefreshService.shared.start()
        }
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
                .environmentObject(appState.meshStore)
                .environmentObject(updater)
                .environmentObject(windowState)
                .environmentObject(dictation)
                .environmentObject(vaultManager)
                .environmentObject(databaseManager)
                .environmentObject(featureFlags)
                .environmentObject(terminalStore)
                .environmentObject(iotManager)
                .environmentObject(remoteToolsRegistry)
                .environmentObject(agentStore)
                .environmentObject(badgerManager)
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
                Button("Quick Upload to Drive…") {
                    appState.requestDriveQuickUpload()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Open Drive Photos") {
                    appState.currentRoute = .drivePhotos
                }
                .keyboardShortcut("l", modifiers: [.command, .shift, .option])
                Divider()
                DatabaseWorkbenchCommands(appState: appState)
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
                .environmentObject(vaultManager)
                .environmentObject(databaseManager)
                .environmentObject(featureFlags)
        } label: {
            Image(nsImage: ClawixLogoTemplateImage.make(size: 18))
        }
    }
}

struct ClawixToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var windowState = WindowState()
    @StateObject private var dictation = DictationCoordinator.shared
    @StateObject private var vaultManager = VaultManager.shared
    @StateObject private var databaseManager = DatabaseManager()
    @StateObject private var featureFlags = FeatureFlags.shared
    @StateObject private var terminalStore = TerminalSessionStore.shared
    @StateObject private var agentStore = AgentStore.shared

    private let role: ClawixToolRole

    init() {
        AppLanguage.bootstrap()
        BodyFont.register()
        SidebarPrefs.migrateLegacySidebarPrefs()
        _appState = StateObject(wrappedValue: AppState())
        self.role = ClawixToolRole.fromBundle() ?? .tasks
    }

    var body: some Scene {
        WindowGroup(role.windowTitle) {
            role.makeView()
                .environmentObject(appState)
                .environmentObject(appState.composer)
                .environmentObject(appState.meshStore)
                .environmentObject(windowState)
                .environmentObject(dictation)
                .environmentObject(vaultManager)
                .environmentObject(databaseManager)
                .environmentObject(featureFlags)
                .environmentObject(terminalStore)
                .environmentObject(agentStore)
                .environment(\.locale, appState.preferredLanguage.locale)
                .id(appState.preferredLanguage.rawValue)
                .preferredColorScheme(.dark)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultManager
    @EnvironmentObject private var flags: FeatureFlags
    @ObservedObject private var micPrefs = MicrophonePreferences.shared
    @ObservedObject private var screenTools = ScreenToolService.shared
    @ObservedObject private var macUtilities = MacUtilitiesController.shared
    @ObservedObject private var bridge = BackgroundBridgeService.shared
    @Environment(\.openWindow) private var openWindow

    // Status bar dropdown is organized into thematic sections, in fixed order:
    //
    //   1. CONNECT       pairing actions to link Clawix with other devices
    //                    (Pair iPhone…, future: Pair Watch, Re-pair, Unlink…).
    //   2. SCREEN TOOLS  local capture, recording, OCR, pins and history.
    //   3. MAC UTILITIES local macOS window, clipboard, display and settings actions.
    //   4. BRIDGE        runtime status and controls of the background bridge
    //                    daemon (port, LAN/Tailscale IPs, Open Logs, Restart).
    //   5. VOICE TO TEXT audio capture sources and dictation settings
    //                    (Audio Input device picker, future: dictation toggles).
    //   6. SECRETS       vault state and access (Show vault, Lock now, Unlock…).
    //
    // Open Clawix sits above the sections; Quit Clawix sits below. They are
    // app-level meta-actions and stay outside any Section.
    //
    // When adding a new menu item, decide which listed section it belongs
    // to and place it inside that Section. Never add a top-level entry between
    // Open and Quit. If it doesn't fit any section, raise it before introducing
    // another one.
    var body: some View {
        Button {
            openMainWindow()
        } label: {
            Label("Open \(appDisplayName)", systemImage: "macwindow")
        }
        .keyboardShortcut("o")

        Divider()

        Section {
            Menu {
                Button {
                    screenTools.captureArea()
                } label: {
                    Label("Capture Area", systemImage: "crop")
                }
                Button {
                    screenTools.capturePreviousArea()
                } label: {
                    Label("Capture Previous Area", systemImage: "rectangle.dashed")
                }
                Button {
                    screenTools.captureFullscreen()
                } label: {
                    Label("Capture Fullscreen", systemImage: "rectangle.inset.filled")
                }
                Button {
                    screenTools.captureWindow()
                } label: {
                    Label("Capture Window", systemImage: "macwindow")
                }
                Button {
                    screenTools.captureSelfTimer()
                } label: {
                    Label("Self-Timer", systemImage: "timer")
                }
                Divider()
                Button {
                    screenTools.recordScreen()
                } label: {
                    Label("Record Screen", systemImage: "record.circle")
                }
                Button {
                    screenTools.captureText()
                } label: {
                    Label("Capture Text", systemImage: "text.viewfinder")
                }
                Button {
                    macUtilities.perform(.toggleDesktopIcons)
                } label: {
                    Label("Hide Desktop Icons", systemImage: "square.grid.3x3")
                }
                Divider()
                Button {
                    screenTools.chooseAndPinImage()
                } label: {
                    Label("Pin Image…", systemImage: "pin")
                }
                Button {
                    screenTools.pinLastCapture()
                } label: {
                    Label("Pin Last Capture", systemImage: "pin.fill")
                }
                Button {
                    screenTools.showLastCaptureOverlay()
                } label: {
                    Label("Show Last Capture", systemImage: "rectangle.on.rectangle")
                }
                Button {
                    screenTools.copyLastCapture()
                } label: {
                    Label("Copy Last Capture", systemImage: "doc.on.doc")
                }
                Button {
                    screenTools.openLastCapture()
                } label: {
                    Label("Open Last Capture", systemImage: "arrow.up.right.square")
                }
                Button {
                    screenTools.revealLastCapture()
                } label: {
                    Label("Reveal Last Capture", systemImage: "folder")
                }
                Button {
                    screenTools.openCaptureHistory()
                } label: {
                    Label("Capture History…", systemImage: "clock")
                }
                Button {
                    screenTools.revealCaptureFolder()
                } label: {
                    Label("Reveal Capture Folder", systemImage: "folder")
                }
                if !screenTools.overlays.isEmpty {
                    Button {
                        screenTools.closeAllOverlays()
                    } label: {
                        Label("Close All Overlays", systemImage: "xmark")
                    }
                }
                if !screenTools.pins.isEmpty {
                    Button {
                        screenTools.closeAllPins()
                    } label: {
                        Label("Close All Pins", systemImage: "xmark")
                    }
                }
                Divider()
                Button {
                    appState.settingsCategory = .screenTools
                    appState.currentRoute = .settings
                    openMainWindow()
                } label: {
                    Label("Screen Tools Settings…", systemImage: "gearshape")
                }
            } label: {
                Label("Screen Tools", systemImage: "camera.viewfinder")
            }
        } header: {
            Text("Screen Tools")
        }

        MacUtilitiesMenuSection {
            appState.settingsCategory = .macUtilities
            appState.currentRoute = .settings
            openMainWindow()
        }

        DatabaseWorkbenchMenuBarSection(
            appState: appState,
            openMainWindow: openMainWindow
        )

        Section {
            Button {
                openWindow(id: "clawix-pair")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(L10n.t("Pair iPhone…"), systemImage: "iphone")
            }
        } header: {
            Text(L10n.t("Connect"))
        }

        if bridge.isEnabled {
            Section {
                Menu {
                    Text("Running on port \(String(BridgeAgentControl.bridgePort))")
                        .foregroundColor(.secondary)
                    if let lan = PairingService.currentLANIPv4() {
                        Text("LAN: \(lan)")
                            .foregroundColor(.secondary)
                    }
                    if let ts = PairingService.currentTailscaleIPv4() {
                        Text("Tailscale: \(ts)")
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    Button {
                        BridgeAgentControl.openLogs()
                    } label: {
                        Label(L10n.t("Open Bridge Logs"), systemImage: "doc.text")
                    }
                    Button {
                        BridgeAgentControl.restart()
                    } label: {
                        Label(L10n.t("Restart Bridge"), systemImage: "arrow.clockwise")
                    }
                } label: {
                    Label(L10n.t("Bridge"), systemImage: "antenna.radiowaves.left.and.right")
                }
            } header: {
                Text(L10n.t("Bridge"))
            }
        }

        Section {
            Menu {
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
            } label: {
                Label(L10n.t("Audio Input"), systemImage: "mic")
            }
        } header: {
            Text(L10n.t("Voice to text"))
        }

        if flags.isVisible(.secrets) {
            Section {
                Menu {
                    Button {
                        appState.currentRoute = .secretsHome
                        openMainWindow()
                    } label: {
                        Label("Show vault", systemImage: "tray.full")
                    }
                    switch vault.state {
                    case .unlocked:
                        Button {
                            vault.lock()
                        } label: {
                            Label("Lock now", systemImage: "lock.fill")
                        }
                        .keyboardShortcut("l", modifiers: [.command, .shift])
                        Divider()
                        if !vault.openAnomalies.isEmpty {
                            Text("\(vault.openAnomalies.count) open anomal\(vault.openAnomalies.count == 1 ? "y" : "ies")")
                                .foregroundColor(.orange)
                        }
                        if !vault.activeGrants.isEmpty {
                            Text("\(vault.activeGrants.count) active grant\(vault.activeGrants.count == 1 ? "" : "s")")
                        }
                        Text("\(vault.secrets.count) secret\(vault.secrets.count == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                    case .locked:
                        Button {
                            appState.currentRoute = .secretsHome
                            openMainWindow()
                        } label: {
                            Label("Unlock…", systemImage: "lock.open.fill")
                        }
                    case .uninitialized:
                        Button {
                            appState.currentRoute = .secretsHome
                            openMainWindow()
                        } label: {
                            Label("Set up vault…", systemImage: "key.fill")
                        }
                    default:
                        EmptyView()
                    }
                } label: {
                    Label(secretsMenuTitle, systemImage: "lock.shield")
                }
            } header: {
                Text(L10n.t("Secrets"))
            }
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label(L10n.t("Quit \(appDisplayName)"), systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private var secretsMenuTitle: String {
        switch vault.state {
        case .unlocked: return "Secrets · unlocked"
        case .locked, .unlocking: return "Secrets · locked"
        case .uninitialized: return "Secrets · not set up"
        case .loading: return "Secrets · loading"
        case .openFailed: return "Secrets · error"
        }
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

private struct MacUtilitiesMenuSection: View {
    @ObservedObject private var controller = MacUtilitiesController.shared
    @State private var pendingAction: MacUtilityActionID?
    let openSettings: () -> Void

    var body: some View {
        Section {
            Menu {
                ForEach(MacUtilityGroup.allCases) { group in
                    Menu(group.title) {
                        ForEach(MacUtilityActionID.actions(in: group)) { action in
                            Button {
                                request(action)
                            } label: {
                                Label(label(for: action), systemImage: action.systemImage)
                            }
                        }
                    }
                }
                Divider()
                Button(action: openSettings) {
                    Label("Mac Utilities Settings…", systemImage: "gearshape")
                }
            } label: {
                Label("Mac Utilities", systemImage: "bolt")
            }
        } header: {
            Text("Mac Utilities")
        }
        .confirmationDialog(
            pendingAction?.title ?? "Confirm Action",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.title, role: .destructive) {
                controller.perform(action)
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            if action == .clearClipboard {
                Text("This removes all current clipboard contents.")
            } else {
                Text("Run this macOS action now?")
            }
        }
    }

    private func request(_ action: MacUtilityActionID) {
        if action.requiresConfirmation {
            pendingAction = action
        } else {
            controller.perform(action)
        }
    }

    private func label(for action: MacUtilityActionID) -> String {
        if action == .toggleKeepAwake {
            return controller.keepAwakeEnabled ? "Keep Awake Off" : "Keep Awake On"
        }
        return action.title
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wipe any system Keychain entries left over from earlier
        // pre-release builds before they show up in the user's
        // `Keychain Access.app` search for "clawix". The app no longer
        // touches the Keychain at all; this is a one-shot cleanup.
        LegacyKeychainPurge.runOnce()

        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.windows.forEach(configure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.forEach(self.configure)
        }
        // Diagnostics bootstrap. ResourceSampler and MetricKitObserver
        // are always-on (negligible runtime cost). HangDetector is
        // gated to DEBUG by default; CLAWIX_FORCE_HANG_DETECTOR=1
        // opts a release build in. Order is independent — see
        // macos/PERF.md for the playbook.
        ResourceSampler.start()
        MetricKitObserver.shared.install()
        HangDetector.start()
        // The Tasks mini-app needs ClawJSServiceManager.shared.start()
        // because DatabaseManager observes its snapshots and only
        // bootstraps when the supervisor flips .database to .ready /
        // .readyFromDaemon. The supervisor is idempotent: if Clawix.app
        // already spawned the daemons, the second instance discovers
        // them and publishes .readyFromDaemon without spawning a
        // duplicate. If Clawix.app is not running at all, the mini-app
        // will report the database as unavailable, which is the
        // expected fallback.
        Task { @MainActor in
            await ClawJSServiceManager.shared.start()
        }
        // Wire the audio catalog client + run the one-shot legacy
        // migration the first time the supervisor publishes
        // `.audio = .ready`. Idempotent: the marker file in the data
        // dir prevents repeat runs.
        AudioCatalogBootstrap.shared.start()
        // Tasks mini-app stops here. The hooks below either touch
        // shared LaunchAgent state or register a global hotkey, both of
        // which would clash with the full Clawix.app instance running
        // in parallel.
        if ClawixApp.isToolRole {
            return
        }
        // If the previous launch was interrupted by a Sparkle update
        // mid-install, the LaunchAgent was unregistered to release
        // file handles. Restore it now so the user does not have to
        // re-enable "Run bridge in background" after every update.
        BackgroundBridgeService.shared.restoreAfterUpdateIfNeeded()
        // Suppress the standalone `clawix-menubar` icon while the GUI
        // owns its own MenuBarExtra: two near-identical icons next to
        // each other confuse users. The CLI agent is restored on
        // applicationWillTerminate if the bridge daemon is still alive.
        BridgeAgentControl.bootoutMenubarAgent()
        // Register the system-wide QuickAsk hotkey. The default combo
        // (⌃Space) is set in `QuickAskHotkey.defaultValue`; the user
        // can change it from Settings → QuickAsk.
        QuickAskController.shared.install()
        // Wire the dictation overlay (cheap: only creates an offscreen
        // NSPanel that ignoresMouseEvents, no run-loop side effects)
        // and bootstrap the dictation hotkey monitors. Bootstrap is a
        // no-op when no trigger is configured, so a fresh install
        // doesn't touch `addGlobalMonitorForEvents` until the user
        // opts in from Settings → Voice to Text.
        DictationOverlay.shared.install(coordinator: DictationCoordinator.shared)
        HotkeyManager.shared.bootstrap(coordinator: DictationCoordinator.shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.windows.forEach(saveFrame)
        // Tasks mini-app shutdown is just window-frame persistence; the
        // daemons it talks to belong to the full Clawix.app process.
        if ClawixApp.isToolRole {
            return
        }
        // Send SIGHUP to every live integrated-terminal shell so the
        // children get a chance to flush before the process exits.
        // macOS reaps any stragglers via SIGKILL once the parent
        // process is gone, but giving them a clean signal first makes
        // shells like zsh write `.zsh_history` correctly.
        TerminalSessionStore.shared.shutdown()
        // SIGTERM every ClawJS sidecar service before the run loop
        // unwinds. macOS reaps stragglers via SIGKILL once the parent
        // process exits, so this synchronous fan-out is enough.
        ClawJSServiceManager.shared.terminateAllSynchronously()
        // Persist the most recent resource sample so a post-mortem
        // read of "what did the process look like before it shut down"
        // is one `cat` away on the diagnostics directory.
        ResourceSampler.persistLastSample()
        // Hand the menu bar back to the standalone CLI icon if the
        // user installed it AND the daemon is still going to outlive
        // the GUI (the LaunchAgent kept it up across Cmd+Q). If the
        // daemon is also gone, an empty CLI menubar saying "Bridge:
        // not running" would just be noise, so we leave it alone.
        if BridgeAgentControl.isMenubarAgentInstalled(),
           BridgeAgentControl.isBridgeAgentLoaded() {
            BridgeAgentControl.bootstrapMenubarAgent()
        }
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

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !ClawixApp.isToolRole else { return }
        for url in urls where url.scheme?.lowercased() == "clawix" {
            NotificationCenter.default.post(name: .clawixOpenURL, object: url)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.identifier?.rawValue == FileMenuActions.mainWindowID })?
            .makeKeyAndOrderFront(nil)
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
