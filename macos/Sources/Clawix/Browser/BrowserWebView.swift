import SwiftUI
import WebKit

/// Per-tab controller wrapping a WKWebView. Holds the live navigation state
/// (current URL, title, back/forward/loading flags, favicon) and forwards
/// changes back to AppState so the tab strip and persistence stay in sync.
@MainActor
final class BrowserTabController: NSObject, ObservableObject {
    let id: UUID
    @Published var currentURL: URL
    @Published var title: String
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var faviconURL: URL?
    @Published var pageZoom: Double = 1.0
    @Published var mobileMode: Bool = false
    /// Last error surfaced by `WKNavigationDelegate`. Cleared the moment a
    /// new navigation starts. Drives the "Cannot connect to host" overlay
    /// in BrowserView.
    @Published var lastNavigationError: NavigationError?

    struct NavigationError: Equatable {
        let message: String
        let failedURL: URL?
    }

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Mobile/15E148 Safari/604.1"

    let webView: WKWebView
    private weak var appState: AppState?
    private var observers: [NSKeyValueObservation] = []
    private var bgSampleTimer: Timer?
    private var lastSampledBgRaw: String?
    private var requestedURL: URL?
    private static let blankURL = URL(string: "about:blank")!
    private static let blankPageHTML = """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              html, body {
                margin: 0;
                min-height: 100%;
                background: #000;
              }
            </style>
          </head>
          <body></body>
        </html>
        """

    init(
        id: UUID,
        initialURL: URL,
        appState: AppState,
        initialTitle: String,
        initialFaviconURL: URL?,
        initialPageZoom: Double = 1.0,
        initialMobileMode: Bool = false
    ) {
        self.id = id
        self.currentURL = initialURL
        self.title = initialTitle
        self.faviconURL = initialFaviconURL
        self.pageZoom = initialPageZoom
        self.mobileMode = initialMobileMode
        self.appState = appState

        let config = WKWebViewConfiguration()
        // Pretend to be a recent Safari so most sites serve the desktop layout.
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true
        wv.setValue(false, forKey: "drawsBackground")
        wv.pageZoom = CGFloat(initialPageZoom)
        if initialMobileMode {
            wv.customUserAgent = Self.mobileUserAgent
        }
        self.webView = wv

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        attachObservers()
        startBackgroundSampling()
        load(initialURL)
    }

    deinit {
        teardown()
    }

