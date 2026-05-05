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

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Mobile/15E148 Safari/604.1"

    let webView: WKWebView
    private weak var appState: AppState?
    private var observers: [NSKeyValueObservation] = []
    private var bgSampleTimer: Timer?
    private var lastSampledBgRaw: String?

    init(id: UUID, initialURL: URL, appState: AppState, initialTitle: String) {
        self.id = id
        self.currentURL = initialURL
        self.title = initialTitle
        self.appState = appState

        let config = WKWebViewConfiguration()
        // Pretend to be a recent Safari so most sites serve the desktop layout.
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv

        super.init()

        webView.navigationDelegate = self
        attachObservers()
        startBackgroundSampling()
        webView.load(URLRequest(url: initialURL))
    }

    deinit {
        observers.forEach { $0.invalidate() }
        bgSampleTimer?.invalidate()
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
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
    func reload()    { webView.reload() }
    func hardReload() { webView.reloadFromOrigin() }

    func zoomIn()    { setZoom(min(pageZoom + 0.1, 5.0)) }
    func zoomOut()   { setZoom(max(pageZoom - 0.1, 0.25)) }
    func resetZoom() { setZoom(1.0) }

    private func setZoom(_ value: Double) {
        let rounded = (value * 100).rounded() / 100
        pageZoom = rounded
        webView.pageZoom = CGFloat(rounded)
    }

    func toggleMobileMode() {
        mobileMode.toggle()
        webView.customUserAgent = mobileMode ? Self.mobileUserAgent : nil
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
            Task { @MainActor in self?.isLoading = value }
        })
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            guard let url = wv.url else { return }
            Task { @MainActor in
                guard let self else { return }
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
    /// render on macOS).
    private func setHostFallbackFavicon() {
        guard let host = currentURL.host, !host.isEmpty else { return }
        guard let fallback = URL(
            string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        ) else { return }
        faviconURL = fallback
        appState?.updateBrowserTab(id, faviconURL: fallback)
        // Warm the disk cache so the icon renders the moment SwiftUI asks.
        FaviconCache.shared.prefetch(fallback)
    }

    private func fetchFavicon() {
        // Pick the best raster favicon declared by the page. SVG and
        // data-URI hrefs are skipped because AsyncImage can't decode them
        // on macOS, which is why favicons were silently failing to render.
        // `mask-icon` (Safari pinned-tab silhouette) is also ignored.
        let js = """
            (function(){
              try {
                var links = document.getElementsByTagName('link');
                var candidates = [];
                for (var i = 0; i < links.length; i++) {
                  var rel = (links[i].getAttribute('rel') || '').toLowerCase();
                  if (rel.indexOf('icon') === -1) continue;
                  if (rel.indexOf('mask-icon') !== -1) continue;
                  var href = links[i].href;
                  if (!href) continue;
                  if (href.indexOf('data:') === 0) continue;
                  if (/\\.svg(\\?|#|$)/i.test(href)) continue;
                  candidates.push({ rel: rel, href: href });
                }
                for (var j = 0; j < candidates.length; j++) {
                  if (candidates[j].rel === 'icon' ||
                      candidates[j].rel === 'shortcut icon') {
                    return candidates[j].href;
                  }
                }
                return candidates.length > 0 ? candidates[0].href : null;
              } catch (e) { return null; }
            })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let s = result as? String, let url = URL(string: s) {
                    self.faviconURL = url
                    self.appState?.updateBrowserTab(self.id, faviconURL: url)
                    FaviconCache.shared.prefetch(url)
                } else {
                    self.setHostFallbackFavicon()
                }
            }
        }
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
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.fetchFavicon()
            self.sampleBottomLeftBackground()
        }
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

/// Reference-typed cache so SwiftUI can keep one controller alive per tab id
/// without Swift complaining about mutating @State from inside the body.
@MainActor
final class BrowserControllerStore {
    private var controllers: [UUID: BrowserTabController] = [:]

    func controller(for tab: SidebarItem.WebPayload, appState: AppState) -> BrowserTabController {
        if let existing = controllers[tab.id] { return existing }
        let new = BrowserTabController(
            id: tab.id,
            initialURL: tab.url,
            appState: appState,
            initialTitle: tab.title
        )
        controllers[tab.id] = new
        return new
    }

    func discardOrphans(currentTabIds: Set<UUID>) {
        let stale = controllers.keys.filter { !currentTabIds.contains($0) }
        for id in stale { controllers.removeValue(forKey: id) }
    }
}
