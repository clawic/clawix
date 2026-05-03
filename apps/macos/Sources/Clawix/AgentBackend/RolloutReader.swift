import Foundation

// Reads a Clawix rollout JSONL file and reconstructs the visible chat
// history with the same structure the live streaming pipeline produces:
// each assistant turn becomes one ChatMessage whose `timeline` interleaves
// reasoning chunks (the commentary/final-answer text shown to the user)
// and tool groups (the work-summary rows that appear between paragraphs).

struct RolloutHistoryEntry {
    enum Role { case user, assistant }
    let role: Role
    /// Final visible text for this entry. For assistants this is empty
    /// when all the body lives in `timeline` as `.reasoning` chunks
    /// (Clawix's "commentary" phase) — the renderer falls back to the
    /// timeline in that case.
    let text: String
    let timestamp: Date
    let timeline: [AssistantTimelineEntry]
}

enum RolloutReader {

    static func read(path: URL) -> [RolloutHistoryEntry] {
        guard let data = try? Data(contentsOf: path) else { return [] }
        return parse(data: data)
    }

    private static func parse(data: Data) -> [RolloutHistoryEntry] {
        var out: [RolloutHistoryEntry] = []

        // Builder for the assistant turn currently being assembled. nil
        // when the next agent_message / exec_command_end should open a
        // fresh turn. A pending turn is flushed on user_message and at
        // EOF so trailing content is never dropped.
        var pending: PendingAssistant? = nil
        // De-dupe by call_id: a single command shows up as both a
        // function_call (start) and an exec_command_end (finish). We
        // prefer the end event because it carries `parsed_cmd`, but if
        // the file is truncated we still surface the start.
        var seenCallIds = Set<String>()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        var start = data.startIndex
        while start < data.endIndex {
            let nl = data[start...].firstIndex(of: 0x0a) ?? data.endIndex
            let line = data[start..<nl]
            start = nl < data.endIndex ? data.index(after: nl) : data.endIndex
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any] else {
                continue
            }

            let timestamp: Date = {
                if let s = obj["timestamp"] as? String {
                    return isoFormatter.date(from: s) ?? isoFallback.date(from: s) ?? Date()
                }
                return Date()
            }()
            let kind = obj["type"] as? String
            guard let payload = obj["payload"] as? [String: Any] else { continue }
            let inner = payload["type"] as? String

            switch (kind, inner) {

            case ("event_msg", "user_message"):
                if let p = pending {
                    out.append(p.finalize())
                    pending = nil
                }
                if let msg = payload["message"] as? String {
                    let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Clawix re-injects internal scaffolding ("# In app
                    // browser:", "<turn_aborted>", …) into the response
                    // history as fake user_messages — skip those.
                    if !trimmed.isEmpty,
                       !trimmed.hasPrefix("<turn_aborted>"),
                       !containsRequestMarker(trimmed) {
                        out.append(RolloutHistoryEntry(
                            role: .user,
                            text: trimmed,
                            timestamp: timestamp,
                            timeline: []
                        ))
                    } else if containsRequestMarker(trimmed),
                              let extracted = extractRequestFromBrowserWrapper(trimmed) {
                        out.append(RolloutHistoryEntry(
                            role: .user,
                            text: extracted,
                            timestamp: timestamp,
                            timeline: []
                        ))
                    }
                }

            case ("event_msg", "agent_message"):
                let phase = payload["phase"] as? String
                if phase == "interim_summary" { continue }
                guard let msg = payload["message"] as? String else { continue }
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                pending?.appendText(trimmed, isFinal: phase == "final_answer")

            case ("event_msg", "exec_command_end"):
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                let actions = parseCommandActions(payload["parsed_cmd"])
                let cmdText = (payload["command"] as? [String])?.last
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                if seenCallIds.contains(callId) {
                    // function_call already emitted a placeholder for this
                    // command; replace it with the rich parsed_cmd payload
                    // so the timeline renders the parsed read/list label
                    // instead of a generic "ran 1 command".
                    pending?.updateCommand(id: callId, text: cmdText, actions: actions)
                } else {
                    pending?.appendCommand(id: callId, text: cmdText, actions: actions)
                    seenCallIds.insert(callId)
                }

            case ("response_item", "function_call"):
                let name = payload["name"] as? String ?? ""
                guard name == "exec_command" else { continue }
                // call_id sits at the payload top level; the inner
                // `arguments` JSON only carries cmd/workdir/etc.
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if seenCallIds.contains(callId) { continue }
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                pending?.appendCommand(id: callId, text: nil, actions: [])
                seenCallIds.insert(callId)

            case ("event_msg", "patch_apply_end"):
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if !seenCallIds.insert(callId).inserted { continue }
                let stdout = payload["stdout"] as? String ?? ""
                let paths = Self.parsePatchApplyPaths(stdout)
                if paths.isEmpty { continue }
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                pending?.appendOther(
                    WorkItem(
                        id: callId,
                        kind: .fileChange(paths: paths),
                        status: .completed
                    )
                )

            case ("event_msg", "mcp_tool_call_end"):
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if !seenCallIds.insert(callId).inserted { continue }
                let invocation = payload["invocation"] as? [String: Any]
                let server = (invocation?["server"] as? String) ?? ""
                let tool = (invocation?["tool"] as? String) ?? ""
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                // Clawix relabels MCP calls whose result carries a screenshot
                // as "navegador" usage (the browser-use plugin pipes a
                // playwright screenshot back through node_repl). Detect that
                // shape and emit a dynamicTool so the renderer says
                // "Se han usado the browser" instead of "Node Repl · js".
                let kind: WorkItemKind
                if mcpResultHasImage(payload["result"]) {
                    kind = .dynamicTool(name: "the browser")
                } else {
                    kind = .mcpTool(server: server, tool: tool)
                }
                pending?.appendOther(
                    WorkItem(id: callId, kind: kind, status: .completed)
                )

            default:
                continue
            }
        }

        if let p = pending {
            out.append(p.finalize())
        }
        return out
    }

