import Foundation
import CryptoKit

struct BackendState {
    var workspaceRoots: [Project]
    var pinnedThreadIds: [String]
    var threadWorkspaceRootHints: [String: String]
    var projectlessThreadIds: Set<String>

    static let empty = BackendState(
        workspaceRoots: [],
        pinnedThreadIds: [],
        threadWorkspaceRootHints: [:],
        projectlessThreadIds: []
    )
}

enum StableProjectID {
    static func uuid(for path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        let bytes = Array(digest.prefix(16))
        let text = String(format:
            "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuidString: text) ?? UUID()
    }

    static func uuid(forResourceId resourceId: String) -> UUID {
        uuid(for: "claw.resource:\(resourceId)")
    }

    static func newResourceId() -> String {
        "res_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }
}
