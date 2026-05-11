import SwiftUI
import WebKit

/// SwiftUI wrapper around the `WKWebView` that renders the current
/// editor document. Pipes selection / hover / inline-edit events from
/// the harness JS up to the parent via `onMessage`. Reloads when the
/// HTML payload changes.
struct EditorCanvas: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    var selectedSlotId: String?
    var onMessage: (EditorCanvasMessage) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "clawixEditor")
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if context.coordinator.lastSelection != selectedSlotId {
            context.coordinator.lastSelection = selectedSlotId
            let safeId = selectedSlotId.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? "null"
            webView.evaluateJavaScript("window.clawixSelectSlot && window.clawixSelectSlot(\(safeId));", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onMessage: (EditorCanvasMessage) -> Void
        weak var webView: WKWebView?
        var lastHTML: String = ""
        var lastSelection: String? = nil

        init(onMessage: @escaping (EditorCanvasMessage) -> Void) {
            self.onMessage = onMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "clawixEditor", let payload = message.body as? [String: Any] else { return }
            guard let type = payload["type"] as? String else { return }
            switch type {
            case "slot.click":
                guard let id = payload["id"] as? String else { return }
                let kind = payload["kind"] as? String
                onMessage(.click(id: id, kind: kind))
            case "slot.hover":
                let id = payload["id"] as? String
                onMessage(.hover(id: id))
            case "slot.edit":
                guard let id = payload["id"] as? String, let text = payload["text"] as? String else { return }
                onMessage(.edit(id: id, text: text))
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Prevent the canvas from navigating away (e.g. when a
            // rendered .button is clicked). All href="#" jumps are
            // ignored; only the initial load is allowed.
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

enum EditorCanvasMessage {
    case click(id: String, kind: String?)
    case hover(id: String?)
    case edit(id: String, text: String)
}