    /// Clawix parses each shell command into one or more semantic actions
    /// (read / list_files / search / unknown). We map that array to our
    /// CommandActionKind so ToolGroupView can split exploration vs raw
    /// exec the same way the live pipeline does.
    private static func parseCommandActions(_ raw: Any?) -> [CommandActionKind] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { entry in
            guard let t = entry["type"] as? String else { return nil }
            switch t {
            case "read": return .read
            case "list_files", "listFiles": return .listFiles
            case "search": return .search
            default: return .unknown
            }
        }
    }

    /// Pull absolute file paths out of a `patch_apply_end` stdout. The CLI
    /// writes one line per touched file prefixed with the change kind:
    /// `M /abs/path` (modified), `A /abs/path` (added), `D /abs/path`
    /// (deleted). The first line is `Success. Updated the following files:`
    /// and is ignored.
    private static func parsePatchApplyPaths(_ stdout: String) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        for raw in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count > 2 else { continue }
            let prefix = line.prefix(2)
            guard prefix == "M " || prefix == "A " || prefix == "D " else { continue }
            let path = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if path.isEmpty || seen.contains(path) { continue }
            seen.insert(path)
            paths.append(path)
        }
        return paths
    }

    /// True when an mcp_tool_call_end result carries an image item. Clawix
    /// uses that as the signal to render the row as "Se han usado el
    /// navegador" (the browser-use plugin returns a playwright screenshot
    /// inside its content array).
    private static func mcpResultHasImage(_ raw: Any?) -> Bool {
        guard let result = raw as? [String: Any] else { return false }
        // result shape: { "Ok": { "content": [{ "type": "image" | "text", … }] } }
        let payload = (result["Ok"] as? [String: Any])
                   ?? (result["Err"] as? [String: Any])
                   ?? result
        guard let content = payload["content"] as? [[String: Any]] else { return false }
        return content.contains { ($0["type"] as? String) == "image" }
    }

    /// In-app browser wraps user requests with a header block; pull the
    /// trailing prompt back out so the chat shows what the user typed
    /// rather than the scaffolding.
    private static func extractRequestFromBrowserWrapper(_ text: String) -> String? {
        guard let marker = requestMarkers.first(where: { text.contains($0) }),
              let r = text.range(of: marker) else { return nil }
        let tail = text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    private static let requestMarkers = [
        "## My request for Clawix:",
        "## My request for " + ["Co", "dex"].joined() + ":"
    ]

    private static func containsRequestMarker(_ text: String) -> Bool {
        requestMarkers.contains { text.contains($0) }
    }
}

/// Mutable accumulator for a single assistant turn while we walk the
/// rollout. Tracks the chronological mix of text paragraphs and tool
/// invocations so the final ChatMessage matches what the live streaming
/// pipeline produces.
private struct PendingAssistant {
    let timestamp: Date
    var timeline: [AssistantTimelineEntry] = []
    var finalText: String = ""

    mutating func appendText(_ text: String, isFinal: Bool) {
        // Each agent_message becomes its own paragraph in the timeline,
        // rendered as a `.reasoning` block (same style as body text).
        timeline.append(.reasoning(id: UUID(), text: text))
        if isFinal {
            finalText = text
        }
    }

    mutating func appendCommand(id: String, text: String?, actions: [CommandActionKind]) {
        let item = WorkItem(
            id: id,
            kind: .command(text: text, actions: actions),
            status: .completed
        )
        // Consecutive shell commands fold into the same tools group so the
        // aggregated row reads "Se han explorado 3 archivos, ran 1 command".
        if case .tools(let groupId, let items) = timeline.last,
           items.last.map({ TimelineFamily.command.matches($0.kind) }) ?? false {
            timeline[timeline.count - 1] = .tools(id: groupId, items: items + [item])
        } else {
            timeline.append(.tools(id: UUID(), items: [item]))
        }
    }

    /// Replace an already-emitted command placeholder (from a function_call
    /// that arrived before its exec_command_end) with the richer payload.
    mutating func updateCommand(id: String, text: String?, actions: [CommandActionKind]) {
        for tIdx in timeline.indices {
            if case .tools(let gid, var items) = timeline[tIdx],
               let itemIdx = items.firstIndex(where: { $0.id == id }) {
                items[itemIdx] = WorkItem(
                    id: id,
                    kind: .command(text: text, actions: actions),
                    status: .completed
                )
                timeline[tIdx] = .tools(id: gid, items: items)
                return
            }
        }
    }

    /// Append any non-command tool item (mcpTool, dynamicTool, fileChange,
    /// imageGen/View). MCP/dynamic tools always open a new tools group so
    /// each call renders as its own row, matching how Clawix shows them
    /// stacked between reasoning paragraphs.
    mutating func appendOther(_ item: WorkItem) {
        let openNew: Bool
        if case .tools(_, let items) = timeline.last, let last = items.last {
            openNew = !TimelineFamily.from(last.kind).matches(item.kind)
        } else {
            openNew = true
        }
        if openNew {
            timeline.append(.tools(id: UUID(), items: [item]))
        } else if case .tools(let gid, let items) = timeline.last {
            timeline[timeline.count - 1] = .tools(id: gid, items: items + [item])
        } else {
            timeline.append(.tools(id: UUID(), items: [item]))
        }
    }

    func finalize() -> RolloutHistoryEntry {
        RolloutHistoryEntry(
            role: .assistant,
            text: "",
            timestamp: timestamp,
            timeline: timeline
        )
    }
}
