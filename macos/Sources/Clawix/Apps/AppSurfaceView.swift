import SwiftUI
import WebKit

/// Center-pane surface for one App. Loads `clawix-app://<slug>/` into a
/// `WKWebView` with three custom hooks:
///
///   1. `AppURLSchemeHandler` resolves all in-app paths via the FS-backed
///      AppsStore (no HTTP, no localhost).
///   2. A `WKUserScript` injects a synchronous `window.__clawixContext`
///      with the app id/name + a few user fields so the SDK init has
///      something to expose without a round trip.
///   3. `AppBridgeMessageHandler` is wired under the message name
///      `clawix` so the SDK can call back into native code.
///
/// The chrome is intentionally absent: no URL bar, no back/forward, no
/// tabs. The app should not feel like a browser.
/// External links (target=_blank or any non-clawix-app navigation) are
/// kicked out to `NSWorkspace.shared.open` instead of being followed
/// inside the WKWebView.
struct AppSurfaceView: View {
    let appId: UUID

    @EnvironmentObject var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared
    @State private var reloadToken: Int = 0

    private var record: AppRecord? {
        appsStore.record(forId: appId)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let record {
                AppSurfaceWebView(
                    appId: appId,
                    slug: record.slug,
                    appName: record.name,
                    reloadToken: reloadToken,
                    appsStore: appsStore,
                    appState: appState
                )
                .id("\(record.slug)-\(reloadToken)")

                surfaceToolbar
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            } else {
                missingAppPlaceholder
            }
        }
        .background(Palette.background)
        .onAppear {
            if let record { appsStore.markOpened(record) }
        }
    }

    private var missingAppPlaceholder: some View {
        VStack(spacing: 12) {
            Text("App not found")
                .font(BodyFont.system(size: 18, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("This app may have been removed.")
                .font(BodyFont.system(size: 13.5, wght: 400))
                .foregroundColor(Color(white: 0.65))
            Button("Back to home") {
                appState.currentRoute = .home
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var surfaceToolbar: some View {
        HStack(spacing: 8) {
            Button {
                reloadToken &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Reload app")

            Button {
                appState.currentRoute = .appsHome
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("All apps")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        )
        .foregroundColor(Color(white: 0.92))
    }
}

private struct AppSurfaceWebView: NSViewRepresentable {
    let appId: UUID
    let slug: String
    let appName: String
    let reloadToken: Int
    let appsStore: AppsStore
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let preferences = WKPreferences()
        config.preferences = preferences
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        // 1. URL scheme handler so clawix-app://<slug>/<path> hits the FS store.
        let schemeHandler = AppURLSchemeHandler(
            resolveFile: { [weak appsStore] slug, path in
                appsStore?.readFile(slug: slug, relativePath: path)
            },
            allowsInternet: { [weak appsStore] slug in
                appsStore?.record(forSlug: slug)?.permissions.internet ?? false
            }
        )
        config.setURLSchemeHandler(schemeHandler, forURLScheme: AppURLSchemeHandler.scheme)
        context.coordinator.schemeHandler = schemeHandler

        // 2. Inject the synchronous context + the SDK script.
        let contentController = WKUserContentController()
        let contextScript = WKUserScript(
            source: AppSurfaceView.contextBootstrapJS(appId: appId, slug: slug, appName: appName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        let sdkScript = WKUserScript(
            source: appsStore.sdkScriptJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(contextScript)
        contentController.addUserScript(sdkScript)

        // 3. Bridge handler so window.clawix can post into Swift.
        let bridgeHandler = AppBridgeMessageHandler(slug: slug, appsStore: appsStore, appState: appState)
        contentController.add(bridgeHandler, name: AppBridgeMessageHandler.messageName)
        context.coordinator.bridgeHandler = bridgeHandler

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        bridgeHandler.webView = webView

        if let url = URL(string: "\(AppURLSchemeHandler.scheme)://\(slug)/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The .id() modifier on the parent view rebuilds the entire
        // WKWebView when reloadToken changes; this hook stays as a
        // no-op so SwiftUI doesn't try to reuse the old web context.
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var schemeHandler: AppURLSchemeHandler?
        var bridgeHandler: AppBridgeMessageHandler?

        // Intercept navigation: anything that isn't `clawix-app://` is
        // shipped to the macOS default browser. Inside-scheme navs
        // (the user clicks a link inside their own app) are allowed.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == AppURLSchemeHandler.scheme {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.cancel)
        }

        // target=_blank windows: open in the system browser instead of
        // attempting to instantiate a popup inside the surface.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

extension AppSurfaceView {
    /// Bootstrap script injected before the SDK so `window.__clawixContext`
    /// is available synchronously when the SDK attaches `window.clawix`.
    /// User fields are intentionally minimal: no email, no chat ids.
    static func contextBootstrapJS(appId: UUID, slug: String, appName: String) -> String {
        let payload: [String: Any] = [
            "app": [
                "id": appId.uuidString,
                "slug": slug,
                "name": appName
            ],
            "user": [
                "name": NSFullUserName(),
                "locale": Locale.current.identifier
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "window.__clawixContext = \(json);"
    }
}
