import Foundation
import ClawixCore

// HTTP wrapper around the local daemon's `/mesh/*` endpoints. The daemon
// (clawix-bridged) listens on loopback at the HTTP port; the Mac app
// talks to it as a regular client. v1 only goes through loopback, so
// no TLS and no auth headers — the daemon validates `isLoopback` itself
// and only honours mesh write/read calls for the local user. Pure
// URLSession + Codable; no shared state.
enum MeshClientError: LocalizedError, Equatable {
    case daemonUnreachable
    case http(status: Int, body: String)
    case decoding(String)
    case workspaceDenied
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .daemonUnreachable:
            return "Local Clawix daemon is not reachable. Start the bridge from Settings → General."
        case .http(let status, let body):
            return "HTTP \(status): \(body)"
        case .decoding(let message):
            return "Failed to decode response: \(message)"
        case .workspaceDenied:
            return "The remote Mac rejected this workspace. Add it to its allowed workspaces or pick another path."
        case .unknown(let message):
            return message
        }
    }
}

/// Loopback-only HTTP client for the daemon's /mesh/* surface. Lives
/// for the lifetime of the app; methods are async and re-entrant.
struct MeshClient {
    /// UserDefaults key the explorer / E2E tests flip when they want
    /// the app to talk to a fake daemon on a different port.
    static let httpPortDefaultsKey = "ClawixMesh.HTTPPort.v1"

    /// Daemon default. Mirrors `CLAWIX_BRIDGED_HTTP_PORT` in
    /// `clawix-bridged/main.swift`. We never poke the heartbeat file
    /// for this; if the user runs the daemon on a non-default port
    /// they set the override below from the menu bar Dev tooling
    /// (out of scope for v1) or via E2E tests.
    static let defaultHTTPPort: UInt16 = 7779

    let baseURL: URL
    private let session: URLSession

    init(host: String = "127.0.0.1", port: UInt16 = MeshClient.resolvedHTTPPort()) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: cfg)
    }

    static func resolvedHTTPPort() -> UInt16 {
        if let override = UserDefaults.standard.object(forKey: httpPortDefaultsKey) as? Int,
           override > 0, override < 65536 {
            return UInt16(override)
        }
        return defaultHTTPPort
    }

    // MARK: - Public surface

    /// GET /mesh/identity — returns this Mac's mesh identity (node id,
    /// display name, endpoints). Always callable; safe even when the
    /// daemon is freshly booted.
    func identity() async throws -> NodeIdentity {
        try await get("/mesh/identity", as: NodeIdentity.self)
    }

    /// GET /mesh/peers — full list of paired Macs. Loopback-only on
    /// the daemon side, so this is the canonical "who is paired"
    /// query.
    func peers() async throws -> [PeerRecord] {
        let payload: PeersOutput = try await get("/mesh/peers")
        return payload.peers
    }

    /// POST /mesh/link — link to another Mac by host + http port +
    /// pairing token. The daemon does the round-trip (fetches the
    /// remote's identity, posts its own back), and on success persists
    /// the remote as a `PeerRecord` on disk.
    func link(host: String, httpPort: Int, token: String, profile: PeerPermissionProfile = .scoped) async throws -> PeerRecord {
        let body = LinkInput(host: host, httpPort: httpPort, bridgePort: nil, token: token, permissionProfile: profile)
        let payload: PeerOutput = try await post("/mesh/link", body: body)
        return payload.peer
    }

    /// GET /mesh/workspaces — local allowlist of folders this Mac will
    /// allow remote peers to execute jobs in. The list is editable from
    /// the Machines settings page (`add(workspace:)`).
    func workspaces() async throws -> [RemoteWorkspace] {
        let payload: WorkspacesOutput = try await get("/mesh/workspaces")
        return payload.workspaces
    }

    /// POST /mesh/workspaces — append (or update) a folder in the
    /// local allowlist. The daemon stores the absolute path; jobs from
    /// peers may target any subpath under it.
    func addWorkspace(path: String, label: String? = nil) async throws -> RemoteWorkspace {
        let body = LocalWorkspaceInput(path: path, label: label)
        let payload: WorkspaceOutput = try await post("/mesh/workspaces", body: body)
        return payload.workspace
    }

    /// POST /mesh/remote-jobs — start an outbound job on a paired
    /// peer. The daemon seals the prompt, signs it, and forwards it to
    /// the peer over the encrypted mesh channel. Returns the initial
    /// `RemoteJob` row (status `queued` or `running`).
    func startRemoteJob(
        peerId: String,
        workspacePath: String,
        prompt: String,
        jobId: String? = nil
    ) async throws -> RemoteJob {
        let body = StartRemoteJobInput(peerId: peerId, workspacePath: workspacePath, prompt: prompt, jobId: jobId)
        let payload: RemoteJobResponse = try await post("/mesh/remote-jobs", body: body)
        return payload.job
    }

    /// GET /mesh/jobs/<id> — current snapshot of a job + the full
    /// event log. Polled from `RemoteJobTracker` to drive the status
    /// UI. Returns nil for the job if the daemon does not know about
    /// it (race with deletion / clean reset).
    func job(id: String) async throws -> JobOutput {
        try await get("/mesh/jobs/\(id)", as: JobOutput.self)
    }

    // MARK: - Wire types
    //
    // These mirror the server's `RemoteMeshHTTPController` shapes 1:1
    // so a tiny daemon refactor that renames a field won't drift
    // silently. Kept private so the rest of the app talks in
    // `ClawixCore` types only.

    private struct LinkInput: Codable {
        var host: String
        var httpPort: Int
        var bridgePort: Int?
        var token: String
        var permissionProfile: PeerPermissionProfile?
    }

    private struct LocalWorkspaceInput: Codable {
        var path: String
        var label: String?
    }

    private struct StartRemoteJobInput: Codable {
        var peerId: String
        var workspacePath: String
        var prompt: String
        var jobId: String?
    }

    private struct PeerOutput: Codable { var peer: PeerRecord }
    private struct PeersOutput: Codable { var peers: [PeerRecord] }
    private struct WorkspaceOutput: Codable { var workspace: RemoteWorkspace }
    private struct WorkspacesOutput: Codable { var workspaces: [RemoteWorkspace] }
    private struct RemoteJobResponse: Codable { var job: RemoteJob }

    struct JobOutput: Codable, Equatable {
        var job: RemoteJob?
        var events: [RemoteJobEvent]
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Self.encoder.encode(body)
        return try await send(req)
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError where Self.isUnreachable(error) {
            throw MeshClientError.daemonUnreachable
        } catch {
            throw MeshClientError.unknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MeshClientError.unknown("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.localizedCaseInsensitiveContains("workspace") &&
                body.localizedCaseInsensitiveContains("denied") {
                throw MeshClientError.workspaceDenied
            }
            throw MeshClientError.http(status: http.statusCode, body: body)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw MeshClientError.decoding(String(describing: error))
        }
    }

    private static func isUnreachable(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .timedOut, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