    func teardown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        bgSampleTimer?.invalidate()
        bgSampleTimer = nil
        webView.loadHTMLString(Self.blankPageHTML, baseURL: Self.blankURL)
    }

    func load(_ url: URL) {
        switch BrowserPermissionPolicy.decision(for: url) {
        case .allow:
            loadApproved(url)
        case .block:
            ToastCenter.shared.show("Website blocked by browser settings", icon: .error)
        case .ask:
            appState?.pendingConfirmation = ConfirmationRequest(
                title: "Open website?",
                body: "Clawix wants to open an external website in the browser.",
                confirmLabel: "Open"
            ) { [weak self] in
                self?.loadApproved(url)
            }
        }
    }

    private func loadApproved(_ url: URL) {
        if Self.isBlankURL(url) {
            requestedURL = nil
            currentURL = Self.blankURL
            title = ""
            lastNavigationError = nil
            appState?.updateBrowserTab(id, url: Self.blankURL, title: "")
            appState?.browserTabsLoading.remove(id)
            appState?.browserPageBackgroundColors[id] = .black
            webView.loadHTMLString(Self.blankPageHTML, baseURL: Self.blankURL)
            return
        }
        requestedURL = url
        currentURL = url
        title = ""
        lastNavigationError = nil
        appState?.updateBrowserTab(id, url: url, title: "")
        webView.load(URLRequest(url: url))
    }

    private static func isBlankURL(_ url: URL) -> Bool {
        url.absoluteString == blankURL.absoluteString
    }

    func loadString(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = Self.normalize(trimmed) {
            load(url)
        }
    }

    func goBack()    { if webView.canGoBack    { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() {
        if lastNavigationError != nil || Self.isBlankURL(webView.url ?? Self.blankURL) {
            load(currentURL)
            return
        }
        webView.reload()
    }
    func hardReload() { webView.reloadFromOrigin() }

    /// Capture the current visible region of the web view as a PNG and
    /// copy it to the system pasteboard. Surfaces a toast on success or
    /// failure so the user gets immediate feedback even though the
    /// pasteboard write is silent.
    func captureToClipboard() {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, error in
            Task { @MainActor in
                guard let image, error == nil else {
                    ToastCenter.shared.show(
                        "Couldn't take screenshot",
                        icon: .error
                    )
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                let ok = pb.writeObjects([image])
                if ok {
                    ToastCenter.shared.show("Screenshot saved to clipboard")
                } else {
                    ToastCenter.shared.show(
                        "Couldn't copy screenshot",
                        icon: .error
                    )
                }
            }
        }
    }

    func zoomIn()    { setZoom(min(pageZoom + 0.1, 5.0)) }
    func zoomOut()   { setZoom(max(pageZoom - 0.1, 0.25)) }
    func resetZoom() { setZoom(1.0) }

    private func setZoom(_ value: Double) {
        let rounded = (value * 100).rounded() / 100
        pageZoom = rounded
        webView.pageZoom = CGFloat(rounded)
        appState?.updateBrowserTab(id, pageZoom: rounded)
    }

    func toggleMobileMode() {
        mobileMode.toggle()
        webView.customUserAgent = mobileMode ? Self.mobileUserAgent : nil
        appState?.updateBrowserTab(id, mobileMode: mobileMode)
        webView.reload()
    }

    func clearCookies(completion: (() -> Void)? = nil) {
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        WKWebsiteDataStore.default()
            .removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                Task { @MainActor in completion?() }
            }
    }

    func clearCache(completion: (() -> Void)? = nil) {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache,
        ]
        WKWebsiteDataStore.default()
            .removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                Task { @MainActor in completion?() }
            }
    }

    /// Polls the bottom-left visible pixel's CSS background colour so the
    /// content column's bottom-trailing rounded-corner cutout can blend
    /// with the live page. Walks up from `elementFromPoint` to find the
    /// nearest opaque ancestor, falling back to body / html background.
    private func startBackgroundSampling() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleBottomLeftBackground() }
        }
        RunLoop.main.add(timer, forMode: .common)
        bgSampleTimer = timer
    }

    private func sampleBottomLeftBackground() {
        let js = """
            (function() {
              if (!document.body) return '';
              function colorAt(x, y) {
                var el = document.elementFromPoint(x, y);
                while (el) {
                  var bg = getComputedStyle(el).backgroundColor;
                  if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') {
                    return bg;
                  }
                  el = el.parentElement;
                }
                var b = getComputedStyle(document.body).backgroundColor;
                if (b && b !== 'rgba(0, 0, 0, 0)' && b !== 'transparent') return b;
                return getComputedStyle(document.documentElement).backgroundColor || '';
              }
              return colorAt(2, Math.max(1, window.innerHeight - 2));
            })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self,
                      let raw = result as? String,
                      !raw.isEmpty,
                      raw != self.lastSampledBgRaw,
                      let color = Self.parseCSSColor(raw)
                else { return }
                self.lastSampledBgRaw = raw
                self.appState?.browserPageBackgroundColors[self.id] = color
            }
        }
    }

    /// Parses CSS `rgb(r, g, b)` / `rgba(r, g, b, a)` strings into a SwiftUI
    /// Color. Returns nil for any other format (named colours, `color()`,
    /// hsl, etc.) so the caller keeps the previous sample instead of
    /// flashing to a wrong colour.
    static func parseCSSColor(_ raw: String) -> Color? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let pattern = #"^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else { return nil }
        func capture(_ index: Int) -> String? {
            let r = match.range(at: index)
            guard r.location != NSNotFound, let rng = Range(r, in: trimmed) else { return nil }
            return String(trimmed[rng])
        }
        guard let rs = capture(1), let gs = capture(2), let bs = capture(3),
              let r = Int(rs), let g = Int(gs), let b = Int(bs) else { return nil }
        let a = Double(capture(4) ?? "1") ?? 1
        return Color(.sRGB,
                     red: Double(r) / 255,
                     green: Double(g) / 255,
                     blue: Double(b) / 255,
                     opacity: a)
    }

    private func attachObservers() {
        observers.append(webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
            let value = wv.canGoBack
            Task { @MainActor in self?.canGoBack = value }
        })
        observers.append(webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
            let value = wv.canGoForward
            Task { @MainActor in self?.canGoForward = value }
        })
        observers.append(webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
            let value = wv.isLoading
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = value
                if value {
                    self.appState?.browserTabsLoading.insert(self.id)
                } else {
                    self.appState?.browserTabsLoading.remove(self.id)
                }
            }
        })
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            guard let url = wv.url else { return }
            Task { @MainActor in
                guard let self else { return }
                if Self.isBlankURL(url),
                   let requestedURL = self.requestedURL,
                   !Self.isBlankURL(requestedURL) {
                    return
                }
                self.currentURL = url
                self.appState?.updateBrowserTab(self.id, url: url)
            }
        })
        observers.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            let value = wv.title ?? ""
            Task { @MainActor in
                guard let self else { return }
                self.title = value
                self.appState?.updateBrowserTab(self.id, title: value)
            }
        })
    }

    /// Sets a Google-served PNG favicon for the current host so the tab pill
    /// and URL bar show something immediately, before the page-level
    /// `<link rel="icon">` lookup runs (and as a guaranteed fallback for
    /// pages that only declare SVG/data-URI icons that AsyncImage can't
    /// render on macOS). Skips the overwrite when the existing favicon
    /// already belongs to this host so a navigation restart (page
    /// refresh, tab reopen, in-site link) doesn't flicker back to the
    /// generic Google globe before the real icon resolves.
    private func setHostFallbackFavicon() {
        guard let host = currentURL.host, !host.isEmpty else { return }
        if let current = faviconURL, Self.faviconBelongs(to: host, url: current) {
            return
        }
        guard let fallback = URL(
            string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        ) else { return }
        faviconURL = fallback
        appState?.updateBrowserTab(id, faviconURL: fallback)
        FaviconCache.shared.prefetch(fallback, priority: .userInitiated)
    }

    private static func faviconBelongs(to host: String, url: URL) -> Bool {
        if let urlHost = url.host {
            if urlHost == host { return true }
            // CDN subdomains (assets.github.com, cdn.x.com, etc.) share
            // the registrable domain. Treat any host whose registrable
            // suffix matches as same-site.
            let target = registrable(host)
            if !target.isEmpty && registrable(urlHost) == target { return true }
        }
        // Google's s2/favicons endpoint identifies the source host via
        // the `domain` query param.
        if url.host == "www.google.com",
           url.path == "/s2/favicons",
           let query = url.query,
           query.contains("domain=\(host)") {
            return true
        }
        return false
    }

    private static func registrable(_ host: String) -> String {
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }

    private func fetchFavicon() {
        // Score every <link rel="*icon*"> by relType (real <link rel="icon">
        // wins over apple-touch-icon, both win over rel="manifest" inferred
        // entries) and by `sizes` proximity to 64px. Skip SVG and data-URI
        // because AsyncImage can't decode them on macOS. Also surface the
        // <link rel="manifest"> href so Swift can fall back to its icons[]
        // when the page declared no <link rel="icon"> at all.
        let js = """
            (function(){
              try {
                var links = document.getElementsByTagName('link');
                var candidates = [];
                var manifestHref = null;
                for (var i = 0; i < links.length; i++) {
                  var rel = (links[i].getAttribute('rel') || '').toLowerCase();
                  if (rel === 'manifest' && links[i].href && !manifestHref) {
                    manifestHref = links[i].href;
                  }
                  if (rel.indexOf('icon') === -1) continue;
                  if (rel.indexOf('mask-icon') !== -1) continue;
                  var href = links[i].href;
                  if (!href) continue;
                  if (href.indexOf('data:') === 0) continue;
                  if (/\\.svg(\\?|#|$)/i.test(href)) continue;
                  var sizes = (links[i].getAttribute('sizes') || '').toLowerCase();
                  var bestSize = 0;
                  var parts = sizes.split(/\\s+/);
                  for (var k = 0; k < parts.length; k++) {
                    var dim = parts[k].split('x')[0];
                    var n = parseInt(dim, 10);
                    if (!isNaN(n) && n > bestSize) bestSize = n;
                  }
                  candidates.push({ rel: rel, href: href, size: bestSize });
                }
                function score(c) {
                  var relScore = 25;
                  if (c.rel === 'icon' || c.rel === 'shortcut icon') {
                    relScore = 100;
                  } else if (c.rel.indexOf('apple-touch-icon') !== -1) {
                    relScore = 50;
                  }
                  var sizeScore = c.size === 0
                    ? 50
                    : Math.max(0, 100 - Math.abs(c.size - 64));
                  return relScore + sizeScore;
                }
                candidates.sort(function(a, b) { return score(b) - score(a); });
                return {
                  icon: candidates.length > 0 ? candidates[0].href : null,
                  manifest: manifestHref
                };
              } catch (e) { return null; }
            })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let dict = result as? [String: Any]
                if let iconStr = dict?["icon"] as? String,
                   let url = URL(string: iconStr) {
                    self.applyFavicon(url)
                    return
                }
                let manifestHref = dict?["manifest"] as? String
                await self.resolveFaviconFallback(manifestHref: manifestHref)
            }
        }
    }

    private func applyFavicon(_ url: URL) {
        faviconURL = url
        appState?.updateBrowserTab(id, faviconURL: url)
        FaviconCache.shared.prefetch(url, priority: .userInitiated)
    }

    /// Last-resort favicon resolution when the page declared no
    /// `<link rel="icon">`: try the manifest.json `icons[]`, then a
    /// raw `/favicon.ico` at the page origin, and only after that
    /// fall through to the Google API host fallback.
    private func resolveFaviconFallback(manifestHref: String?) async {
        let pageOrigin = Self.origin(of: currentURL)
        if let href = manifestHref,
           let manifestURL = Self.resolve(href, against: currentURL),
           let icon = await Self.bestManifestIcon(manifestURL) {
            applyFavicon(icon)
            return
        }
        if let origin = pageOrigin,
           let icoURL = URL(string: origin + "/favicon.ico"),
           await Self.urlReturnsImage(icoURL) {
            applyFavicon(icoURL)
            return
        }
        setHostFallbackFavicon()
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var s = "\(scheme)://\(host)"
        if let port = url.port { s += ":\(port)" }
        return s
    }

    private static func resolve(_ href: String, against base: URL) -> URL? {
        if let direct = URL(string: href), direct.scheme != nil { return direct }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    private static func bestManifestIcon(_ url: URL) async -> URL? {
        var req = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 4.0
        )
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req)
        else { return nil }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = json["icons"] as? [[String: Any]] else { return nil }
        var best: (URL, Int)?
        for icon in icons {
            guard let src = icon["src"] as? String,
                  let resolved = resolve(src, against: url) else { continue }
            if resolved.pathExtension.lowercased() == "svg" { continue }
            let sizes = (icon["sizes"] as? String ?? "").lowercased()
            var bestSize = 0
            for part in sizes.split(separator: " ") {
                let dim = part.split(separator: "x").first.map(String.init) ?? ""
                if let n = Int(dim), n > bestSize { bestSize = n }
            }
            let score = bestSize == 0 ? 50 : 100 - abs(bestSize - 64)
            if best == nil || score > best!.1 {
                best = (resolved, score)
            }
        }
        return best?.0
    }

    private static func urlReturnsImage(_ url: URL) async -> Bool {
        var req = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 4.0
        )
        req.httpMethod = "HEAD"
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (_, response) = try? await URLSession.shared.data(for: req)
        else { return false }
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Best-effort URL parser: accepts "google.com", "https://...", or a search
    /// query (falls back to a Google search).
    static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return url
        }

        let looksLikeHost = trimmed.contains(".") && !trimmed.contains(" ")
        if looksLikeHost,
           let url = URL(string: "https://" + trimmed),
           url.host != nil {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}

