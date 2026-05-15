import Foundation
import Network
import ClawixCore
import ClawixEngine

/// Minimal HTTP/1.1 server that serves the embedded Clawix web client
/// (the React SPA built from `clawix/web/`). Sits on a separate port from
/// the WebSocket bridge so it does not collide with NWProtocolWebSocket
/// on the listener stack. The SPA loads from this port, learns the WS
/// port from a small bootstrap snippet injected into index.html, and
/// connects back to the BridgeServer.
///
/// Endpoints:
///   GET /                      → embedded index.html (with bridge URL injected)
///   GET /assets/*              → embedded asset files
///   GET /favicon.svg           → embedded favicon
///   GET /manifest.webmanifest  → embedded manifest
///   GET /pairing/qr.json       → live pairing payload (loopback only)
///   anything else              → 404
///
/// HTTP method support is GET-only; the bridge uses WebSocket for state.
@MainActor
final class WebStaticServer {
    private let httpPort: NWEndpoint.Port
    private let wsPort: UInt16
    private let pairing: PairingService
    private let mesh: RemoteMeshHTTPController?
    private var listener: NWListener?
    private var connections: [BridgeConnection] = []

    init(httpPort: UInt16, wsPort: UInt16, pairing: PairingService, mesh: RemoteMeshHTTPController? = nil) {
        self.httpPort = NWEndpoint.Port(rawValue: httpPort) ?? NWEndpoint.Port(rawValue: 24081)!
        self.wsPort = wsPort
        self.pairing = pairing
        self.mesh = mesh
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: httpPort)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    BridgeLog.write("web-http listener failed: \(err)")
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            BridgeLog.write("web-http listening tcp/\(httpPort.rawValue) wsPort=\(wsPort)")
        } catch {
            BridgeLog.write("web-http listen-failed \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ raw: NWConnection) {
        let isLoopback: Bool
        if case .hostPort(let host, _) = raw.endpoint {
            isLoopback = WebStaticServer.isLoopback(host: host)
        } else {
            isLoopback = false
        }
        let conn = BridgeConnection(
            raw: raw,
            isLoopback: isLoopback,
            pairing: pairing,
            wsPort: wsPort,
            mesh: mesh,
            onTerminated: { [weak self] id in
                Task { @MainActor in
                    self?.connections.removeAll { $0.id == id }
                }
            }
        )
        connections.append(conn)
        conn.start()
    }

    static func isLoopback(host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let a):
            let bytes = a.rawValue
            return bytes.count == 4 && bytes[0] == 127
        case .ipv6(let a):
            // ::1 → 16 bytes, last byte 1, all others 0
            let bytes = a.rawValue
            if bytes.count == 16, bytes.last == 1, bytes.dropLast().allSatisfy({ $0 == 0 }) {
                return true
            }
            return false
        case .name(let s, _):
            return s == "localhost" || s == "::1" || s.hasPrefix("127.")
        @unknown default:
            return false
        }
    }
}

@MainActor
final class BridgeConnection {
    let id = UUID()
    private let raw: NWConnection
    private let isLoopback: Bool
    private let pairing: PairingService
    private let wsPort: UInt16
    private let mesh: RemoteMeshHTTPController?
    private let onTerminated: (UUID) -> Void
    private var buffer = Data()

    init(
        raw: NWConnection,
        isLoopback: Bool,
        pairing: PairingService,
        wsPort: UInt16,
        mesh: RemoteMeshHTTPController?,
        onTerminated: @escaping (UUID) -> Void
    ) {
        self.raw = raw
        self.isLoopback = isLoopback
        self.pairing = pairing
        self.wsPort = wsPort
        self.mesh = mesh
        self.onTerminated = onTerminated
    }

