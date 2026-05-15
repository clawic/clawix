import AppKit
import ClawixEngine
import SwiftUI

extension AppState {
    // MARK: - Sidebar (per-chat web tabs and file previews)

    static let sidebarDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    static let leftSidebarOpenKey = "LeftSidebarOpen"
    static let chatSidebarsKey = "ChatSidebars"
    static let globalSidebarKey = "GlobalSidebar"
    static let hostFaviconsKey = "HostFavicons"

    /// UUID of the chat the user is currently viewing, if any. Returns nil
    /// for non-chat routes (home, settings, etc.) so write-time accessors
    /// silently no-op when there is no chat to attach state to.
    var currentChatId: UUID? {
        if case .chat(let id) = currentRoute { return id }
        return nil
    }

    /// Sidebar state for the active chat, or the in-memory global state
    /// when there is no chat selected (home / new conversation, search,
    /// plugins, etc.). The chat dict setter persists and removes empty
    /// entries so it doesn't grow forever; the global setter just writes
    /// through so toggling on home actually opens the panel.
    var currentSidebar: ChatSidebarState {
        get {
            guard let id = currentChatId else { return globalSidebar }
            return chatSidebars[id] ?? .empty
        }
        set {
            guard let id = currentChatId else {
                globalSidebar = newValue
                persistGlobalSidebar()
                return
            }
            if newValue == .empty {
                chatSidebars.removeValue(forKey: id)
            } else {
                chatSidebars[id] = newValue
            }
            persistChatSidebars()
        }
    }

    var isRightSidebarOpen: Bool {
        get { currentSidebar.isOpen }
        set {
            var s = currentSidebar
            s.isOpen = newValue
            currentSidebar = s
        }
    }

    var sidebarItems: [SidebarItem] {
        let items = currentSidebar.items
        if FeatureFlags.shared.isVisible(.simulators) { return items }
        return items.filter { item in
            switch item {
            case .iosSimulator, .androidSimulator: return false
            default: return true
            }
        }
    }

    var activeSidebarItemId: UUID? {
        get { currentSidebar.activeItemId }
        set {
            var s = currentSidebar
            s.activeItemId = newValue
            currentSidebar = s
        }
    }

    var activeSidebarItem: SidebarItem? {
        let item = currentSidebar.activeItem
        if FeatureFlags.shared.isVisible(.simulators) { return item }
        switch item {
        case .iosSimulator, .androidSimulator: return nil
        default: return item
        }
    }

    func removeWebTabsFromCurrentSidebar() {
        var s = currentSidebar
        let activeWasWeb = s.activeItem.map {
            if case .web = $0 { return true }
            return false
        } ?? false
        s.items.removeAll {
            if case .web = $0 { return true }
            return false
        }
        let activeStillExists = s.activeItemId.map { activeID in
            s.items.contains(where: { $0.id == activeID })
        } ?? false
        if activeWasWeb || !activeStillExists {
            s.activeItemId = s.items.first?.id
        }
        if s.items.isEmpty {
            s.isOpen = false
        }
        currentSidebar = s
    }

    /// Whether the browser panel is showing a web tab right now. Drives the
    /// enabled state of browser-scoped menu commands (Cmd+R, Cmd+L, Cmd+W,
    /// Cmd+/-/0) so they fall through to the system when there's nothing
    /// for them to act on.
    var hasActiveWebTab: Bool {
        if case .web = currentSidebar.activeItem { return true }
        return false
    }

    /// Dispatch a browser command toward the active web tab. The view layer
    /// reads `pendingBrowserCommand` and forwards to the right controller.
    /// We bump a sequence so two presses of the same command produce two
    /// distinct values (otherwise Combine wouldn't fire `onChange` for
    /// identical enums).
    func requestBrowserCommand(_ command: BrowserCommandRequest.Action) {
        guard FeatureFlags.shared.isVisible(.browserUsage) else { return }
        Self.browserCommandSequence &+= 1
        pendingBrowserCommand = BrowserCommandRequest(
            action: command,
            sequence: Self.browserCommandSequence
        )
    }

    private static var browserCommandSequence: UInt64 = 0

    /// Convenience for the corner-cutout colour sampling: returns the id
    /// of the active item only when it's a web tab (file previews don't
    /// sample a page colour).
    var activeWebTabId: UUID? {
        if case .web(let p) = activeSidebarItem { return p.id }
        return nil
    }

