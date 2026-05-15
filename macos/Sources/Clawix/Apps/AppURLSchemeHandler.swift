import Foundation
import WebKit

/// Custom WebKit URL handler that powers `clawix-app://<slug>/<path>`.
/// We picked a custom scheme over a localhost HTTP server for three
/// reasons: every app gets its own origin (`clawix-app://<slug>`) so
/// localStorage/IndexedDB are sandboxed for free; nothing is exposed
/// on `127.0.0.1`; and there is no auth dance to invent (the daemon's
/// Bearer token doesn't apply to in-process WK requests anyway).
///
/// The handler is initialized with a closure to fetch bytes so the
/// `AppsStore` lookup stays on the main actor and we don't ferry a
/// reference to it across the actor boundary on every load.
final class AppURLSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "clawix-app"

    /// Closure resolves a (slug, relativePath) to bytes + MIME, or nil
    /// when the file doesn't exist. Returning nil triggers a 404.
    private let resolveFile: (_ slug: String, _ relativePath: String) -> (data: Data, mimeType: String)?
    /// Closure resolves a slug to its current internet permission, used
    /// to decide whether the CSP `connect-src` allows external hosts.
    private let allowsInternet: (_ slug: String) -> Bool

    init(
        resolveFile: @escaping (String, String) -> (data: Data, mimeType: String)?,
        allowsInternet: @escaping (String) -> Bool
    ) {
        self.resolveFile = resolveFile
        self.allowsInternet = allowsInternet
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == AppURLSchemeHandler.scheme else {
            urlSchemeTask.didFailWithError(NSError(domain: "AppURLSchemeHandler", code: 400))
            return
        }
        let slug = (url.host ?? "").lowercased()
        guard !slug.isEmpty else {
            urlSchemeTask.didFailWithError(NSError(domain: "AppURLSchemeHandler", code: 404, userInfo: [NSLocalizedDescriptionKey: "Missing slug"]))
            return
        }
        let path = url.path
        // Snapshot the closure values on the main actor BEFORE jumping
        // off, then publish bytes back from a background queue. Avoids
        // a hop into the main actor for every byte read.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let allowsNet = DispatchQueue.main.sync { self.allowsInternet(slug) }
            guard let payload = DispatchQueue.main.sync(execute: { self.resolveFile(slug, path) }) else {
                self.respond404(urlSchemeTask: urlSchemeTask, url: url)
                return
            }
            let (data, mimeType) = payload
            let csp = AppURLSchemeHandler.cspHeader(allowsInternet: allowsNet, slug: slug)
            let headers: [String: String] = [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Content-Security-Policy": csp,
                "X-Content-Type-Options": "nosniff",
                "Cache-Control": "no-store",
            ]
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
                urlSchemeTask.didFailWithError(NSError(domain: "AppURLSchemeHandler", code: 500))
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Nothing to cancel: every fetch is one-shot and synchronous on
        // the worker queue. WK still calls stop on navigations away.
    }

    private func respond404(urlSchemeTask: WKURLSchemeTask, url: URL) {
        let body = "404 Not Found".data(using: .utf8) ?? Data()
        let headers = [
            "Content-Type": "text/plain; charset=utf-8",
            "Content-Length": "\(body.count)",
            "X-Content-Type-Options": "nosniff",
        ]
        if let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: headers) {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(body)
            urlSchemeTask.didFinish()
        } else {
            urlSchemeTask.didFailWithError(NSError(domain: "AppURLSchemeHandler", code: 404))
        }
    }

    /// CSP that locks the app to its own scheme by default and only
    /// relaxes `connect-src` to https when the user has granted internet
    /// access. Inline JS is allowed by the v1 app contract because apps
    /// are packaged vanilla documents that boot from their own bundle.
    static func cspHeader(allowsInternet: Bool, slug: String) -> String {
        let connectSrc = allowsInternet
            ? "connect-src 'self' https: wss:"
            : "connect-src 'self'"
        let imgSrc = allowsInternet
            ? "img-src 'self' data: blob: https:"
            : "img-src 'self' data: blob:"
        let pieces = [
            "default-src 'self' \(AppURLSchemeHandler.scheme):",
            "script-src 'self' 'unsafe-inline' \(AppURLSchemeHandler.scheme):",
            "style-src 'self' 'unsafe-inline' \(AppURLSchemeHandler.scheme):",
            "font-src 'self' data: \(AppURLSchemeHandler.scheme):",
            imgSrc,
            connectSrc,
            "frame-ancestors 'none'",
            "base-uri 'self'",
            "form-action 'self'",
        ]
        return pieces.joined(separator: "; ")
    }
}