    func start() {
        raw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in self?.readLoop() }
            case .failed, .cancelled:
                Task { @MainActor in self?.terminate() }
            default:
                break
            }
        }
        raw.start(queue: .main)
    }

    func cancel() {
        raw.cancel()
    }

    private func readLoop() {
        raw.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data = data, !data.isEmpty {
                    self.buffer.append(data)
                    if let request = HTTPRequest.parse(&self.buffer) {
                        await self.handle(request)
                        return
                    }
                }
                if isComplete || error != nil {
                    self.terminate()
                    return
                }
                self.readLoop()
            }
        }
    }

    private func handle(_ request: HTTPRequest) async {
        if request.path.hasPrefix(ClawixMeshRoute.prefix), let mesh {
            if let response = await mesh.handle(request, isLoopback: isLoopback) {
                send(response)
                return
            }
        }

        guard request.method == "GET" else {
            send(status: 405, contentType: "text/plain", body: Data("method not allowed".utf8))
            return
        }
        let path = request.path

        // Loopback-only endpoint: live pairing payload.
        if path == "/pairing/qr.json" {
            if !isLoopback {
                send(status: 403, contentType: "text/plain", body: Data("loopback only".utf8))
                return
            }
            let payload = pairing.qrPayload()
            send(status: 200, contentType: "application/json", body: Data(payload.utf8), cacheControl: "no-store")
            return
        }

        // Map path to embedded asset.
        let normalised: String
        if path == "/" || path == "/index.html" {
            normalised = "index.html"
        } else {
            normalised = String(path.drop(while: { $0 == "/" }))
        }

        guard let asset = WebAssets.read(path: normalised) else {
            // SPA fallback: any unknown route serves index.html so client-side
            // routing keeps working when the user hits refresh on a deep link.
            if let fallback = WebAssets.read(path: "index.html") {
                let body = injectBridgeBootstrap(into: fallback)
                send(status: 200, contentType: "text/html; charset=utf-8", body: body, cacheControl: "no-store")
                return
            }
            send(status: 404, contentType: "text/plain", body: Data("not found".utf8))
            return
        }

        let body: Data
        let contentType = mimeType(for: normalised)
        if normalised == "index.html" {
            body = injectBridgeBootstrap(into: asset)
        } else {
            body = asset
        }
        let cache = normalised.hasPrefix("assets/")
            ? "public, max-age=31536000, immutable"
            : "no-store"
        send(status: 200, contentType: contentType, body: body, cacheControl: cache)
    }

    private func injectBridgeBootstrap(into html: Data) -> Data {
        let snippet = """
        <script>window.__CLAWIX_BRIDGE__ = { wsPort: \(wsPort), schemaVersion: \(bridgeSchemaVersion) };</script>
        """
        guard var s = String(data: html, encoding: .utf8) else { return html }
        if let range = s.range(of: "</head>") {
            s.replaceSubrange(range, with: snippet + "</head>")
        } else {
            s = snippet + s
        }
        return Data(s.utf8)
    }

    private func send(
        status: Int,
        contentType: String,
        body: Data,
        cacheControl: String = "no-store"
    ) {
        send(HTTPResponse(status: status, contentType: contentType, body: body, cacheControl: cacheControl))
    }

    private func send(_ response: HTTPResponse) {
        var headers = [
            "Content-Type: \(response.contentType)",
            "Content-Length: \(response.body.count)",
            "Cache-Control: \(response.cacheControl)",
            "Connection: close",
        ]
        // Allow the SPA's /pairing/qr.json to be fetched via Vite dev server proxy.
        headers.append("Access-Control-Allow-Origin: *")
        let head = "HTTP/1.1 \(response.status) \(reason(for: response.status))\r\n" + headers.joined(separator: "\r\n") + "\r\n\r\n"
        var out = Data(head.utf8)
        out.append(response.body)
        raw.send(content: out, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.terminate() }
        })
    }

    private func terminate() {
        raw.cancel()
        onTerminated(id)
    }

    private func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 304: return "Not Modified"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "OK"
        }
    }

    private func mimeType(for path: String) -> String {
        if path.hasSuffix(".html")              { return "text/html; charset=utf-8" }
        if path.hasSuffix(".js") || path.hasSuffix(".mjs") { return "application/javascript; charset=utf-8" }
        if path.hasSuffix(".css")               { return "text/css; charset=utf-8" }
        if path.hasSuffix(".json") || path.hasSuffix(".webmanifest") { return "application/json" }
        if path.hasSuffix(".svg")               { return "image/svg+xml" }
        if path.hasSuffix(".png")               { return "image/png" }
        if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") { return "image/jpeg" }
        if path.hasSuffix(".woff2")             { return "font/woff2" }
        if path.hasSuffix(".woff")              { return "font/woff" }
        if path.hasSuffix(".map")               { return "application/json" }
        if path.hasSuffix(".ico")               { return "image/x-icon" }
        return "application/octet-stream"
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    static func parse(_ buffer: inout Data) -> HTTPRequest? {
        guard let endRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headBytes = buffer.subdata(in: 0..<endRange.lowerBound)
        guard let head = String(data: headBytes, encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let target = parts[1]
        var contentLength = 0
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            if pieces.count == 2, pieces[0].lowercased() == "content-length" {
                contentLength = Int(pieces[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = endRange.upperBound
        guard buffer.count >= bodyStart + contentLength else { return nil }
        let body = contentLength > 0 ? buffer.subdata(in: bodyStart..<(bodyStart + contentLength)) : Data()
        // Drop query string from path; we don't use it.
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        buffer.removeSubrange(0..<(bodyStart + contentLength))
        return HTTPRequest(method: method, path: path, body: body)
    }
}

/// Reads embedded web assets (the `clawix/web/` Vite build output) from the
/// SwiftPM resource bundle. The build pipeline (clawix/macos/scripts/dev.sh
/// and release.sh) runs `pnpm --filter @clawix/web build` and copies the
/// output into `Sources/clawix-bridge/Resources/web-dist/` before invoking
/// `swift build`.
enum WebAssets {
    static func read(path: String) -> Data? {
        let safe = path.split(separator: "/").filter { $0 != ".." && !$0.isEmpty }.joined(separator: "/")
        guard !safe.contains("\0") else { return nil }
        let url = Bundle.module
            .resourceURL?
            .appendingPathComponent("web-dist", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: false)
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }
}
