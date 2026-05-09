import Foundation
import ClawixCore
import ClawixEngine

@MainActor
final class RemoteMeshHTTPController {
    private let identity: RemoteMeshIdentity
    private let store: RemoteMeshStore
    private weak var host: DaemonEngineHost?
    private let pairing: PairingService
    private let bridgePort: UInt16
    private let httpPort: UInt16

    init(
        identity: RemoteMeshIdentity,
        store: RemoteMeshStore,
        host: DaemonEngineHost,
        pairing: PairingService,
        bridgePort: UInt16,
        httpPort: UInt16
    ) {
        self.identity = identity
        self.store = store
        self.host = host
        self.pairing = pairing
        self.bridgePort = bridgePort
        self.httpPort = httpPort
    }

    func handle(_ request: HTTPRequest, isLoopback: Bool) async -> HTTPResponse? {
        do {
            switch (request.method, request.path) {
            case ("GET", "/mesh/identity"):
                return try json(identityPayload())

            case ("GET", "/mesh/peers") where isLoopback:
                return try json(PeersOutput(peers: store.peers()))

            case ("GET", "/mesh/workspaces") where isLoopback:
                return try json(WorkspacesOutput(workspaces: store.workspaces()))

            case ("GET", let path) where path.hasPrefix("/mesh/jobs/") && isLoopback:
                let jobId = String(path.dropFirst("/mesh/jobs/".count))
                return try json(JobOutput(job: store.job(id: jobId), events: store.events(jobId: jobId)))

            case ("POST", "/mesh/workspaces") where isLoopback:
                let input = try decode(LocalWorkspaceInput.self, from: request.body)
                let path = URL(fileURLWithPath: input.path).standardizedFileURL.path
                let workspace = RemoteWorkspace(path: path, label: input.label ?? URL(fileURLWithPath: path).lastPathComponent)
                store.upsert(workspace: workspace)
                return try json(WorkspaceOutput(workspace: workspace))

            case ("POST", "/mesh/peers") where isLoopback:
                let input = try decode(LocalPeerInput.self, from: request.body)
                var peer = PeerRecord(
                    nodeId: input.identity.nodeId,
                    displayName: input.identity.displayName,
                    signingPublicKey: input.identity.signingPublicKey,
                    agreementPublicKey: input.identity.agreementPublicKey,
                    endpoints: input.identity.endpoints,
                    permissionProfile: input.permissionProfile ?? .scoped,
                    capabilities: input.identity.capabilities,
                    lastSeenAt: Date()
                )
                peer.revokedAt = nil
                store.upsert(peer: peer)
                return try json(PeerOutput(peer: peer))

            case ("POST", "/mesh/link") where isLoopback:
                let input = try decode(LinkInput.self, from: request.body)
                let peer = try await linkPeer(input)
                return try json(PeerOutput(peer: peer))

            case ("POST", "/mesh/remote-jobs") where isLoopback:
                let input = try decode(StartRemoteJobInput.self, from: request.body)
                let result = try await startOutboundJob(input)
                return try json(result)

            case ("POST", "/mesh/pair"):
                let input = try decode(PairInput.self, from: request.body)
                guard pairing.acceptToken(input.token) else {
                    return text(status: 403, "bad pairing token")
                }
                var peer = PeerRecord(
                    nodeId: input.identity.nodeId,
                    displayName: input.identity.displayName,
                    signingPublicKey: input.identity.signingPublicKey,
                    agreementPublicKey: input.identity.agreementPublicKey,
                    endpoints: input.identity.endpoints,
                    permissionProfile: .scoped,
                    capabilities: input.identity.capabilities,
                    lastSeenAt: Date()
                )
                peer.revokedAt = nil
                store.upsert(peer: peer)
                return try json(PairOutput(identity: try identityPayload(), peer: peer))

            case ("POST", "/mesh/jobs"):
                let envelope = try decode(RemoteMeshSignedEnvelope.self, from: request.body)
                let peer = try verifiedPeer(envelope.senderNodeId)
                let input = try identity.open(envelope, from: peer, as: StartJobInput.self)
                guard let host else { return text(status: 503, "host unavailable") }
                let job = try await host.startRemoteJob(
                    jobId: input.jobId,
                    requesterNodeId: peer.nodeId,
                    workspacePath: input.workspacePath,
                    prompt: input.prompt
                )
                return try encrypted(RemoteJobResponse(job: job), to: peer, path: "/mesh/jobs", method: "POST")

            case ("POST", "/mesh/jobs/cancel"):
                let envelope = try decode(RemoteMeshSignedEnvelope.self, from: request.body)
                let peer = try verifiedPeer(envelope.senderNodeId)
                let input = try identity.open(envelope, from: peer, as: CancelJobInput.self)
                await host?.cancelRemoteJob(jobId: input.jobId)
                return try encrypted(OkOutput(ok: true), to: peer, path: "/mesh/jobs/cancel", method: "POST")

            case ("POST", "/mesh/jobs/events"):
                let envelope = try decode(RemoteMeshSignedEnvelope.self, from: request.body)
                let peer = try verifiedPeer(envelope.senderNodeId)
                let input = try identity.open(envelope, from: peer, as: JobEventsInput.self)
                return try encrypted(JobEventsOutput(events: store.events(jobId: input.jobId)), to: peer, path: "/mesh/jobs/events", method: "POST")

            default:
                return nil
            }
        } catch {
            return text(status: 400, String(describing: error))
        }
    }

