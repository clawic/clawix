import Foundation
import AppKit
import ApplicationServices
import ClawixEngine

/// Persists Power Mode profiles and publishes the currently-active profile.
@MainActor
final class PowerModeManager: ObservableObject {

    static let shared = PowerModeManager()

    static let enabledKey = "dictation.powerMode.enabled"
    static let configsKey = "dictation.powerMode.configs"
    @Published private(set) var activeBundleId: String?
    @Published private(set) var activeURL: URL?

    @Published private(set) var activeConfig: PowerModeConfig?

    @Published private(set) var configs: [PowerModeConfig] {
        didSet { persist() }
    }

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            resolve()
        }
    }

    private let defaults: UserDefaults
    private var workspaceObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(false, forKey: Self.enabledKey)
        }
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        if let data = defaults.data(forKey: Self.configsKey),
           let decoded = try? JSONDecoder().decode([PowerModeConfig].self, from: data) {
            self.configs = decoded
        } else {
            self.configs = PowerModePresets.presets
            if let data = try? JSONEncoder().encode(PowerModePresets.presets) {
                defaults.set(data, forKey: Self.configsKey)
            }
        }
        installForegroundObserver()
        if let app = NSWorkspace.shared.frontmostApplication {
            self.activeBundleId = app.bundleIdentifier
        }
        resolve()
    }

    deinit {
        if let token = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func addBlank() -> UUID {
        var draft = PowerModeConfig.newBlank()
        if !configs.contains(where: { $0.isDefault }) {
            draft.isDefault = true
        }
        configs.append(draft)
        resolve()
        return draft.id
    }

    func update(_ config: PowerModeConfig) {
        var copy = configs
        guard let idx = copy.firstIndex(where: { $0.id == config.id }) else { return }
        var updated = config
        if updated.isDefault {
            for i in copy.indices where copy[i].id != updated.id {
                copy[i].isDefault = false
            }
        }
        copy[idx] = updated
        configs = copy
        resolve()
    }

    func delete(_ id: UUID) {
        configs.removeAll { $0.id == id }
        resolve()
    }

    func resetToPresets() {
        configs = PowerModePresets.presets
        resolve()
    }

    // MARK: - Resolution

    private func resolve() {
        guard enabled else {
            activeConfig = nil
            return
        }
        let candidates = configs.filter(\.enabled)
        activeURL = currentBrowserURL()

        if let url = activeURL, let host = url.host?.lowercased() {
            if let urlMatch = candidates.first(where: { config in
                config.triggerURLHosts.contains(where: { needle in
                    host.contains(needle.lowercased())
                })
            }) {
                activeConfig = urlMatch
                return
            }
        }

        if let bundle = activeBundleId {
            if let bundleMatch = candidates.first(where: {
                $0.triggerBundleIds.contains(bundle)
            }) {
                activeConfig = bundleMatch
                return
            }
        }

        activeConfig = candidates.first(where: \.isDefault)
    }

    // MARK: - Observer

    private func installForegroundObserver() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self.activeBundleId = app?.bundleIdentifier
                self.resolve()
            }
        }
    }

    /// Probe the foreground app's address-bar URL via Accessibility.
    /// Supported browsers: Safari, Chrome, Arc, Brave, Edge, Vivaldi.
    /// AX exposes `kAXURLAttribute` on the focused-window element for
    /// most webview-shell browsers, but the path differs subtly: in
    /// Safari it's on the window directly, in Chromium-based browsers
    /// it's on the focused web area.
    ///
    /// Returns nil on every failure path (no AX, browser not running,
    /// no URL surfaced) so the caller falls back to bundle matching.
    private func currentBrowserURL() -> URL? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard let bundle = app.bundleIdentifier else { return nil }
        guard Self.browserBundleIds.contains(bundle) else { return nil }

        let ax = AXUIElementCreateApplication(app.processIdentifier)
        // Try focused window first, then the window's "AXWebArea"
        // child for Chromium-based browsers.
        var focusedWindow: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            ax,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard status == .success, let window = focusedWindow else { return nil }
        let windowEl = window as! AXUIElement

        // Direct URL on the window (Safari).
        if let url = readAXURL(from: windowEl) { return url }

        // Walk one level into the focused element of the window —
        // covers Chrome / Arc / Brave / Edge.
        var focused: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            windowEl,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        if focusStatus == .success, let f = focused {
            if let url = readAXURL(from: f as! AXUIElement) { return url }
        }
        return nil
    }

    private func readAXURL(from element: AXUIElement) -> URL? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &ref)
        guard status == .success, let value = ref else { return nil }
        if let url = value as? URL { return url }
        if let str = value as? String { return URL(string: str) }
        return nil
    }

    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi"
    ]

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: Self.configsKey)
        }
    }
}