extension BrowserTabController: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        Task { @MainActor in
            // Show *something* immediately for the new host while the page
            // is still loading. fetchFavicon() upgrades to the page-declared
            // icon once navigation finishes.
            self.setHostFallbackFavicon()
            self.lastNavigationError = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.fetchFavicon()
            self.sampleBottomLeftBackground()
            self.requestedURL = nil
            self.lastNavigationError = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        let message = nsError.localizedDescription
        Task { @MainActor in
            // -999 ("cancelled") fires when the user types a new URL while a
            // previous load is still resolving. Don't show an error overlay
            // for that, the new navigation has already taken over.
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            self.requestedURL = nil
            if let failingURL {
                self.currentURL = failingURL
                self.appState?.updateBrowserTab(self.id, url: failingURL)
            }
            self.lastNavigationError = NavigationError(
                message: message,
                failedURL: failingURL
            )
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        let message = nsError.localizedDescription
        Task { @MainActor in
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            self.requestedURL = nil
            if let url = webView.url {
                self.currentURL = url
                self.appState?.updateBrowserTab(self.id, url: url)
            }
            self.lastNavigationError = NavigationError(
                message: message,
                failedURL: webView.url
            )
        }
    }
}

extension BrowserTabController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url
        else { return nil }
        Task { @MainActor in
            self.appState?.newBrowserTab(url: url)
        }
        return nil
    }
}

