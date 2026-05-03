import Foundation

// Atomic writes to ~/.codex/.codex-global-state.json so our local
// projects show up in Codex CLI / Electron desktop app. Gated behind
// SyncSettings.pushProjectsToCodex (default OFF, requires user
// confirmation to enable).
//
// Hard rules:
//   - Read-modify-write the FULL JSON. Preserve every field we don't
//     touch (Electron app keeps adding new ones).
//   - Atomic rename via FileManager.replaceItemAt to avoid partial
//     writes if the process dies mid-write.
//   - Never throw, never crash. Any I/O or parse failure → log + return
//     false. The caller (AppState mutators) doesn't react; the local
//     project still gets created in our DB regardless.
//   - Never remove entries: deleting a local project does NOT propagate.
//     Codex may have learned about that path independently and removing
//     it silently would surprise the user.
@MainActor
enum CodexStateWriter {
    private static let workspaceRootsKey = "electron-saved-workspace-roots"
    private static let workspaceLabelsKey = "electron-workspace-root-labels"

    static var stateFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json")
    }

    /// Add `path` to the saved workspace roots and (if provided) set its
    /// label. Idempotent: reapplying does not duplicate.
    @discardableResult
    static func upsertWorkspaceRoot(path: String, label: String?) -> Bool {
        guard !path.isEmpty else { return false }
        return mutate { json in
            var roots = (json[workspaceRootsKey] as? [String]) ?? []
            if !roots.contains(path) {
                roots.append(path)
                json[workspaceRootsKey] = roots
            }
            if let label, !label.isEmpty {
                var labels = (json[workspaceLabelsKey] as? [String: String]) ?? [:]
                labels[path] = label
                json[workspaceLabelsKey] = labels
            }
        }
    }

    /// Update the label for an existing root. No-op if path is not in
    /// the saved roots (we don't add it implicitly here; callers should
    /// have called upsertWorkspaceRoot first).
    @discardableResult
    static func renameWorkspaceLabel(path: String, label: String) -> Bool {
        guard !path.isEmpty, !label.isEmpty else { return false }
        return mutate { json in
            var labels = (json[workspaceLabelsKey] as? [String: String]) ?? [:]
            labels[path] = label
            json[workspaceLabelsKey] = labels
        }
    }

    /// Read-modify-write the global state file atomically. Returns true
    /// only if the write succeeded.
    private static func mutate(_ apply: (inout [String: Any]) -> Void) -> Bool {
        let url = stateFileURL
        guard let data = try? Data(contentsOf: url),
              var json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            print("[CodexStateWriter] Could not read or parse \(url.path); skipping write.")
            return false
        }
        apply(&json)
        do {
            let updated = try JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            )
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(".codex-global-state.json.tmp.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString.prefix(8))")
            try updated.write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            return true
        } catch {
            print("[CodexStateWriter] Atomic write failed: \(error). State file untouched.")
            return false
        }
    }
}
