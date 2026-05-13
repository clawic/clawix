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

    /// Inserts or replaces a sentinel-delimited block by id. Blocks are
    /// identified by the comment markers `<!-- clawix:<id>-begin -->` and
    /// `<!-- clawix:<id>-end -->`. The body MUST NOT contain those markers.
    /// Idempotent: calling twice with the same id and body produces the
    /// same file contents.
    static func replaceSentinelBlock(id: String, body: String) throws {
        let begin = beginMarker(id: id)
        let end = endMarker(id: id)
        let current = (try? read()) ?? ""

        let block = "\(begin)\n\(body)\n\(end)"

        if let beginRange = current.range(of: begin),
           let endRange = current.range(of: end),
           beginRange.lowerBound < endRange.upperBound {
            // Replace existing block (and trailing newline if present).
            var startIndex = beginRange.lowerBound
            var stopIndex = endRange.upperBound
            // Eat one trailing newline so the block sits cleanly.
            if stopIndex < current.endIndex, current[stopIndex] == "\n" {
                stopIndex = current.index(after: stopIndex)
            }
            // Eat one leading newline.
            if startIndex > current.startIndex {
                let prev = current.index(before: startIndex)
                if current[prev] == "\n" {
                    startIndex = prev
                }
            }
            var output = current
            output.replaceSubrange(startIndex..<stopIndex, with: "\n" + block + "\n")
            try write(output)
        } else {
            // Append at the end.
            var output = current
            if !output.isEmpty && !output.hasSuffix("\n\n") {
                if output.hasSuffix("\n") {
                    output += "\n"
                } else {
                    output += "\n\n"
                }
            }
            output += block + "\n"
            try write(output)
        }
    }

    /// Removes a sentinel-delimited block by id, including the markers and
    /// the surrounding blank line. No-op if the block isn't present.
    static func removeSentinelBlock(id: String) throws {
        let current = (try? read()) ?? ""
        let begin = beginMarker(id: id)
        let end = endMarker(id: id)
        guard let beginRange = current.range(of: begin),
              let endRange = current.range(of: end),
              beginRange.lowerBound < endRange.upperBound
        else { return }
        var startIndex = beginRange.lowerBound
        var stopIndex = endRange.upperBound
        if stopIndex < current.endIndex, current[stopIndex] == "\n" {
            stopIndex = current.index(after: stopIndex)
        }
        if startIndex > current.startIndex {
            let prev = current.index(before: startIndex)
            if current[prev] == "\n" {
                startIndex = prev
            }
        }
        var output = current
        output.removeSubrange(startIndex..<stopIndex)
        // Collapse consecutive blank lines that may have been left behind.
        while output.contains("\n\n\n") {
            output = output.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        try write(output)
    }

    /// Returns the body of a sentinel block, or nil if missing.
    static func sentinelBlockBody(id: String) throws -> String? {
        let current = try read()
        let begin = beginMarker(id: id)
        let end = endMarker(id: id)
        guard let beginRange = current.range(of: begin),
              let endRange = current.range(of: end),
              beginRange.upperBound < endRange.lowerBound
        else { return nil }
        let inner = current[beginRange.upperBound..<endRange.lowerBound]
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func beginMarker(id: String) -> String { "<!-- clawix:\(id)-begin -->" }
    private static func endMarker(id: String) -> String { "<!-- clawix:\(id)-end -->" }
}

enum CodexSecretsBlock {
    static let id = "secrets"

    static let defaultBody: String = """
# Secrets (Clawix)

- All secrets must always be used through `claw secrets`. Never read, paste, or store the literal value in plain text.
- Discover available secrets with `claw secrets list [--search TERM]`.
- Get metadata of a specific secret with `claw secrets describe <internal_name>`. Metadata is safe (allowed hosts, allowed headers, type, fields, notes); the value is never returned.
- Use placeholders `{{secret_name}}` for the primary value of a secret, `{{secret_name.field_name}}` for any field of a secret.
- Normal HTTP usage: `claw secrets broker-http --url https://host... --header "Authorization: Bearer {{secret_name}}"`.
- All output is automatically redacted; secret values are replaced with `[REDACTED:secret_name]` in stdout, stderr, headers, and bodies.
- If you need a secret that doesn't exist, propose its exact metadata (internal name, allowed hosts, allowed headers, read-only, justification) so the user can create it once. Never request the literal value.
"""
}

enum CodexMemoryBlock {
    static let id = "memory"

    static let defaultBody: String = """
# Memory (Clawix)

- The user has a Memory service running locally. Use it instead of asking the user to repeat themselves across conversations.
- Search what is already known before asking the user: `claw memory search "<query>"`. Returns ranked notes (semantic when embeddings are ready, full-text otherwise).
- When the user states a preference, decision, or fact worth keeping across conversations, save it: `claw memory save --content "<markdown>" --title "<short>" [--class observation|decision|preference|...] [--scope-project <project>] [--tags a,b]`.
- Don't save ephemeral working state, current-task to-dos, or chat-specific context. Save what would still be useful in a future, unrelated conversation.
- Always include a short Why and How-to-apply line when saving a decision or preference, so the memory stays useful out of context.
- Before recommending an action based on a memory, verify the underlying file or state still exists. Memories can become stale.
- When wrapping up a task, call `claw memory conclude --content "<verbatim conclusion>"` so working memory promotes cleanly.
- Set `CLAW_MEMORY_EDITOR=agent` in your environment so edits to existing memories are stamped correctly.
"""
}
