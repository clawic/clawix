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
}

enum BackendStateReader {
    private static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json")
    }

    static func read() -> BackendState {
        let env = ProcessInfo.processInfo.environment
        let url = env["CLAWIX_DESKTOP_STATE_FIXTURE"]
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? defaultURL
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .empty }

        let roots = stringArray(json["electron-saved-workspace-roots"])
        let order = stringArray(json["project-order"])
        let labels = json["electron-workspace-root-labels"] as? [String: String] ?? [:]
        let orderedRoots = orderedUnique(primary: order, fallback: roots)
        let projects = orderedRoots.map { path in
            Project(
                id: StableProjectID.uuid(for: normalized(path)),
                name: displayName(for: path, labels: labels),
                path: normalized(path)
            )
        }

        return BackendState(
            workspaceRoots: projects,
            pinnedThreadIds: stringArray(json["pinned-thread-ids"]),
            threadWorkspaceRootHints: (json["thread-workspace-root-hints"] as? [String: String] ?? [:])
                .mapValues(normalized),
            projectlessThreadIds: Set(stringArray(json["projectless-thread-ids"]))
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [String])?.filter { !$0.isEmpty } ?? []
    }

    private static func orderedUnique(primary: [String], fallback: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in primary + fallback {
            let path = normalized(raw)
            guard !path.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            result.append(path)
        }
        return result
    }

    private static func displayName(for path: String, labels: [String: String]) -> String {
        if let label = labels[path], !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }

    private static func normalized(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
