import SwiftUI
import UIKit
import WebKit

/// iOS canvas wrapper. Same harness as macOS (click / hover / dblclick
/// → contenteditable inline edit) — works untouched on iPad since
/// hover and dblclick map to long-press + double-tap via the
/// pointer interactions WKWebView synthesises on iOS 26.
struct EditorCanvas: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    var selectedSlotId: String?
    var onMessage: (EditorCanvasMessage) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "clawixEditor")
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
                onMessage(.hover(id: payload["id"] as? String))
            case "slot.edit":
                guard let id = payload["id"] as? String, let text = payload["text"] as? String else { return }
                onMessage(.edit(id: id, text: text))
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