    /// Open the embedded iOS Simulator as a first-class right-sidebar item.
    func openIOSSimulator(deviceUDID: String? = nil, deviceName: String = "iOS Simulator") {
        guard FeatureFlags.shared.isVisible(.simulators) else { return }
        var s = currentSidebar
        if let existing = s.items.first(where: {
            if case .iosSimulator = $0 { return true }
            return false
        }) {
            s.activeItemId = existing.id
            s.isOpen = true
            currentSidebar = s
            return
        }
        let item = SidebarItem.iosSimulator(.init(
            id: UUID(),
            deviceUDID: deviceUDID,
            deviceName: deviceName
        ))
        s.items.append(item)
        s.activeItemId = item.id
        s.isOpen = true
        currentSidebar = s
    }

    func updateIOSSimulator(_ payload: SidebarItem.IOSSimulatorPayload) {
        var s = currentSidebar
        guard let index = s.items.firstIndex(where: { $0.id == payload.id }) else { return }
        s.items[index] = .iosSimulator(payload)
        s.activeItemId = payload.id
        s.isOpen = true
        currentSidebar = s
    }

    /// Open the embedded Android emulator as a first-class right-sidebar item.
    func openAndroidSimulator(avdName: String? = nil, deviceName: String = "Android Emulator") {
        guard FeatureFlags.shared.isVisible(.simulators) else { return }
        var s = currentSidebar
        if let existing = s.items.first(where: {
            if case .androidSimulator = $0 { return true }
            return false
        }) {
            s.activeItemId = existing.id
            s.isOpen = true
            currentSidebar = s
            return
        }
        let item = SidebarItem.androidSimulator(.init(
            id: UUID(),
            avdName: avdName,
            deviceName: deviceName
        ))
        s.items.append(item)
        s.activeItemId = item.id
        s.isOpen = true
        currentSidebar = s
    }

    func updateAndroidSimulator(_ payload: SidebarItem.AndroidSimulatorPayload) {
        var s = currentSidebar
        guard let index = s.items.firstIndex(where: { $0.id == payload.id }) else { return }
        s.items[index] = .androidSimulator(payload)
        s.activeItemId = payload.id
        s.isOpen = true
        currentSidebar = s
    }

    /// Entry point for "open the browser" actions (toolbar `+ → Browser`,
    /// Cmd+T, deep links). When the panel is already open with web tabs we
    /// always create a fresh tab so the user gets the new-tab behaviour they
    /// expect from any browser. Only the cold case (panel closed, or first
    /// time on this chat) reuses the first existing web tab so reopening the
    /// panel doesn't spawn an extra google.com every time.
    func openBrowser(initialURL: URL = URL(string: "about:blank")!) {
        guard FeatureFlags.shared.isVisible(.browserUsage) else { return }
        var s = currentSidebar
        let hasWebTab = s.items.contains(where: {
            if case .web = $0 { return true } else { return false }
        })
        if s.isOpen && hasWebTab {
            currentSidebar = s
            newBrowserTab(url: initialURL)
            return
        }
        if let firstWeb = s.items.first(where: { if case .web = $0 { return true } else { return false } }) {
            s.activeItemId = firstWeb.id
        } else {
            let item = SidebarItem.web(.init(
                id: UUID(),
                url: initialURL,
                title: "",
                faviconURL: cachedFavicon(forSite: initialURL)
            ))
            s.items.append(item)
            s.activeItemId = item.id
        }
        s.isOpen = true
        currentSidebar = s
    }

    /// Tap target for any inline link inside chat content. Opens the URL in
    /// the active chat's sidebar and brings the panel forward, so the user
    /// never bounces out to the system browser. If the same URL is already
    /// open in an existing tab of this chat, that tab is activated and
    /// reloaded instead of duplicating it. `file://` URLs are routed to
    /// the file viewer instead of the browser tab so a `[abrir markdown]
    /// (/abs/path.md)` link from the assistant lands on the same preview
    /// surface as the trailing `ChangedFileCard` pill.
    func openLinkInBrowser(_ url: URL) {
        if url.isFileURL {
            openFileInSidebar(url.path)
            return
        }
        guard FeatureFlags.shared.isVisible(.browserUsage) else { return }
        var s = currentSidebar
        let key = Self.browserDedupKey(for: url)
        if let existing = s.items.first(where: {
            if case .web(let p) = $0 { return Self.browserDedupKey(for: p.url) == key }
            return false
        }) {
            s.activeItemId = existing.id
            s.isOpen = true
            currentSidebar = s
            pendingReloadTabId = existing.id
            return
        }
        let item = SidebarItem.web(.init(
            id: UUID(),
            url: url,
            title: "",
            faviconURL: cachedFavicon(forSite: url)
        ))
        s.items.append(item)
        s.activeItemId = item.id
        s.isOpen = true
        currentSidebar = s
    }

