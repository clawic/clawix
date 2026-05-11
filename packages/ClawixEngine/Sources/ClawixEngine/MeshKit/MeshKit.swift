import Foundation
import Security

// MeshKit wraps a peer-to-peer transport that can carry the existing
// Clawix bridge protocol when LAN / Bonjour / Tailscale candidates fail.
// The intent on Apple platforms is the iroh-ffi Swift Package, which
// embeds a Rust core that handles QUIC, hole punching, and the relay
// fallback. When the native dependency is unavailable (CI builds, debug
// rings that haven't pulled the artifact yet) MeshKit silently falls
// back to a stub so call sites compile and the rest of the bridge race
// degrades gracefully to LAN.

public struct MeshNodeID: Hashable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public var description: String { raw }
}

public struct MeshRemote: Hashable, Codable {
    public let nodeID: MeshNodeID
    public let relayURL: URL?
    public let directAddresses: [String]

    public init(nodeID: MeshNodeID, relayURL: URL? = nil, directAddresses: [String] = []) {
        self.nodeID = nodeID
        self.relayURL = relayURL
        self.directAddresses = directAddresses
    }
}

public protocol MeshBiStream: AnyObject {
    func send(_ payload: Data) async throws
    func receive() -> AsyncThrowingStream<Data, Error>
    func close()
}

public protocol MeshNode: AnyObject {
    var nodeID: MeshNodeID { get }
    func start() async throws
    func stop() async
    func describeEndpoint() async -> (relayURL: URL?, publicAddresses: [String])
    func connect(_ remote: MeshRemote) async throws -> MeshBiStream
    func onInbound(_ handler: @escaping (MeshBiStream, MeshNodeID) -> Void)
}

public enum MeshKit {
    public static func makeNode(relayURL: URL? = nil) async throws -> MeshNode {
        if let factory = MeshNodeFactoryRegistry.factory {
            return try await factory(relayURL)
        }
        return StubMeshNode(relayURL: relayURL)
    }
}

public enum MeshNodeFactoryRegistry {
    public typealias Factory = (URL?) async throws -> MeshNode
    fileprivate static var factory: Factory?

    public static func register(_ factory: @escaping Factory) {
        Self.factory = factory
    }

    public static func clear() {
        Self.factory = nil
    }
}

final class StubMeshNode: MeshNode {
    let nodeID: MeshNodeID
    private let relayURL: URL?
    private var inboundHandler: ((MeshBiStream, MeshNodeID) -> Void)?

    init(relayURL: URL?) {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = bytes.withUnsafeMutableBufferPointer { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        let suffix = bytes.map { String(format: "%02x", $0) }.joined()
        self.nodeID = MeshNodeID("stub-\(suffix)")
        self.relayURL = relayURL
    }

    func start() async throws {
        // Stub node has nothing to do; it advertises a node id but cannot
        // actually open P2P streams.
    }

    func stop() async {}

    func describeEndpoint() async -> (relayURL: URL?, publicAddresses: [String]) {
        return (relayURL, [])
    }

    func connect(_ remote: MeshRemote) async throws -> MeshBiStream {
        throw MeshKitError.unsupported(
            "iroh-ffi unavailable: install the Swift Package or build with the iroh feature on."
        )
    }

    func onInbound(_ handler: @escaping (MeshBiStream, MeshNodeID) -> Void) {
        self.inboundHandler = handler
    }
}

public enum MeshKitError: Error, LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let message): return message
        }
    }
}
