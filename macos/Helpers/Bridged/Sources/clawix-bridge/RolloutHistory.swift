import Foundation
import ClawixCore

enum RolloutHistory {
    struct Metadata {
        var startedAt: Date?
        var cwd: String?
        var firstUserMessage: String?
    }

    /// Mutable accumulator for one assistant turn. Mirrors the Mac
    /// `RolloutReader.PendingAssistant` pattern: every `agent_message`
    /// becomes a `.message` timeline entry on the same WireMessage so
    /// the chat row groups the whole turn under a single "Worked for
    /// Xs" disclosure instead of rendering each commentary paragraph
    /// as its own bubble.
    private struct PendingAssistant {
        let startedAt: Date
        var endedAt: Date
        var timeline: [WireTimelineEntry] = []
        var finalText: String = ""

        init(startedAt: Date) {
            self.startedAt = startedAt
            self.endedAt = startedAt
        }

        mutating func appendMessage(text: String, isFinal: Bool) {
            if case .message(let lastId, let existing) = timeline.last {
                timeline[timeline.count - 1] = .message(
                    id: lastId,
                    text: existing + "\n\n" + text
                )
            } else {
                timeline.append(.message(id: UUID().uuidString, text: text))
            }
            if isFinal {
                finalText = text
            }
        }

        func finalize() -> WireMessage {
            // The collapsed chat row reads `content` once the disclosure
            // is closed; pick the canonical body the same way the Mac's
            // RolloutReader does: phase=="final_answer" wins, otherwise
            // fall back to the last `.message` entry so commentary-only
            // turns still have a visible body when collapsed.
            let body: String
            if !finalText.isEmpty {
                body = finalText
            } else {
                var fallback = ""
                for entry in timeline.reversed() {
                    if case .message(_, let text) = entry {
                        fallback = text
                        break
                    }
                }
                body = fallback
            }
            return WireMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: body,
                streamingFinished: true,
                timestamp: startedAt,
                timeline: timeline,
                workSummary: WireWorkSummary(
                    startedAt: startedAt,
                    endedAt: endedAt,
                    items: []
                )
            )
        }
    }

    static func read(path: URL, now: Date = Date()) -> (messages: [WireMessage], lastTurnInterrupted: Bool) {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return ([], false)
        }
        return parse(text: text, now: now)
    }

    static func readTail(path: URL, maxBytes: UInt64 = 1_048_576, now: Date = Date()) -> (messages: [WireMessage], lastTurnInterrupted: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: path) else {
            return ([], false)
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            guard let text = String(data: data, encoding: .utf8) else { return ([], false) }
            let normalized = offset > 0
                ? text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                : text
            return parse(text: normalized, now: now)
        } catch {
            return ([], false)
        }
    }

    static func metadata(path: URL, maxBytes: Int = 262_144) -> Metadata {
        guard let handle = try? FileHandle(forReadingFrom: path) else { return Metadata() }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: maxBytes)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return Metadata() }
        var meta = Metadata()
        let iso = fractionalFormatter()
        let isoFallback = plainFormatter()
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if meta.startedAt == nil, let timestamp = obj["timestamp"] as? String {
                meta.startedAt = iso.date(from: timestamp) ?? isoFallback.date(from: timestamp)
            }
            if obj["type"] as? String == "session_meta",
               let payload = obj["payload"] as? [String: Any] {
                meta.cwd = payload["cwd"] as? String
                if meta.startedAt == nil, let timestamp = payload["timestamp"] as? String {
                    meta.startedAt = iso.date(from: timestamp) ?? isoFallback.date(from: timestamp)
                }
            }
            if obj["type"] as? String == "event_msg",
               let payload = obj["payload"] as? [String: Any],
               payload["type"] as? String == "user_message",
               let message = payload["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meta.firstUserMessage = message
                break
            }
        }
        return meta
    }

    static func threadId(from url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix("rollout-"), stem.count >= 36 else { return nil }
        let suffix = String(stem.suffix(36)).lowercased()
        return UUID(uuidString: suffix)?.uuidString.lowercased()
    }

    private static func parse(text: String, now: Date) -> (messages: [WireMessage], lastTurnInterrupted: Bool) {
        var messages: [WireMessage] = []
        var pending: PendingAssistant? = nil
        var lastEventAt: Date?
        var sawAgentWork = false
        var sawClose = true
        let iso = fractionalFormatter()
        let isoFallback = plainFormatter()

        func flushPending() {
            if let p = pending {
                messages.append(p.finalize())
                pending = nil
            }
        }

        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let parsedTimestamp: Date? = (obj["timestamp"] as? String).flatMap {
                iso.date(from: $0) ?? isoFallback.date(from: $0)
            }
            if let parsedTimestamp {
                lastEventAt = parsedTimestamp
                pending?.endedAt = parsedTimestamp
            }
            guard obj["type"] as? String == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  let type = payload["type"] as? String
            else { continue }
            let timestamp = parsedTimestamp ?? lastEventAt ?? now
            switch type {
            case "user_message":
                flushPending()
                if let message = payload["message"] as? String {
                    messages.append(WireMessage(
                        id: UUID().uuidString,
                        role: .user,
                        content: message,
                        streamingFinished: true,
                        timestamp: timestamp
                    ))
                    sawClose = true
                    sawAgentWork = false
                }
            case "agent_message":
                // Skip Codex's interim-summary chunks: they're scratch
                // intermediates the renderer never wants to surface as
                // user-visible paragraphs.
                let phase = payload["phase"] as? String
                if phase == "interim_summary" { continue }
                let message = (payload["message"] as? String) ?? (payload["text"] as? String) ?? ""
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if pending == nil {
                    pending = PendingAssistant(startedAt: timestamp)
                }
                pending?.appendMessage(text: trimmed, isFinal: phase == "final_answer")
                sawAgentWork = true
                sawClose = (phase == "final_answer")
            case "turn_completed":
                flushPending()
                sawClose = true
            default:
                break
            }
        }
        flushPending()
        let interrupted = sawAgentWork
            && !sawClose
            && lastEventAt.map { now.timeIntervalSince($0) > 30 } == true
        return (messages, interrupted)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func plainFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

// MARK: - Inline audio attachments

/// Maps a MIME type from a bridge `transcribeAudio` frame to the file
/// extension WhisperKit's `AVAudioFile` decoder expects. The list is
/// the codec set the iPhone composer can produce out of the box.
func audioExtension(mimeType: String) -> String {
    switch mimeType.lowercased() {
    case "audio/wav", "audio/x-wav", "audio/wave":     return "wav"
    case "audio/m4a", "audio/mp4", "audio/x-m4a":      return "m4a"
    case "audio/aac":                                  return "aac"
    case "audio/mpeg", "audio/mp3":                    return "mp3"
    case "audio/ogg", "audio/opus":                    return "ogg"
    case "audio/flac":                                 return "flac"
    case "audio/caf", "audio/x-caf":                   return "caf"
    default:                                           return "m4a"
    }
}

// `AttachmentSpooler` lives in ClawixCore so the macOS GUI bridge and
// this daemon share the same temp-file layout for inline image inputs.
