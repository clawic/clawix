import Foundation
import ClawixCore

/// "Where does the next prompt run?" Either the local Codex backend
/// (the existing path) or a paired remote Mac. Picked from the
/// composer pill; consumed by `AppState.sendMessage()` to decide
/// whether to dispatch through Codex or through the mesh.
enum MeshTarget: Equatable, Hashable {
    case local
    case peer(nodeId: String)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    var peerNodeId: String? {
        if case .peer(let id) = self { return id }
        return nil
    }
}

extension PeerRecord {
    /// True when this peer is currently usable as a destination. False
    /// for revoked peers; the composer disables the row but keeps it
    /// visible so the user can see *why* sending isn't possible.
    var isAvailable: Bool { revokedAt == nil }
}
