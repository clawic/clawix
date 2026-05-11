import Foundation
import ClawixEngine
import os

/// Iroh-backed candidate plumbing for the iPhone bridge race.
///
/// On its own, `BridgeClient` only knows about LAN/Bonjour/Tailscale.
/// When the user has paired a coordinator (the device has a coordinator
/// URL + an access token cached), this extension can spin up an
/// auxiliary `MeshNode` that races a P2P stream against the Mac's
/// advertised `irohNodeId` and, if it wins, becomes the active path the
/// same way a LAN candidate would.
///
/// The actual `MeshNode` is supplied via `MeshNodeFactoryRegistry`. The
/// production iOS app registers the iroh-ffi-backed factory at startup;
/// in environments without the native binary, MeshKit falls back to a
/// stub that fails fast on `connect`, so the race quietly defers to the
/// LAN candidates without crashing.

fileprivate let irohDbg = Logger(subsystem: "clawix.bridge.dbg", category: "iroh")

@MainActor
public final class IrohBridgeCandidate {
    public let peerNodeID: MeshNodeID
    public let relayURL: URL?
    private let onFrame: @MainActor (Data) -> Void
    private let onClose: @MainActor () -> Void
    private var node: MeshNode?
    private var stream: MeshBiStream?

    public init(
        peerNodeID: MeshNodeID,
        relayURL: URL?,
        onFrame: @escaping @MainActor (Data) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.peerNodeID = peerNodeID
        self.relayURL = relayURL
        self.onFrame = onFrame
        self.onClose = onClose
    }

    public func start() async throws {
        let node = try await MeshKit.makeNode(relayURL: relayURL)
        try await node.start()
        self.node = node
        let remote = MeshRemote(nodeID: peerNodeID, relayURL: relayURL)
        let stream = try await node.connect(remote)
        self.stream = stream
        Task { [stream, onFrame, onClose] in
            do {
                for try await chunk in stream.receive() {
                    await MainActor.run { onFrame(chunk) }
                }
            } catch {
                irohDbg.error("iroh stream receive error: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run { onClose() }
        }
    }

    public func send(_ payload: Data) {
        guard let stream else { return }
        Task { try? await stream.send(payload) }
    }

    public func close() {
        stream?.close()
        Task { [node] in await node?.stop() }
        stream = nil
        node = nil
    }
}
