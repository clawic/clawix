import AppKit
import Foundation
import WebKit

/// Native side of the `window.clawix` SDK. WebKit calls into here
/// whenever the app posts a message via
/// `window.webkit.messageHandlers.clawix.postMessage(...)`. The handler
/// resolves the corresponding JS Promise by calling
/// `window.__clawixResolve` / `__clawixReject` back on the WKWebView.
///
/// `WKScriptMessageHandlerWithReply` is available since macOS 11; it
/// would let us reply synchronously, but we keep the indirection via
/// `__clawixResolve` so old AppKit deployments and the existing
/// `decidePolicyFor` plumbing stay simple.
@MainActor
final class AppBridgeMessageHandler: NSObject, WKScriptMessageHandler {
    static let messageName = "clawix"

    weak var webView: WKWebView?
    private let slug: String
    private let appsStore: AppsStore
    private weak var appState: AppState?
    /// In-memory KV cache mirroring the on-disk storage file. Reads are
    /// served from cache; writes flush to disk asynchronously so the JS
    /// promise resolves quickly and the disk lags behind by a few ms.
    private var storageCache: [String: AppBridgeAnyCodable] = [:]
    private var storageLoaded = false

    init(slug: String, appsStore: AppsStore = .shared, appState: AppState?) {
        self.slug = slug
        self.appsStore = appsStore
        self.appState = appState
        super.init()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit dispatches script messages on the main thread, which
        // matches our @MainActor isolation, so we can read the body
        // and dispatch synchronously.
        handle(body: message.body)
    }