    private func identityPayload() throws -> NodeIdentity {
        try identity.nodeIdentity(endpoints: currentEndpoints())
    }

    private func currentEndpoints() -> [RemoteEndpoint] {
        var endpoints: [RemoteEndpoint] = []
        if let lan = PairingService.currentLANIPv4() {
            endpoints.append(RemoteEndpoint(kind: "lan", host: lan, bridgePort: Int(bridgePort), httpPort: Int(httpPort)))
        }
        if let tail = PairingService.currentTailscaleIPv4() {
            endpoints.append(RemoteEndpoint(kind: "tailscale", host: tail, bridgePort: Int(bridgePort), httpPort: Int(httpPort)))
        }
        endpoints.append(RemoteEndpoint(kind: "loopback", host: "127.0.0.1", bridgePort: Int(bridgePort), httpPort: Int(httpPort)))
        return endpoints
    }

    private func linkPeer(_ input: LinkInput) async throws -> PeerRecord {
        let identityURL = URL(string: "http://\(input.host):\(input.httpPort)/mesh/identity")!
        let (identityData, _) = try await URLSession.shared.data(from: identityURL)
        let remoteIdentity = try RemoteMeshCodec.decoder.decode(NodeIdentity.self, from: identityData)
        let localIdentity = try identityPayload()
        let pairURL = URL(string: "http://\(input.host):\(input.httpPort)/mesh/pair")!
        var req = URLRequest(url: pairURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try RemoteMeshCodec.encoder.encode(PairInput(token: input.token, identity: localIdentity))
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RemoteMeshError.badRequest("remote pair failed")
        }
        var endpoints = remoteIdentity.endpoints
        endpoints.insert(
            RemoteEndpoint(
                kind: "linked",
                host: input.host,
                bridgePort: input.bridgePort ?? 7778,
                httpPort: input.httpPort
            ),
            at: 0
        )
        let peer = PeerRecord(
            nodeId: remoteIdentity.nodeId,
            displayName: remoteIdentity.displayName,
            signingPublicKey: remoteIdentity.signingPublicKey,
            agreementPublicKey: remoteIdentity.agreementPublicKey,
            endpoints: endpoints,
            permissionProfile: input.permissionProfile ?? .scoped,
            capabilities: remoteIdentity.capabilities,
            lastSeenAt: Date()
        )
        store.upsert(peer: peer)
        return peer
    }

