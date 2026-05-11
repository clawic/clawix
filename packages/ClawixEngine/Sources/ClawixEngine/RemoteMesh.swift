import Foundation
import ClawixCore
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum RemoteMeshError: Error, LocalizedError {
    case cryptoUnavailable
    case peerNotFound
    case revokedPeer
    case invalidSignature
    case decryptFailed
    case workspaceDenied
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case .cryptoUnavailable: return "Remote mesh crypto is unavailable on this platform"
        case .peerNotFound: return "Peer not found"
        case .revokedPeer: return "Peer has been revoked"
        case .invalidSignature: return "Invalid peer signature"
        case .decryptFailed: return "Encrypted payload could not be opened"
        case .workspaceDenied: return "Workspace is not allowed on this host"
        case .badRequest(let message): return message
        }
    }
}

public struct RemoteMeshSealedPayload: Codable, Sendable {
    public let nonce: String
    public let ciphertext: String
    public let tag: String
}

public struct RemoteMeshSignedEnvelope: Codable, Sendable {
    public let senderNodeId: String
    public let timestamp: String
    public let path: String
    public let method: String
    public let payload: RemoteMeshSealedPayload
    public let signature: String
}

public final class RemoteMeshStore: @unchecked Sendable {
    public let root: URL
    private let peersURL: URL
    private let workspacesURL: URL
    private let jobsURL: URL
    private let eventsURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL? = nil) {
        let base = root ?? Self.defaultRoot()
        self.root = base
        self.peersURL = base.appendingPathComponent("peers.json")
        self.workspacesURL = base.appendingPathComponent("workspaces.json")
        self.jobsURL = base.appendingPathComponent("jobs.json")
        self.eventsURL = base.appendingPathComponent("job-events.json")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAWIX_MESH_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".clawix/mesh", isDirectory: true)
    }

    public func peers() -> [PeerRecord] {
        lockedRead([PeerRecord].self, from: peersURL) ?? []
    }

    public func peer(nodeId: String) -> PeerRecord? {
        peers().first { $0.nodeId == nodeId }
    }

    public func upsert(peer: PeerRecord) {
        lock.withLock {
            var all = readUnlocked([PeerRecord].self, from: peersURL) ?? []
            if let idx = all.firstIndex(where: { $0.nodeId == peer.nodeId }) {
                all[idx] = peer
            } else {
                all.append(peer)
            }
            writeUnlocked(all, to: peersURL)
        }
    }

    public func revokePeer(nodeId: String) {
        lock.withLock {
            var all = readUnlocked([PeerRecord].self, from: peersURL) ?? []
            if let idx = all.firstIndex(where: { $0.nodeId == nodeId }) {
                all[idx].revokedAt = Date()
                writeUnlocked(all, to: peersURL)
            }
        }
    }

    public func workspaces() -> [RemoteWorkspace] {
        lockedRead([RemoteWorkspace].self, from: workspacesURL) ?? []
    }

    public func upsert(workspace: RemoteWorkspace) {
        lock.withLock {
            var all = readUnlocked([RemoteWorkspace].self, from: workspacesURL) ?? []
            if let idx = all.firstIndex(where: { $0.path == workspace.path }) {
                all[idx] = workspace
            } else {
                all.append(workspace)
            }
            writeUnlocked(all, to: workspacesURL)
        }
    }

    public func allowsWorkspace(_ path: String) -> Bool {
        let normalised = URL(fileURLWithPath: path).standardizedFileURL.path
        return workspaces().contains { workspace in
            let allowed = URL(fileURLWithPath: workspace.path).standardizedFileURL.path
            return normalised == allowed || normalised.hasPrefix(allowed + "/")
        }
    }

    public func jobs() -> [RemoteJob] {
        lockedRead([RemoteJob].self, from: jobsURL) ?? []
    }

    public func job(id: String) -> RemoteJob? {
        jobs().first { $0.id == id }
    }

    public func upsert(job: RemoteJob) {
        lock.withLock {
            var all = readUnlocked([RemoteJob].self, from: jobsURL) ?? []
            if let idx = all.firstIndex(where: { $0.id == job.id }) {
                all[idx] = job
            } else {
                all.append(job)
            }
            writeUnlocked(all, to: jobsURL)
        }
    }

    public func events(jobId: String) -> [RemoteJobEvent] {
        (lockedRead([RemoteJobEvent].self, from: eventsURL) ?? []).filter { $0.jobId == jobId }
    }

    public func append(event: RemoteJobEvent) {
        lock.withLock {
            var all = readUnlocked([RemoteJobEvent].self, from: eventsURL) ?? []
            all.append(event)
            writeUnlocked(all, to: eventsURL)
        }
    }

    private func lockedRead<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        lock.withLock { readUnlocked(type, from: url) }
    }

    private func readUnlocked<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func writeUnlocked<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public final class RemoteMeshIdentity: @unchecked Sendable {
    public let root: URL
    private let identityURL: URL
    private let displayName: String

    public init(root: URL? = nil, displayName: String? = nil) {
        let base = root ?? RemoteMeshStore.defaultRoot()
        self.root = base
        self.identityURL = base.appendingPathComponent("identity.json")
        self.displayName = displayName ?? HostIdentity.localizedName ?? "Mac"
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func nodeIdentity(endpoints: [RemoteEndpoint]) throws -> NodeIdentity {
        let material = try loadOrCreate()
        return NodeIdentity(
            nodeId: material.nodeId,
            displayName: displayName,
            signingPublicKey: material.signingPublicKey,
            agreementPublicKey: material.agreementPublicKey,
            endpoints: endpoints,
            capabilities: RemoteMeshCapabilities.current
        )
    }

    public func sign(_ data: Data) throws -> String {
        #if canImport(CryptoKit)
        let material = try loadOrCreate()
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: material.signingPrivateKey) ?? Data())
        return try privateKey.signature(for: data).base64EncodedString()
        #else
        throw RemoteMeshError.cryptoUnavailable
        #endif
    }

    public func seal<T: Encodable>(_ value: T, for peer: PeerRecord, path: String, method: String) throws -> RemoteMeshSignedEnvelope {
        #if canImport(CryptoKit)
        let material = try loadOrCreate()
        let body = try RemoteMeshCodec.encoder.encode(value)
        let privateAgreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: material.agreementPrivateKey) ?? Data())
        let peerPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: peer.agreementPublicKey) ?? Data())
        let secret = try privateAgreement.sharedSecretFromKeyAgreement(with: peerPublic)
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("clawix-remote-mesh-v1".utf8),
            sharedInfo: Data((material.nodeId + ":" + peer.nodeId).utf8),
            outputByteCount: 32
        )
        let sealed = try ChaChaPoly.seal(body, using: key)
        let combined = sealed.combined
        let nonce = combined.prefix(12)
        let ciphertext = combined.dropFirst(12).dropLast(16)
        let tag = combined.suffix(16)
        let timestamp = RemoteMeshCodec.iso8601(Date())
        let payload = RemoteMeshSealedPayload(
            nonce: Data(nonce).base64EncodedString(),
            ciphertext: Data(ciphertext).base64EncodedString(),
            tag: Data(tag).base64EncodedString()
        )
        let signingBytes = RemoteMeshCodec.signingBytes(
            senderNodeId: material.nodeId,
            timestamp: timestamp,
            method: method,
            path: path,
            payload: payload
        )
        let signature = try sign(signingBytes)
        return RemoteMeshSignedEnvelope(
            senderNodeId: material.nodeId,
            timestamp: timestamp,
            path: path,
            method: method,
            payload: payload,
            signature: signature
        )
        #else
        throw RemoteMeshError.cryptoUnavailable
        #endif
    }

    public func open<T: Decodable>(_ envelope: RemoteMeshSignedEnvelope, from peer: PeerRecord, as type: T.Type) throws -> T {
        #if canImport(CryptoKit)
        guard peer.revokedAt == nil else { throw RemoteMeshError.revokedPeer }
        let signingBytes = RemoteMeshCodec.signingBytes(
            senderNodeId: envelope.senderNodeId,
            timestamp: envelope.timestamp,
            method: envelope.method,
            path: envelope.path,
            payload: envelope.payload
        )
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: peer.signingPublicKey) ?? Data())
        let signature = Data(base64Encoded: envelope.signature) ?? Data()
        guard publicKey.isValidSignature(signature, for: signingBytes) else {
            throw RemoteMeshError.invalidSignature
        }
        let material = try loadOrCreate()
        let privateAgreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: material.agreementPrivateKey) ?? Data())
        let peerPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: peer.agreementPublicKey) ?? Data())
        let secret = try privateAgreement.sharedSecretFromKeyAgreement(with: peerPublic)
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("clawix-remote-mesh-v1".utf8),
            sharedInfo: Data((peer.nodeId + ":" + material.nodeId).utf8),
            outputByteCount: 32
        )
        guard let nonce = Data(base64Encoded: envelope.payload.nonce),
              let ciphertext = Data(base64Encoded: envelope.payload.ciphertext),
              let tag = Data(base64Encoded: envelope.payload.tag)
        else { throw RemoteMeshError.decryptFailed }
        let box = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        let opened = try ChaChaPoly.open(box, using: key)
        return try RemoteMeshCodec.decoder.decode(type, from: opened)
        #else
        throw RemoteMeshError.cryptoUnavailable
        #endif
    }

    private func loadOrCreate() throws -> Material {
        if let data = try? Data(contentsOf: identityURL),
           let material = try? RemoteMeshCodec.decoder.decode(Material.self, from: data) {
            return material
        }
        #if canImport(CryptoKit)
        let signing = Curve25519.Signing.PrivateKey()
        let agreement = Curve25519.KeyAgreement.PrivateKey()
        let material = Material(
            nodeId: UUID().uuidString,
            signingPrivateKey: signing.rawRepresentation.base64EncodedString(),
            signingPublicKey: signing.publicKey.rawRepresentation.base64EncodedString(),
            agreementPrivateKey: agreement.rawRepresentation.base64EncodedString(),
            agreementPublicKey: agreement.publicKey.rawRepresentation.base64EncodedString()
        )
        let data = try RemoteMeshCodec.encoder.encode(material)
        try data.write(to: identityURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identityURL.path)
        return material
        #else
        throw RemoteMeshError.cryptoUnavailable
        #endif
    }

    private struct Material: Codable {
        var nodeId: String
        var signingPrivateKey: String
        var signingPublicKey: String
        var agreementPrivateKey: String
        var agreementPublicKey: String
    }
}

public enum RemoteMeshCapabilities {
    public static let current = [
        "peer.identity",
        "peer.link",
        "workspace.allowlist",
        "remote.chat",
        "remote.job",
        "remote.job.events",
        "remote.job.cancel",
    ]
}

public enum RemoteMeshCodec {
    public static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    public static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func signingBytes(
        senderNodeId: String,
        timestamp: String,
        method: String,
        path: String,
        payload: RemoteMeshSealedPayload
    ) -> Data {
        let body = [
            senderNodeId,
            timestamp,
            method.uppercased(),
            path,
            payload.nonce,
            payload.ciphertext,
            payload.tag,
        ].joined(separator: "\n")
        return Data(body.utf8)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