    private func handle(body: Any) {
        guard let dict = body as? [String: Any],
              let requestId = dict["requestId"] as? String,
              let op = dict["op"] as? String else {
            return
        }
        let payload = (dict["payload"] as? [String: Any]) ?? [:]
        do {
            switch op {
            case "storage.get":
                let key = (payload["key"] as? String) ?? ""
                ensureStorageLoaded()
                let value = storageCache[key]?.value ?? NSNull()
                resolve(requestId: requestId, value: value)
            case "storage.set":
                let key = (payload["key"] as? String) ?? ""
                let value = payload["value"] ?? NSNull()
                ensureStorageLoaded()
                storageCache[key] = AppBridgeAnyCodable(value)
                persistStorage()
                resolve(requestId: requestId, value: NSNull())
            case "storage.delete":
                let key = (payload["key"] as? String) ?? ""
                ensureStorageLoaded()
                storageCache.removeValue(forKey: key)
                persistStorage()
                resolve(requestId: requestId, value: NSNull())
            case "storage.keys":
                ensureStorageLoaded()
                resolve(requestId: requestId, value: Array(storageCache.keys))
            case "agent.sendMessage":
                let text = (payload["text"] as? String) ?? ""
                try sendMessageToOriginatingChat(text)
                resolve(requestId: requestId, value: NSNull())
            case "agent.callTool":
                // v1: every tool call surfaces a native confirm sheet
                // unless the app has the tool in `permissions.allowedTools`.
                // The actual dispatch to the agent is a v2 concern (it
                // requires a bridge frame to ClawJS); for now we just
                // gate the permission and reject so apps fail loudly
                // until the runtime tools are wired.
                let tool = (payload["tool"] as? String) ?? ""
                try gateToolCall(tool: tool, requestId: requestId)
            case "ui.setTitle":
                let title = (payload["title"] as? String) ?? ""
                applyTitle(title)
                resolve(requestId: requestId, value: NSNull())
            case "ui.setBadge":
                // Badge is informational only in v1; just acknowledge.
                resolve(requestId: requestId, value: NSNull())
            case "ui.openExternal":
                let urlString = (payload["url"] as? String) ?? ""
                if let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                    resolve(requestId: requestId, value: NSNull())
                } else {
                    reject(requestId: requestId, message: "Unsupported URL: \(urlString)")
                }
            default:
                reject(requestId: requestId, message: "Unknown op: \(op)")
            }
        } catch {
            reject(requestId: requestId, message: error.localizedDescription)
        }
    }

    // MARK: - Resolve / reject

    private func resolve(requestId: String, value: Any) {
        guard let webView else { return }
        let payload = encodeForJS(value)
        let js = "window.__clawixResolve && window.__clawixResolve(\(jsonEncoded(requestId)), \(payload));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func reject(requestId: String, message: String) {
        guard let webView else { return }
        let js = "window.__clawixReject && window.__clawixReject(\(jsonEncoded(requestId)), \(jsonEncoded(message)));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Encode a Swift value as a JS literal. Strings + bools + numbers
    /// pass through JSONEncoder; dicts/arrays do too. NSNull becomes
    /// the literal `null`. Anything we can't encode falls back to null.
    private func encodeForJS(_ value: Any) -> String {
        if value is NSNull { return "null" }
        let wrapped = AppBridgeAnyCodable(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(wrapped),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "null"
    }

    private func jsonEncoded(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string], options: [])) ?? Data()
        var s = String(data: data, encoding: .utf8) ?? "[\"\"]"
        // Strip surrounding [ ] to get the encoded scalar.
        if s.hasPrefix("[") { s.removeFirst() }
        if s.hasSuffix("]") { s.removeLast() }
        return s
    }

    // MARK: - Storage

    private var storageURL: URL {
        appsStore.directory(forSlug: slug)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.appStorageFile, isDirectory: false)
    }

    private func ensureStorageLoaded() {
        guard !storageLoaded else { return }
        storageLoaded = true
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL) else { return }
        if let dict = try? JSONDecoder().decode([String: AppBridgeAnyCodable].self, from: data) {
            storageCache = dict
        }
    }

    private func persistStorage() {
        let url = storageURL
        let snapshot = storageCache
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Agent integration (v1: chat send only)

    private func sendMessageToOriginatingChat(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let appState,
              let record = appsStore.record(forSlug: slug),
              let chatId = record.createdByChatId else {
            // No originating chat: drop the message but don't error so
            // the JS Promise still resolves; the SDK is best-effort.
            return
        }
        // Mirror the path "user types into composer in chat X". We
        // don't have a public API on AppState to inject a synthetic
        // user message without a UI roundtrip, so for v1 we just route
        // the agent message through the standard sendPrompt path.
        appState.dispatchAppMessage(text, toChatId: chatId)
    }

    private func gateToolCall(tool: String, requestId: String) throws {
        guard let record = appsStore.record(forSlug: slug) else {
            reject(requestId: requestId, message: "App not found")
            return
        }
        if record.permissions.allowedTools.contains(tool) {
            // Even pre-approved, v1 has no agent-tool dispatch path.
            reject(requestId: requestId, message: "Agent tool dispatch is not available in this build")
            return
        }
        // Sheet-based approval lives in `AppPermissionPrompt`; AppSurfaceView
        // wires it up. The handler just routes the request id back.
        let prompt = AppPermissionPrompt.shared
        prompt.requestToolApproval(
            appName: record.name,
            tool: tool
        ) { [weak self] decision in
            guard let self else { return }
            switch decision {
            case .denied:
                self.reject(requestId: requestId, message: "User denied tool: \(tool)")
            case .once, .always:
                if decision == .always {
                    self.persistAllowedTool(tool: tool)
                }
                self.reject(requestId: requestId, message: "Agent tool dispatch is not available in this build")
            }
        }
    }

    private func persistAllowedTool(tool: String) {
        guard var record = appsStore.record(forSlug: slug) else { return }
        guard !record.permissions.allowedTools.contains(tool) else { return }
        record.permissions.allowedTools.append(tool)
        try? appsStore.update(record)
    }

    private func applyTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var record = appsStore.record(forSlug: slug) else { return }
        if record.name != trimmed {
            record.name = trimmed
            try? appsStore.update(record)
        }
    }
}

// MARK: - AnyCodable helper

/// Heterogeneous JSON-friendly value used to round-trip arbitrary
/// payloads from JS through Swift's Codable encoding. Reads `value`
/// for inspection; encoding goes through JSON via type switching.
struct AppBridgeAnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else if let arr = try? c.decode([AppBridgeAnyCodable].self) {
            self.value = arr.map(\.value)
        } else if let dict = try? c.decode([String: AppBridgeAnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try c.encodeNil()
        case let v as Bool:
            try c.encode(v)
        case let v as Int:
            try c.encode(v)
        case let v as Int64:
            try c.encode(v)
        case let v as Double:
            try c.encode(v)
        case let v as Float:
            try c.encode(Double(v))
        case let v as String:
            try c.encode(v)
        case let v as [Any]:
            try c.encode(v.map(AppBridgeAnyCodable.init))
        case let v as [String: Any]:
            try c.encode(v.mapValues(AppBridgeAnyCodable.init))
        case let v as NSNumber:
            // NSNumber covers most JS primitives that come through
            // WebKit's bridge: distinguish bool by ObjC type.
            if String(cString: v.objCType) == "c" {
                try c.encode(v.boolValue)
            } else if CFGetTypeID(v) == CFBooleanGetTypeID() {
                try c.encode(v.boolValue)
            } else if v.stringValue.contains(".") {
                try c.encode(v.doubleValue)
            } else {
                try c.encode(v.int64Value)
            }
        default:
            try c.encodeNil()
        }
    }
}