/// Hosts the WKWebView created by the controller. All state mutations go
/// through the controller, so updateNSView is intentionally a no-op.
struct BrowserWebView: NSViewRepresentable {
    let controller: BrowserTabController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// One-shot request emitted by the menu / keyboard shortcut layer, consumed
/// by `BrowserView` and forwarded to the active tab's controller. The
/// `sequence` number makes consecutive identical requests (e.g. Cmd+R twice)
/// distinct from Combine's perspective so `.onChange` fires for both.
struct BrowserCommandRequest: Equatable {
    enum Action: Equatable {
        case newTab
        case reload
        case focusURLBar
        case closeActiveTab
        case zoomIn
        case zoomOut
        case zoomReset
    }
    let action: Action
    let sequence: UInt64
}

/// Tagged focus-the-URL-bar signal. Carries the tab id the request was
/// originally aimed at so a late-arriving handler on another tab ignores it.
struct BrowserFocusURLBarRequest: Equatable {
    let tabId: UUID
    let sequence: UInt64
}

/// Reference-typed cache so SwiftUI can keep one controller alive per tab id
/// without Swift complaining about mutating @State from inside the body.
@MainActor
final class BrowserControllerStore {
    private var controllers: [UUID: BrowserTabController] = [:]

    deinit {
        for controller in controllers.values {
            controller.teardown()
        }
    }

    func controller(for tab: SidebarItem.WebPayload, appState: AppState) -> BrowserTabController {
        if let existing = controllers[tab.id] { return existing }
        let new = BrowserTabController(
            id: tab.id,
            initialURL: tab.url,
            appState: appState,
            initialTitle: tab.title,
            initialFaviconURL: tab.faviconURL,
            initialPageZoom: tab.pageZoom,
            initialMobileMode: tab.mobileMode
        )
        controllers[tab.id] = new
        return new
    }

    func discardOrphans(currentTabIds: Set<UUID>) {
        let stale = controllers.keys.filter { !currentTabIds.contains($0) }
        for id in stale {
            controllers.removeValue(forKey: id)?.teardown()
        }
    }

    func teardownAll() {
        for controller in controllers.values {
            controller.teardown()
        }
        controllers.removeAll()
    }
}