    /// Loose URL identity for "is this already open in a tab". Drops scheme,
    /// leading `www.`, trailing slash and fragment so a click on
    /// `clawix.com` matches a tab whose live URL is the post-redirect
    /// `https://www.clawix.com/`.
    private static func browserDedupKey(for url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        var path = url.path
        if path.isEmpty { path = "/" }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        let query = url.query.map { "?" + $0 } ?? ""
        return host + path + query
    }

    /// Hides the right column for the active chat without losing its
    /// items, so reopening from the toggle restores whatever was there.
    func closeBrowserPanel() {
        var s = currentSidebar
        s.isOpen = false
        currentSidebar = s
    }

    /// Open an absolute file path in the active chat's sidebar. Used by
    /// `ChangedFileCard`'s primary "Open" tap so the user can preview the
    /// edited file in-app instead of bouncing out to an external editor.
    /// Re-activates an existing file tab for the same path instead of
    /// duplicating it.
    func openFileInSidebar(_ path: String) {
        var s = currentSidebar
        if let existing = s.items.first(where: {
            if case .file(let p) = $0 { return p.path == path }
            return false
        }) {
            s.activeItemId = existing.id
            s.isOpen = true
            currentSidebar = s
            return
        }
        let item = SidebarItem.file(.init(id: UUID(), path: path))
        s.items.append(item)
        s.activeItemId = item.id
        s.isOpen = true
        currentSidebar = s
    }

    @discardableResult
    func newBrowserTab(url: URL = URL(string: "about:blank")!) -> SidebarItem.WebPayload? {
        guard FeatureFlags.shared.isVisible(.browserUsage) else { return nil }
        var s = currentSidebar
        let payload = SidebarItem.WebPayload(
            id: UUID(),
            url: url,
            title: "",
            faviconURL: cachedFavicon(forSite: url)
        )
        s.items.append(.web(payload))
        s.activeItemId = payload.id
        s.isOpen = true
        currentSidebar = s
        return payload
    }

    /// Remove an item (web or file) from the active chat's sidebar. If
    /// the closed tab was the active one, focus snaps to its neighbour.
    /// Closing the last item collapses the panel so the column animates
    /// away instead of leaving a chrome with no body.
    func closeSidebarItem(_ id: UUID) {
        var s = currentSidebar
        guard let idx = s.items.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = s.activeItemId == id
        s.items.remove(at: idx)
        browserPageBackgroundColors.removeValue(forKey: id)
        browserTabsLoading.remove(id)
        if wasActive && !s.items.isEmpty {
            let next = min(idx, s.items.count - 1)
            s.activeItemId = s.items[next].id
        }
        if s.items.isEmpty {
            s.activeItemId = nil
            s.isOpen = false
        }
        currentSidebar = s
    }

    /// Update the live web-tab fields (URL on navigation, title, favicon).
    /// The web view callbacks fire even when the user is on another chat,
    /// so the search scans every chat's sidebar instead of only the
    /// active one.
    func updateBrowserTab(
        _ id: UUID,
        url: URL? = nil,
        title: String? = nil,
        faviconURL: URL? = nil,
        pageZoom: Double? = nil,
        mobileMode: Bool? = nil
    ) {
        for chatId in chatSidebars.keys {
            guard var s = chatSidebars[chatId],
                  let idx = s.items.firstIndex(where: { $0.id == id }),
                  case .web(var payload) = s.items[idx]
            else { continue }
            if let url { payload.url = url }
            if let title { payload.title = title }
            if let faviconURL {
                payload.faviconURL = faviconURL
                recordHostFavicon(faviconURL, for: payload.url)
            }
            if let pageZoom { payload.pageZoom = pageZoom }
            if let mobileMode { payload.mobileMode = mobileMode }
            s.items[idx] = .web(payload)
            chatSidebars[chatId] = s
            persistChatSidebars()
            return
        }
        if let idx = globalSidebar.items.firstIndex(where: { $0.id == id }),
           case .web(var payload) = globalSidebar.items[idx] {
            if let url { payload.url = url }
            if let title { payload.title = title }
            if let faviconURL {
                payload.faviconURL = faviconURL
                recordHostFavicon(faviconURL, for: payload.url)
            }
            if let pageZoom { payload.pageZoom = pageZoom }
            if let mobileMode { payload.mobileMode = mobileMode }
            globalSidebar.items[idx] = .web(payload)
            persistGlobalSidebar()
        }
    }

