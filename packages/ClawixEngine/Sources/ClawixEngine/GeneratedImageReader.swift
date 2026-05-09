import Foundation

/// Reads bytes for an `imageGeneration` work item that Codex's `imagegen`
/// tool wrote under `~/.codex/generated_images/<sessionId>/<callId>.<ext>`,
/// or for a markdown image link the assistant emitted pointing into that
/// same tree.
///
/// Sandbox: the path the client sends is fully resolved (symlinks /
/// `..` collapsed) and the resolved real path must still live under the
/// canonical `~/.codex/generated_images/` directory. Anything else
/// short-circuits with a "denied" error so a compromised iPhone session
/// can't turn the bridge into an arbitrary file reader.
public enum GeneratedImageReader {

    public struct Result: Sendable {
        public let dataBase64: String?
        public let mimeType: String?
        public let errorMessage: String?
        public init(dataBase64: String?, mimeType: String?, errorMessage: String?) {
            self.dataBase64 = dataBase64
            self.mimeType = mimeType
            self.errorMessage = errorMessage
        }
    }

    /// Root the daemon is willing to serve from. Computed per-call so a
    /// host that overrides `$HOME` (tests, sandboxed previews) doesn't
    /// have to re-build the framework.
    public static var sandboxRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("generated_images", isDirectory: true)
            .resolvingSymlinksInPath()
    }

    public static func read(path: String) -> Result {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(dataBase64: nil, mimeType: nil, errorMessage: "Empty path")
        }
        // Strip an optional `file://` prefix the model sometimes emits in
        // markdown so the same handler covers both work-item paths and
        // links the assistant wrote inline.
        let normalized: String = {
            if let url = URL(string: trimmed), url.isFileURL {
                return url.path
            }
            if trimmed.hasPrefix("file://") {
                return String(trimmed.dropFirst("file://".count))
            }
            return trimmed
        }()
        let url = URL(fileURLWithPath: normalized).resolvingSymlinksInPath()
        let root = sandboxRoot
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else {
            return Result(
                dataBase64: nil,
                mimeType: nil,
                errorMessage: "Path is outside the generated_images sandbox"
            )
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Result(
                dataBase64: nil,
                mimeType: nil,
                errorMessage: "Image not found"
            )
        }
        guard let data = try? Data(contentsOf: url) else {
            return Result(
                dataBase64: nil,
                mimeType: nil,
                errorMessage: "Couldn't read image bytes"
            )
        }
        let mime = mimeType(forExtension: url.pathExtension)
        return Result(
            dataBase64: data.base64EncodedString(),
            mimeType: mime,
            errorMessage: nil
        )
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "webp":         return "image/webp"
        case "heic":         return "image/heic"
        default:             return "application/octet-stream"
        }
    }
}
