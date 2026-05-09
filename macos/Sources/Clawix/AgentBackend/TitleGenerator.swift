import Foundation

// Generates conversation titles by spawning the runtime CLI in non-interactive
// mode. We reuse runtime auth instead of reimplementing it in Swift.
//   - The CLI handles model resolution and request shaping consistently
//     with what the rest of the app does.
//
// The runtime spawns its binary via a Node entrypoint, so each invocation
// adds ~200 ms of bootstrap. We therefore cap concurrency at 4 — enough
// to keep the sidebar lively on first launch without saturating the CPU
// when dozens of historic sessions need a title.

@MainActor
final class TitleGenerator {

    private struct PendingJob {
        let sessionId: String
        let prompt: String
        let onTitle: @MainActor (String) -> Void
    }

    private let binary: ClawixBinaryInfo
    private var inFlight: Set<String> = []
    private var pending: [PendingJob] = []
    private var active: Int = 0
    private let maxConcurrent = 4
    /// Hard cap per process. If runtime execution hangs (model unavailable,
    /// approval prompt despite non-interactive mode, …) we kill it and
    /// move on. The session keeps its fallback title until the next
    /// app launch retries.
    private let timeoutSeconds: Double = 25

    init(binary: ClawixBinaryInfo) {
        self.binary = binary
    }

    /// Schedule title generation for `sessionId`. Idempotent: a second
    /// call for the same id while the first is in-flight is dropped.
    /// `onTitle` runs on the main actor when (and only when) generation
    /// produced a usable string.
    func ensureTitle(
        sessionId: String,
        prompt: String,
        onTitle: @escaping @MainActor (String) -> Void
    ) {
        if inFlight.contains(sessionId) { return }
        inFlight.insert(sessionId)
        pending.append(PendingJob(sessionId: sessionId, prompt: prompt, onTitle: onTitle))
        pump()
    }

    private func pump() {
        while active < maxConcurrent, !pending.isEmpty {
            let job = pending.removeFirst()
            active += 1
            let binaryURL = binary.path
            let timeout = timeoutSeconds
            Task.detached(priority: .utility) {
                let title = Self.runBackendExec(
                    binary: binaryURL,
                    prompt: job.prompt,
                    timeoutSeconds: timeout
                )
                await MainActor.run {
                    self.active -= 1
                    self.inFlight.remove(job.sessionId)
                    if let title { job.onTitle(title) }
                    self.pump()
                }
            }
        }
    }

    /// Off-actor: spawn the runtime, wait, parse output. Returns a
    /// sanitized title or nil if anything failed.
    nonisolated private static func runBackendExec(
        binary: URL,
        prompt: String,
        timeoutSeconds: Double
    ) -> String? {
        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-title-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }

        let proc = Process()
        proc.executableURL = binary
        // Notes on the flag set:
        //  - No `-m`: we ride the user's configured default model. The
        //    "smaller / faster" models (gpt-5-mini etc.) are blocked on
        //    ChatGPT-account auth, so hardcoding one breaks for the
        //    common login path. Whatever they use day-to-day works.
        //  - `model_reasoning_effort=low`: titles don't need deep
        //    thinking and the user's config likely sets this to "high",
        //    which costs ~22k tokens and ~30s per call. Low brings it
        //    down to ~4s.
        //  - `--ephemeral`: don't pollute runtime session history with our
        //    title-generation rollouts.
        proc.arguments = [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "-s", "read-only",
            "-c", "model_reasoning_effort=\"low\"",
            "-o", outFile.path,
            prompt
        ]
        // Drain pipes so the child does not block on a full stdout/stderr
        // buffer when it logs more than a few KiB before exiting.
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return nil
        }

        let killer = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: killer)
        proc.waitUntilExit()
        killer.cancel()

        _ = try? outPipe.fileHandleForReading.readToEnd()
        _ = try? errPipe.fileHandleForReading.readToEnd()

        guard proc.terminationStatus == 0 else { return nil }

        guard let raw = try? String(contentsOf: outFile, encoding: .utf8) else { return nil }
        return sanitize(raw)
    }

    /// Trim, strip wrapping quotes, drop multi-line / refusal / empty
    /// outputs, cap to 80 characters, strip trailing punctuation.
    nonisolated private static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count > 1 {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("«") && s.hasSuffix("»") && s.count > 1 {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Multi-line output usually means the model rambled instead of
        // emitting a single title. Treat as failure.
        if s.contains("\n") { return nil }
        let lower = s.lowercased()
        let refusalPrefixes = ["i'm sorry", "lo siento", "no puedo", "i cannot", "i can't"]
        if refusalPrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }
        if s.count > 80 { s = String(s.prefix(80)) }
        while let last = s.last, ".!?,;:".contains(last) {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Build the user-visible prompt for title generation. Keep it as a
    /// single string argument so we don't have to deal with stdin.
    static func buildPrompt(
        firstUserMessage: String,
        firstAssistantMessage: String? = nil
    ) -> String {
        let trimmedUser = firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let clippedUser = String(trimmedUser.prefix(1500))
        var lines: [String] = [
            "Return a short title (3 to 6 words) for this conversation, in the same language as the user.",
            "Just the title. No quotes, no trailing period, no extra text.",
            "",
            "User message:",
            "<<<",
            clippedUser,
            ">>>"
        ]
        if let asst = firstAssistantMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !asst.isEmpty {
            lines.append("")
            lines.append("Assistant response:")
            lines.append("<<<")
            lines.append(String(asst.prefix(800)))
            lines.append(">>>")
        }
        return lines.joined(separator: "\n")
    }
}