    private func startOutboundJob(_ input: StartRemoteJobInput) async throws -> RemoteJobResponse {
        let peer = try verifiedPeer(input.peerId)
        let payload = StartJobInput(jobId: input.jobId ?? UUID().uuidString, workspacePath: input.workspacePath, prompt: input.prompt)
        let envelope = try identity.seal(payload, for: peer, path: "/mesh/jobs", method: "POST")
        let response: RemoteMeshSignedEnvelope = try await postEncrypted(envelope, to: peer, path: "/mesh/jobs")
        let opened = try identity.open(response, from: peer, as: RemoteJobResponse.self)
        return opened
    }

    private func postEncrypted<T: Decodable>(_ envelope: RemoteMeshSignedEnvelope, to peer: PeerRecord, path: String) async throws -> T {
        guard let endpoint = preferredEndpoint(peer) else { throw RemoteMeshError.peerNotFound }
        let url = URL(string: "http://\(endpoint.host):\(endpoint.httpPort)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try RemoteMeshCodec.encoder.encode(envelope)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RemoteMeshError.badRequest(String(data: data, encoding: .utf8) ?? "remote request failed")
        }
        return try RemoteMeshCodec.decoder.decode(T.self, from: data)
    }

    private func encrypted<T: Encodable>(_ value: T, to peer: PeerRecord, path: String, method: String) throws -> HTTPResponse {
        let envelope = try identity.seal(value, for: peer, path: path, method: method)
        return try json(envelope)
    }

    private func verifiedPeer(_ nodeId: String) throws -> PeerRecord {
        guard let peer = store.peer(nodeId: nodeId) else { throw RemoteMeshError.peerNotFound }
        guard peer.revokedAt == nil else { throw RemoteMeshError.revokedPeer }
        return peer
    }

    private func preferredEndpoint(_ peer: PeerRecord) -> RemoteEndpoint? {
        peer.endpoints.first { $0.kind == "linked" }
            ?? peer.endpoints.first { $0.kind == "tailscale" }
            ?? peer.endpoints.first { $0.kind == "lan" }
            ?? peer.endpoints.first
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try RemoteMeshCodec.decoder.decode(type, from: data)
    }

    private func json<T: Encodable>(_ value: T) throws -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json", body: try RemoteMeshCodec.encoder.encode(value))
    }

    private func text(status: Int, _ value: String) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(value.utf8))
    }

    struct LinkInput: Codable {
        var host: String
        var httpPort: Int
        var bridgePort: Int?
        var token: String
        var permissionProfile: PeerPermissionProfile?
    }

    struct PairInput: Codable {
        var token: String
        var identity: NodeIdentity
    }

    struct LocalPeerInput: Codable {
        var identity: NodeIdentity
        var permissionProfile: PeerPermissionProfile?
    }

    struct LocalWorkspaceInput: Codable {
        var path: String
        var label: String?
    }

    struct StartRemoteJobInput: Codable {
        var peerId: String
        var workspacePath: String
        var prompt: String
        var jobId: String?
    }

    struct StartJobInput: Codable {
        var jobId: String
        var workspacePath: String
        var prompt: String
    }

    struct RemoteJobResponse: Codable {
        var job: RemoteJob
    }

    struct PeersOutput: Codable {
        var peers: [PeerRecord]
    }

    struct PeerOutput: Codable {
        var peer: PeerRecord
    }

    struct WorkspacesOutput: Codable {
        var workspaces: [RemoteWorkspace]
    }

    struct WorkspaceOutput: Codable {
        var workspace: RemoteWorkspace
    }

    struct PairOutput: Codable {
        var identity: NodeIdentity
        var peer: PeerRecord
    }

    struct JobOutput: Codable {
        var job: RemoteJob?
        var events: [RemoteJobEvent]
    }

    struct JobEventsOutput: Codable {
        var events: [RemoteJobEvent]
    }

    struct OkOutput: Codable {
        var ok: Bool
    }

    struct CancelJobInput: Codable {
        var jobId: String
    }

    struct JobEventsInput: Codable {
        var jobId: String
    }
}

struct HTTPResponse {
    var status: Int
    var contentType: String
    var body: Data
    var cacheControl: String = "no-store"
}
