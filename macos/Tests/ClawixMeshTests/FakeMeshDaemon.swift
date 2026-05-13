import Foundation
import Network
import ClawixCore

/// Tiny in-process HTTP server that mimics the daemon's `/v1/mesh/*`
/// surface for unit tests. Boots on a random local port (so two
/// concurrent test runs don't collide), routes incoming requests via
/// a closure provided by the test, and tears down cleanly.
///
/// Built on `NWListener` to avoid pulling in NIO. The protocol it
/// speaks is HTTP/1.1 — request line + headers + body — and the
/// implementation is intentionally tiny: only enough to exercise
/// MeshClient, not to be a production server.
final class FakeMeshDaemon: @unchecked Sendable {

    typealias Handler = (Request) -> Response

    struct Request {
        let method: String
        let path: String
        let body: Data
    }

    struct Response {
        var status: Int = 200
        var contentType: String = "application/json"
        var body: Data = Data()

        static func json<T: Encodable>(_ value: T) throws -> Response {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return Response(status: 200, contentType: "application/json", body: try encoder.encode(value))
        }

        static func text(_ message: String, status: Int = 400) -> Response {
            Response(status: status, contentType: "text/plain; charset=utf-8", body: Data(message.utf8))
        }
    }

    private let queue = DispatchQueue(label: "fake-mesh-daemon")
    private let listener: NWListener
    var port: UInt16
    var handler: Handler

    init(handler: @escaping Handler) throws {
        self.handler = handler
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        let semaphore = DispatchSemaphore(value: 0)
        let portBox = AtomicPort()
        listener.stateUpdateHandler = { state in
            if case .ready = state, let p = listener.port?.rawValue {
                portBox.set(p)
                semaphore.signal()
            }
        }
        self.port = 0
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            throw NSError(domain: "FakeMeshDaemon", code: 1, userInfo: [NSLocalizedDescriptionKey: "listener did not bind"])
        }
        self.port = portBox.get()
    }

    func stop() {
        listener.cancel()
    }

    deinit {
        listener.cancel()
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, accumulated: Data())
    }

    private func receive(_ conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                conn.cancel()
                _ = error
                return
            }
            var combined = accumulated
            if let data = data { combined.append(data) }
            if let request = self.parse(combined) {
                let response = self.handler(request)
                self.write(conn: conn, response: response)
            } else if isComplete {
                conn.cancel()
            } else {
                self.receive(conn, accumulated: combined)
            }
        }
    }

    private func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.split(separator: "\r\n").map(String.init)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])
        var contentLength = 0
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "0"
                contentLength = Int(value) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        let bodyAvailable = data.count - bodyStart
        if bodyAvailable < contentLength {
            return nil
        }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return Request(method: method, path: path, body: body)
    }

    private func write(conn: NWConnection, response: Response) {
        let statusText = Self.statusText(response.status)
        var head = "HTTP/1.1 \(response.status) \(statusText)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(response.body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }
}

// Tiny holder used during init so we can capture the port from the
// NWListener state callback without mutating self before init
// finishes. NSLock + UInt16 is overkill but keeps the listener dance
// simple.
private final class AtomicPort: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt16 = 0
    func set(_ v: UInt16) { lock.lock(); value = v; lock.unlock() }
    func get() -> UInt16 { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - Sample data builders shared across tests

enum MeshTestFixtures {
    static func nodeIdentity(displayName: String = "This Mac") -> NodeIdentity {
        NodeIdentity(
            nodeId: "node-this",
            displayName: displayName,
            signingPublicKey: "AAA=",
            agreementPublicKey: "BBB=",
            endpoints: [
                RemoteEndpoint(kind: "lan", host: "192.168.1.10", bridgePort: 24080, httpPort: 24081),
                RemoteEndpoint(kind: "loopback", host: "127.0.0.1", bridgePort: 24080, httpPort: 24081)
            ],
            capabilities: ["remote.job"]
        )
    }

    static func peer(nodeId: String = "node-peer", displayName: String = "Other Mac", revoked: Bool = false) -> PeerRecord {
        PeerRecord(
            nodeId: nodeId,
            displayName: displayName,
            signingPublicKey: "PEER=",
            agreementPublicKey: "PEER2=",
            endpoints: [RemoteEndpoint(kind: "linked", host: "10.0.0.5", bridgePort: 24080, httpPort: 24081)],
            permissionProfile: .scoped,
            capabilities: ["remote.job"],
            lastSeenAt: Date(),
            revokedAt: revoked ? Date() : nil
        )
    }

    static func workspace(path: String = "/Users/me/Projects/foo", label: String = "foo") -> RemoteWorkspace {
        RemoteWorkspace(path: path, label: label)
    }
}
