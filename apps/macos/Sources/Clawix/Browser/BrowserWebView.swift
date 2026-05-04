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
        webView.load(URLRequest(url: initialURL))
    }

    deinit {
        observers.forEach { $0.invalidate() }
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

    private func fetchFavicon() {
        let js = """
            (function(){
              const links = Array.from(document.querySelectorAll('link[rel*="icon" i]'));
              const filtered = links.filter(l => l.href && l.href.length > 0);
              if (filtered.length === 0) return null;
              return filtered[filtered.length - 1].href;
            })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let s = result as? String, let url = URL(string: s) {
                    self.faviconURL = url
                    self.appState?.updateBrowserTab(self.id, faviconURL: url)
                } else if let host = self.currentURL.host {
                    let fallback = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
                    self.faviconURL = fallback
                    if let fallback {
                        self.appState?.updateBrowserTab(self.id, faviconURL: fallback)
                    }
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
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.fetchFavicon()
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

    func controller(for tab: BrowserTab, appState: AppState) -> BrowserTabController {
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
