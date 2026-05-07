import Foundation

// Read/write helper for ~/.codex/AGENTS.md, the file Codex uses as the
// user's global custom instructions. The Personalization page in
// Settings is a direct editor for this file: load on appear, save on
// commit. No in-memory cache. If something else (CLI, another editor)
// rewrites the file while the app is open, re-entering the page picks
// up the new contents on the next .onAppear.
enum CodexInstructionsFile {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/AGENTS.md")
    }

    /// Returns the current file contents, or an empty string if the
    /// file does not exist yet (first-time users). Throws on real I/O
    /// errors so the caller can surface them.
    static func read() throws -> String {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Atomic write: temp file + rename, so a crash mid-write cannot
    /// leave AGENTS.md half-written. Creates ~/.codex/ if missing.
    static func write(_ text: String) throws {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        let data = Data(text.utf8)
        let tempURL = dir.appendingPathComponent(
            "AGENTS.md.tmp.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString.prefix(8))"
        )
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }
}
