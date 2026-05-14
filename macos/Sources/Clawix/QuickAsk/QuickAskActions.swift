import AppKit
import UniformTypeIdentifiers

/// Inventory of capture targets the `+` menu surfaces under
/// "Hacer una captura de pantalla". `Screen` enumerates connected
/// displays; `Window` enumerates every visible, regular app window
/// returned by `CGWindowListCopyWindowInfo`.
enum QuickAskCaptureSource {

    struct Screen: Identifiable {
        /// Stable across menu reopens within the same session
        /// (`CGDirectDisplayID`).
        let id: CGDirectDisplayID
        /// "MacBook Pro", "LG UltraFine", etc. when available; falls
        /// back to "Pantalla N" when no friendly name is exposed.
        let name: String
    }

    struct Window: Identifiable {
        let id: CGWindowID
        let appName: String
        let title: String
        var label: String {
            title.isEmpty ? appName : "\(appName) — \(title)"
        }
    }

    /// Every screen the OS reports as connected, in `NSScreen.screens`
    /// order. The `displayID` is read from each `NSScreen`'s
    /// `deviceDescription` so it can be passed to `screencapture -D`.
    static func currentScreens() -> [Screen] {
        NSScreen.screens.enumerated().compactMap { (i, screen) in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            let name = screen.localizedName.isEmpty ? "Pantalla \(i + 1)" : screen.localizedName
            return Screen(id: id, name: name)
        }
    }

    /// On-screen, non-desktop windows owned by other apps. We filter
    /// out very tiny (< 80×80) windows because those are usually
    /// background helpers (menu-bar item windows, transparent
    /// overlays) the user doesn't think of as "windows."
    static func currentWindows() -> [Window] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPid = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { dict -> Window? in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let pid = dict[kCGWindowOwnerPID as String] as? pid_t, pid != myPid else { return nil }
            guard let id = dict[kCGWindowNumber as String] as? CGWindowID else { return nil }
            let app = (dict[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (dict[kCGWindowName as String] as? String) ?? ""
            if let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"],
               (w < 80 || h < 80) {
                return nil
            }
            // Drop entries with no recognisable identity. Without
            // either an app name or a title there's nothing to render
            // in the menu row.
            if app.isEmpty && title.isEmpty { return nil }
            return Window(id: id, appName: app, title: title)
        }
        // Stable sort: by app, then by title, so reopening the menu
        // doesn't shuffle entries the user is hovering.
        .sorted { a, b in
            if a.appName != b.appName { return a.appName < b.appName }
            return a.title < b.title
        }
    }
}

/// Handlers wired to the `+` menu items. All file pickers run
/// modally on the main thread; screencapture runs as a child
/// process so the user sees the standard system capture flash.
@MainActor
enum QuickAskActions {

    // MARK: - File / photo / app pickers

    static func loadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        present(panel) { urls in
            for url in urls {
                QuickAskController.shared.addAttachment(
                    QuickAskAttachment(url: url, kind: .file)
                )
            }
        }
    }

    static func loadPhoto() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        present(panel) { urls in
            for url in urls {
                QuickAskController.shared.addAttachment(
                    QuickAskAttachment(url: url, kind: .file)
                )
            }
        }
    }

    // MARK: - Captures

    /// `screencapture -D <displayID> -t png …`. Hides the QuickAsk
    /// panel briefly so it doesn't end up in its own screenshot, then
    /// re-shows it and stages the PNG as a `screenshot` attachment chip
    /// so the next prompt can refer to the captured image.
    static func captureScreen(_ screen: QuickAskCaptureSource.Screen) {
        QuickAskController.shared.hide()
        let url = captureFileURL(prefix: "screen")
        runScreencapture(args: ["-D", String(screen.id), "-t", "png", url.path]) {
            attachScreenshotAndReshow(url: url)
        }
    }

    /// `screencapture -l <windowID> -o -t png …`. `-o` skips the
    /// drop shadow so the output is the window content alone.
    static func captureWindow(_ window: QuickAskCaptureSource.Window) {
        QuickAskController.shared.hide()
        let url = captureFileURL(prefix: "window")
        runScreencapture(args: ["-l", String(window.id), "-o", "-t", "png", url.path]) {
            attachScreenshotAndReshow(url: url)
        }
    }

    /// `screencapture -i …` is the system's interactive crosshair.
    /// Falls back here when neither a screen nor a window is the
    /// right granularity (the user wants a custom rectangle).
    static func captureInteractive() {
        QuickAskController.shared.hide()
        let url = captureFileURL(prefix: "selection")
        runScreencapture(args: ["-i", "-t", "png", url.path]) {
            // `-i` writes nothing if the user cancels with Esc; in
            // that case we just re-show the panel with no chip.
            if FileManager.default.fileExists(atPath: url.path) {
                attachScreenshotAndReshow(url: url)
            } else {
                QuickAskController.shared.show()
            }
        }
    }

    /// Reveal the AVFoundation camera sheet on top of the QuickAsk
    /// panel. The sheet captures a still frame and stages it as a
    /// `camera` attachment chip; cancellation just dismisses the sheet
    /// with no attachment added.
    static func takePhoto() {
        QuickAskController.shared.requestCameraSheet()
    }

    /// Re-shows the QuickAsk panel and adds the captured PNG as a
    /// chip. Centralised so all three capture variants share the same
    /// post-capture flow without three duplicated bodies.
    private static func attachScreenshotAndReshow(url: URL) {
        QuickAskController.shared.show()
        QuickAskController.shared.addAttachment(
            QuickAskAttachment(url: url, kind: .screenshot)
        )
    }

    // MARK: - Helpers

    /// Path under `~/Library/Caches/Clawix-Captures/` so successive
    /// captures don't collide and `/tmp` doesn't fill up.
    private static func captureFileURL(prefix: String) -> URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.captures, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        return dir.appendingPathComponent("\(prefix)-\(stamp).png")
    }

    private static func runScreencapture(args: [String], completion: @escaping () -> Void) {
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = args
        task.terminationHandler = { _ in
            DispatchQueue.main.async { completion() }
        }
        do {
            try task.run()
        } catch {
            DispatchQueue.main.async { completion() }
        }
    }

    /// `NSOpenPanel` on a `.nonactivatingPanel` won't surface unless
    /// the app is the active one. We bring Clawix forward, run the
    /// modal, then return the resolved URLs.
    private static func present(_ panel: NSOpenPanel, completion: @escaping ([URL]) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { completion([]); return }
            completion(panel.urls)
        }
    }
}