    /// Drop the chat's sidebar entry (used when a chat is removed
    /// entirely; archiving keeps the entry so it comes back on
    /// unarchive).
    func discardSidebar(forChatId id: UUID) {
        guard chatSidebars[id] != nil else { return }
        chatSidebars.removeValue(forKey: id)
        persistChatSidebars()
    }

    func loadChatSidebars() {
        let defaults = AppState.sidebarDefaults
        if let data = defaults.data(forKey: AppState.chatSidebarsKey),
           let saved = try? JSONDecoder().decode([String: ChatSidebarState].self, from: data) {
            var rebuilt: [UUID: ChatSidebarState] = [:]
            for (key, value) in saved {
                guard let id = UUID(uuidString: key) else { continue }
                rebuilt[id] = value
                for item in value.items {
                    if case .web(let p) = item, let favicon = p.faviconURL {
                        FaviconCache.shared.prefetch(favicon)
                    }
                }
            }
            chatSidebars = rebuilt
        }
        if let data = defaults.data(forKey: AppState.globalSidebarKey),
           let saved = try? JSONDecoder().decode(ChatSidebarState.self, from: data) {
            globalSidebar = saved
            for item in saved.items {
                if case .web(let p) = item, let favicon = p.faviconURL {
                    FaviconCache.shared.prefetch(favicon)
                }
            }
        }
    }

    func persistChatSidebars() {
        let payload = Dictionary(uniqueKeysWithValues:
            chatSidebars.map { ($0.key.uuidString, $0.value) }
        )
        let defaults = AppState.sidebarDefaults
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: AppState.chatSidebarsKey)
        }
    }

    private func persistGlobalSidebar() {
        let defaults = AppState.sidebarDefaults
        if globalSidebar == .empty {
            defaults.removeObject(forKey: AppState.globalSidebarKey)
            return
        }
        if let data = try? JSONEncoder().encode(globalSidebar) {
            defaults.set(data, forKey: AppState.globalSidebarKey)
        }
    }

    /// Returns the best known favicon URL for `siteURL`'s host, or nil
    /// when the user has never visited it. New tabs use this so the
    /// pill renders the real favicon on the first frame instead of the
    /// monogram while WKWebView spins up.
    func cachedFavicon(forSite siteURL: URL) -> URL? {
        guard let key = AppState.hostKey(siteURL) else { return nil }
        return hostFavicons[key]
    }

    /// Records the favicon discovered for the given site URL into the
    /// global host store, preferring real page-declared icons over the
    /// Google s2 fallback when both have been seen for the same host.
    private func recordHostFavicon(_ favicon: URL, for siteURL: URL) {
        guard let key = AppState.hostKey(siteURL) else { return }
        if let existing = hostFavicons[key],
           !AppState.isGoogleS2Favicon(existing),
           AppState.isGoogleS2Favicon(favicon) {
            return
        }
        if hostFavicons[key] == favicon { return }
        hostFavicons[key] = favicon
        persistHostFavicons()
    }

    func loadHostFavicons() {
        let defaults = AppState.sidebarDefaults
        guard let data = defaults.data(forKey: AppState.hostFaviconsKey),
              let saved = try? JSONDecoder().decode([String: URL].self, from: data)
        else { return }
        hostFavicons = saved
        for url in saved.values {
            FaviconCache.shared.prefetch(url, priority: .userInitiated)
        }
    }

    private func persistHostFavicons() {
        let defaults = AppState.sidebarDefaults
        if let data = try? JSONEncoder().encode(hostFavicons) {
            defaults.set(data, forKey: AppState.hostFaviconsKey)
        }
    }

    private static func hostKey(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func isGoogleS2Favicon(_ url: URL) -> Bool {
        url.host == "www.google.com" && url.path == "/s2/favicons"
    }

    /// Publishes the current pairing payload (host, port, bearer, optional
    /// Tailscale host, etc.) to `~/Library/Caches/Clawix-Dev/pairing.json`
    /// so external dev tools (the `Dev` menu-bar agent, scripts) can pre-pair
    /// the iOS Simulator without scanning the on-screen QR. The bearer is
    /// stable across rebuilds, but the LAN IP is not, so this rewrites on
    /// every launch. Silent on failure: this is a developer convenience and
    /// must never block the bridge from coming up.
    static func publishPairingForDevMenu(_ pairing: PairingService) {
        let payload = pairing.qrPayload()
        guard let data = payload.data(using: .utf8) else { return }
        let dir = ((try? ClawixPersistentSurfacePaths.cacheRoot()) ?? FileManager.default.temporaryDirectory).path
        let path = (dir as NSString).appendingPathComponent("pairing.json")
        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            // dev convenience only; ignore.
        }
    }
}
