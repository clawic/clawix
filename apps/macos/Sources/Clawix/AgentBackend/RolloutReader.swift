import Foundation
import ClawixCore

// Reads a Clawix rollout JSONL file and reconstructs the visible chat
// history with the same structure the live streaming pipeline produces:
// each assistant turn becomes one ChatMessage whose `timeline` interleaves
// reasoning chunks (the commentary/final-answer text shown to the user)
// and tool groups (the work-summary rows that appear between paragraphs).

struct RolloutHistoryEntry {
    enum Role { case user, assistant }
    let role: Role
    /// Final visible body for this entry. For assistants it mirrors what
    /// the live streaming pipeline writes to `ChatMessage.content` after
    /// `markAssistantCompleted`: the last `phase=final_answer` text, or
    /// the last reasoning chunk if the turn was commentary-only. The
    /// renderer collapses the timeline once the turn is done, so this
    /// field is what the user actually sees in a hydrated rollout.
    let text: String
    let timestamp: Date
    let timeline: [AssistantTimelineEntry]
    /// Image attachments referenced by this entry. Populated for user
    /// messages whose JSONL event carries an optional
    /// `images: [{filename, mimeType}]` array — each filename is read
    /// from `CLAWIX_IMAGE_FIXTURE_DIR` and base64-encoded so the daemon
    /// can ship the bytes inline on the wire. Empty for typed messages
    /// and for assistant entries.
    let attachments: [WireAttachment]
    /// Synthesized work summary for assistant entries. `startedAt` is
    /// the first timestamp seen for the turn and `endedAt` is the last
    /// timestamp seen, so the chat row's "Worked for Xs" header reads
    /// correctly on a hydrated rollout (the live pipeline populates
    /// this via `beginWorkSummary` / `completeWorkSummary`; without an
    /// equivalent here, the header would never render after a chat
    /// reload). `items` stays empty because the chronological tool
    /// rows already live in `timeline.tools`. Nil for user entries.
    let workSummary: WorkSummary?

    init(
        role: Role,
        text: String,
        timestamp: Date,
        timeline: [AssistantTimelineEntry],
        attachments: [WireAttachment],
        workSummary: WorkSummary? = nil
    ) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.timeline = timeline
        self.attachments = attachments
        self.workSummary = workSummary
    }
}

enum RolloutReader {

    /// Combined output: the parsed history + whether the last
    /// assistant turn looks interrupted (the agent started a turn the
    /// rollout never closed with `final_answer` / `turn_completed`,
    /// and the trailing event is older than `interruptedThreshold`,
    /// so we are confident it is not just a turn still in flight).
    struct ReadResult {
        var entries: [RolloutHistoryEntry]
        var lastTurnInterrupted: Bool
    }

    /// Anything older than this without a closing event is treated as
    /// an interrupted turn rather than a turn-still-in-flight. 30s is
    /// generous enough to outlast the typical "user is reading
    /// reasoning" gap and short enough to surface the pill quickly
    /// after a daemon respawn.
    static let interruptedThreshold: TimeInterval = 30

    /// Default tail-read window for `readTailWithStatus`. 4 MB covers
    /// dozens to hundreds of typical assistant turns (more than any
    /// viewport ever shows on first paint), while keeping the parse
    /// cost bounded regardless of how big the rollout has grown — real
    /// sessions in `~/.codex/sessions/` reach 100+ MB. Read the head
    /// (`tailHeadProbeBytes`) separately to recover `session_meta`.
    static let defaultTailBytes: Int = 4 * 1024 * 1024

    /// Bytes scanned at the start of the file to recover the
    /// `session_meta` line when doing a tail read. Codex writes it as
    /// the very first record, so a small probe is enough.
    static let tailHeadProbeBytes: Int = 64 * 1024

    static func read(path: URL) -> [RolloutHistoryEntry] {
        guard let data = try? Data(contentsOf: path) else { return [] }
        return parse(data: data, now: Date()).entries
    }

    /// Like `read(path:)` but also reports whether the last turn was
    /// interrupted. Use this on hydration after a daemon respawn so
    /// the chat row can surface a "Interrupted, retry?" pill.
    static func readWithStatus(path: URL, now: Date = Date()) -> ReadResult {
        guard let data = try? Data(contentsOf: path) else {
            return ReadResult(entries: [], lastTurnInterrupted: false)
        }
        return parse(data: data, now: now)
    }

    /// Tail-only variant of `readWithStatus`. Reads the trailing
    /// `maxBytes` of the rollout instead of the whole file, aligns to
    /// the first newline so we never start mid-line, and prepends the
    /// head `session_meta` line so the parser can still resolve cwd /
    /// session id (used to materialise `apply_patch` paths and
    /// `imagegen` output dirs). For files smaller than `maxBytes`
    /// falls back to a full read so short rollouts are not truncated.
    ///
    /// Used by the Mac UI hydration path: the chat opens at the
    /// latest turn, the user almost never scrolls hundreds of turns
    /// up immediately, and capping the parse to a fixed window keeps
    /// "click chat → first paint" sub-second even on multi-hundred-MB
    /// rollouts. Older history can be loaded on demand by callers
    /// that want it via `readWithStatus`.
    static func readTailWithStatus(
        path: URL,
        maxBytes: Int = defaultTailBytes,
        now: Date = Date()
    ) -> ReadResult {
        guard let handle = try? FileHandle(forReadingFrom: path) else {
            return ReadResult(entries: [], lastTurnInterrupted: false)
        }
        defer { try? handle.close() }

        let totalSize: UInt64 = (try? handle.seekToEnd()) ?? 0
        if totalSize == 0 {
            return ReadResult(entries: [], lastTurnInterrupted: false)
        }
        if totalSize <= UInt64(maxBytes) {
            try? handle.seek(toOffset: 0)
            let data = (try? handle.readToEnd()) ?? Data()
            return parse(data: data, now: now)
        }

        // Step 1: head probe to recover session_meta.
        try? handle.seek(toOffset: 0)
        let probeSize = min(UInt64(tailHeadProbeBytes), totalSize)
        let headData = (try? handle.read(upToCount: Int(probeSize))) ?? Data()
        let sessionMetaLine = extractSessionMetaLine(headData)

        // Step 2: tail bytes from the file.
        let tailOffset = totalSize - UInt64(maxBytes)
        try? handle.seek(toOffset: tailOffset)
        var tailData = (try? handle.readToEnd()) ?? Data()

        // Step 3: drop the leading partial line so parse never sees
        // a half-record. tailOffset > 0 here by construction (we
        // returned early when totalSize <= maxBytes), so there's
        // always at least one full line ahead of the first newline.
        if let firstNL = tailData.firstIndex(of: 0x0a) {
            let alignStart = tailData.index(after: firstNL)
            tailData = alignStart < tailData.endIndex
                ? tailData.subdata(in: alignStart..<tailData.endIndex)
                : Data()
        }

        var combined = Data(capacity: tailData.count + 4096)
        if let sessionMetaLine {
            combined.append(sessionMetaLine)
            combined.append(0x0a)
        }
        combined.append(tailData)
        return parse(data: combined, now: now)
    }

    /// Walk the head probe for the first `session_meta` JSONL line.
    /// Returns the line bytes (without trailing newline) so callers
    /// can splice it into a tail read. nil when the probe doesn't
    /// contain one; callers degrade gracefully (relative paths emitted
    /// by `apply_patch` won't resolve to absolute, but the chat still
    /// renders).
    private static func extractSessionMetaLine(_ data: Data) -> Data? {
        var start = data.startIndex
        while start < data.endIndex {
            let nl = data[start...].firstIndex(of: 0x0a) ?? data.endIndex
            let line = data[start..<nl]
            start = nl < data.endIndex ? data.index(after: nl) : data.endIndex
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any],
                  (obj["type"] as? String) == "session_meta" else {
                continue
            }
            return Data(line)
        }
        return nil
    }

    private static func parse(data: Data, now: Date) -> ReadResult {
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
        // For `name == "js"` function_calls we need both the input
        // arguments (which carry `code` and `title`) and the
        // mcp_tool_call_end result (which carries the success/error
        // payload used to refine the browser/repl flavour). The two
        // events arrive in order on the same call_id, so we stash the
        // function_call payload here and resolve at mcp_tool_call_end.
        var pendingJS: [String: PendingJSCall] = [:]
        // cwd captured from `session_meta`. Used to resolve relative
        // paths emitted by `apply_patch` (the new custom_tool_call shape
        // writes paths like `cualquiera.md`, not absolute) so the
        // ChangedFileCard pill can find the file on disk.
        var sessionCwd: String? = nil
        // session id captured from `session_meta.payload.id`. Used to
        // build the absolute filesystem path for `imagegen` outputs,
        // which Codex stores under
        // `~/.codex/generated_images/<sessionId>/<callId>.png`.
        var sessionId: String? = nil

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        // Interrupted-detection state. We used to do a second full pass
        // over `data` to compute these; folding them into the main loop
        // avoids re-walking + re-decoding tens of thousands of JSONL
        // lines on a multi-MB rollout.
        var lastParsedTimestamp: Date? = nil
        var sawClose = false
        var sawAnyAssistantWork = false

        var start = data.startIndex
        while start < data.endIndex {
            let nl = data[start...].firstIndex(of: 0x0a) ?? data.endIndex
            let line = data[start..<nl]
            start = nl < data.endIndex ? data.index(after: nl) : data.endIndex
            if line.isEmpty { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: line, options: [])) as? [String: Any] else {
                continue
            }

            // `parsedTimestamp` is the strictly-from-JSON value; only
            // those advance `lastParsedTimestamp` so a synthetic
            // `Date()` fallback (line had no `timestamp` field) does
            // not falsely re-anchor the interrupted-turn check.
            let parsedTimestamp: Date? = (obj["timestamp"] as? String).flatMap {
                isoFormatter.date(from: $0) ?? isoFallback.date(from: $0)
            }
            let timestamp: Date = parsedTimestamp ?? Date()
            if let parsedTimestamp {
                lastParsedTimestamp = parsedTimestamp
                // Stamp the in-progress turn's `endedAt` so the synthesized
                // `WorkSummary` ends on the last activity timestamp instead
                // of leaving the chat row's "Worked for Xs" header ticking
                // forever (`isActive` is gated on `endedAt == nil`).
                pending?.endedAt = parsedTimestamp
            }
            let kind = obj["type"] as? String
            guard let payload = obj["payload"] as? [String: Any] else { continue }
            let inner = payload["type"] as? String

            // Track interrupted-turn signal. Mirrors the heuristic the
            // dedicated `detectInterrupted` pass used to compute: any
            // assistant-side activity sets `sawAnyAssistantWork`; an
            // explicit close (`turn_completed`, `final_answer`) or a
            // new `user_message` resets it.
            if kind == "event_msg" {
                let event = inner ?? (obj["event"] as? String)
                let phase = (payload["phase"] as? String)
                    ?? (obj["phase"] as? String)
                switch event {
                case "agent_message", "agent_reasoning",
                     "exec_command_begin", "exec_command_output_delta",
                     "exec_command_end", "tool_call":
                    sawAnyAssistantWork = true
                case "turn_completed":
                    sawClose = true
                case "user_message":
                    sawClose = true
                    sawAnyAssistantWork = false
                default:
                    break
                }
                if phase == "final_answer" {
                    sawClose = true
                }
            }

            if kind == "session_meta" {
                if sessionCwd == nil,
                   let cwd = payload["cwd"] as? String, !cwd.isEmpty {
                    sessionCwd = cwd
                }
                if sessionId == nil,
                   let id = payload["id"] as? String, !id.isEmpty {
                    sessionId = id
                }
            }

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
                    let attachments = Self.loadImageAttachments(from: payload["images"])
                    if !trimmed.isEmpty,
                       !trimmed.hasPrefix("<turn_aborted>"),
                       !containsRequestMarker(trimmed) {
                        out.append(RolloutHistoryEntry(
                            role: .user,
                            text: trimmed,
                            timestamp: timestamp,
                            timeline: [],
                            attachments: attachments
                        ))
                    } else if containsRequestMarker(trimmed),
                              let extracted = extractRequestFromBrowserWrapper(trimmed) {
                        out.append(RolloutHistoryEntry(
                            role: .user,
                            text: extracted,
                            timestamp: timestamp,
                            timeline: [],
                            attachments: attachments
                        ))
                    } else if trimmed.isEmpty, !attachments.isEmpty {
                        // Attachment-only user message: no text body, but
                        // the bubble still needs to render the thumbnails.
                        out.append(RolloutHistoryEntry(
                            role: .user,
                            text: "",
                            timestamp: timestamp,
                            timeline: [],
                            attachments: attachments
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
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                switch name {
                case "exec_command":
                    if seenCallIds.contains(callId) { continue }
                    if pending == nil {
                        pending = PendingAssistant(timestamp: timestamp)
                    }
                    pending?.appendCommand(id: callId, text: nil, actions: [])
                    seenCallIds.insert(callId)
                case "js":
                    // Stash the args; the mcp_tool_call_end branch is
                    // where we actually emit the WorkItem (so we can
                    // factor the success/error result into the flavour).
                    let parsed = decodeJSArguments(payload["arguments"])
                    pendingJS[callId] = PendingJSCall(
                        title: parsed.title,
                        code: parsed.code,
                        isReset: false
                    )
                case "js_reset":
                    pendingJS[callId] = PendingJSCall(
                        title: nil,
                        code: "",
                        isReset: true
                    )
                default:
                    continue
                }

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

            case ("response_item", "custom_tool_call"):
                // Newer Codex Desktop serialises `apply_patch` as a
                // custom_tool_call (with the patch body in `input`) rather
                // than the legacy `patch_apply_end` event. Extract the
                // touched paths from the patch headers so the timeline
                // gets the same `.fileChange` row and the trailing
                // ChangedFileCard pills appear.
                let name = payload["name"] as? String ?? ""
                guard name == "apply_patch" else { continue }
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if !seenCallIds.insert(callId).inserted { continue }
                let input = (payload["input"] as? String)
                    ?? (payload["arguments"] as? String)
                    ?? ""
                let raw = Self.parseApplyPatchInputPaths(input)
                let paths = raw.map { Self.resolveAgainstCwd($0, cwd: sessionCwd) }
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

            case ("response_item", "web_search_call"):
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if !seenCallIds.insert(callId).inserted { continue }
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                pending?.appendOther(
                    WorkItem(id: callId, kind: .webSearch, status: .completed)
                )

            case ("event_msg", "image_generation_end"):
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if !seenCallIds.insert(callId).inserted { continue }
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                let imagePath: String? = sessionId.map { sid in
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".codex", isDirectory: true)
                        .appendingPathComponent("generated_images", isDirectory: true)
                        .appendingPathComponent(sid, isDirectory: true)
                        .appendingPathComponent("\(callId).png")
                        .path
                }
                pending?.appendOther(
                    WorkItem(
                        id: callId,
                        kind: .imageGeneration,
                        status: .completed,
                        generatedImagePath: imagePath
                    )
                )

            case ("event_msg", "view_image_tool_call"):
                let callId = payload["call_id"] as? String ?? UUID().uuidString
                if !seenCallIds.insert(callId).inserted { continue }
                if pending == nil {
                    pending = PendingAssistant(timestamp: timestamp)
                }
                pending?.appendOther(
                    WorkItem(id: callId, kind: .imageView, status: .completed)
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
                // The browser-use plugin runs every call (including
                // js_reset) through the synthetic `node_repl` MCP server.
                // Route those by JS-flavour classification so the timeline
                // reads `Used the browser` / `Used Node Repl` exactly the
                // way Codex's own UI does. Other MCP servers fall through
                // to the legacy image-aware path below.
                if server == "node_repl" {
                    let pendingCall = pendingJS.removeValue(forKey: callId)
                    let kind: WorkItemKind
                    if tool == "js_reset" || pendingCall?.isReset == true {
                        kind = .jsReset
                    } else {
                        let flavor = classifyJSCall(
                            code: pendingCall?.code ?? "",
                            result: payload["result"]
                        )
                        kind = .jsCall(title: pendingCall?.title, flavor: flavor)
                    }
                    pending?.appendOther(
                        WorkItem(id: callId, kind: kind, status: .completed)
                    )
                    continue
                }
                // Clawix relabels MCP calls whose result carries a screenshot
                // as "navegador" usage. Kept as a defensive fallback for
                // older or third-party MCP integrations that piped a
                // screenshot back through a non-`node_repl` server name.
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

        let interrupted: Bool = {
            guard sawAnyAssistantWork, !sawClose,
                  let last = lastParsedTimestamp else { return false }
            return now.timeIntervalSince(last) > interruptedThreshold
        }()
        return ReadResult(entries: out, lastTurnInterrupted: interrupted)
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

    /// Pull file paths out of a `custom_tool_call` apply_patch input. The
    /// patch body uses `*** Add File: <path>`, `*** Update File: <path>`,
    /// `*** Delete File: <path>` headers (and an optional `*** Move To:
    /// <path>` after Update). Paths can be relative to the session cwd;
    /// resolution to absolute happens at the call site.
    private static func parseApplyPatchInputPaths(_ input: String) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        let prefixes = [
            "*** Add File: ",
            "*** Update File: ",
            "*** Delete File: ",
            "*** Move To: ",
        ]
        for raw in input.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            for prefix in prefixes where line.hasPrefix(prefix) {
                let path = String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty, seen.insert(path).inserted {
                    paths.append(path)
                }
                break
            }
        }
        return paths
    }

    /// Resolve a relative path against the rollout's session cwd captured
    /// from `session_meta`. Absolute paths pass through unchanged. When
    /// the cwd is missing we leave the path as-is so the chip still
    /// renders the file name even if "Open" can't find the file on disk.
    private static func resolveAgainstCwd(_ path: String, cwd: String?) -> String {
        if path.hasPrefix("/") { return path }
        guard let cwd, !cwd.isEmpty else { return path }
        return URL(fileURLWithPath: cwd)
            .appendingPathComponent(path)
            .path
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

    /// In-flight `js` / `js_reset` function_call captured from the
    /// rollout while we wait for its paired `mcp_tool_call_end`. Holds
    /// the args we'll need at emission time (the `code` for browser-API
    /// substring matching, the title for any future expand-to-detail UI).
    fileprivate struct PendingJSCall {
        let title: String?
        let code: String
        let isReset: Bool
    }

    /// Decode the `arguments` blob of a `js` function_call into title +
    /// code. The CLI always serialises arguments as a JSON-encoded
    /// string at the payload top level, so we double-decode here. Any
    /// malformed shape collapses to an empty result so the WorkItem
    /// still renders (just without a title and unable to discriminate
    /// flavour by code substrings).
    fileprivate static func decodeJSArguments(_ raw: Any?) -> (title: String?, code: String) {
        guard let str = raw as? String,
              let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, "")
        }
        let title = (obj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let code = obj["code"] as? String ?? ""
        return (title, code)
    }

    /// Decide whether a single `js` invocation drove the in-app browser
    /// (Playwright / agent.browser API / setup of the browser-use
    /// runtime) or was a plain Node REPL block — including failed calls
    /// that errored before reaching browser code. Mirrors the heuristic
    /// Codex's official UI uses to label each call as `Used the browser`
    /// vs `Used Node Repl`.
    fileprivate static func classifyJSCall(code: String, result: Any?) -> JSCallFlavor {
        // Errored calls (`'snap' has already been declared`, `Tab N is
        // not part of browser session`, kernel timeouts, etc.) go to the
        // REPL bucket even when their `code` would normally tag them as
        // browser. Codex's UI does the same: a JS error throws away the
        // browser-call framing because no browser work actually landed.
        if jsResultLooksLikeError(result) {
            return .repl
        }
        if codeUsesBrowserAPI(code) {
            return .browser
        }
        return .repl
    }

    /// Substrings that, when present in a `js` invocation's `code`,
    /// signal the call drove the in-app browser. Kept narrow on purpose
    /// — every entry maps to a real method on `tab.*` / `agent.browser.*`
    /// or to the bootstrap path (`setupAtlasRuntime`, the plugin client
    /// import). Add new entries when the plugin grows API surface.
    private static let browserAPISubstrings: [String] = [
        "tab.goto", "tab.playwright", "tab.cua", "tab.dom_cua",
        "tab.clipboard", "tab.dev",
        "tab.url(", "tab.title(",
        "tab.back(", "tab.forward(", "tab.reload(", "tab.close(",
        "agent.browser",
        "browser-client.mjs",
        "setupAtlasRuntime"
    ]

    private static func codeUsesBrowserAPI(_ code: String) -> Bool {
        guard !code.isEmpty else { return false }
        return browserAPISubstrings.contains { code.contains($0) }
    }

    /// Common JS REPL error / control messages that indicate the call
    /// failed before reaching the browser. These are the verbatim
    /// strings the `node_repl` MCP server returns inside `result.Ok.content[0].text`
    /// when the runtime throws or the browser session is unreachable.
    private static let jsErrorMarkers: [String] = [
        "is not defined",
        "already been declared",
        "No active Codex browser",
        "is not part of browser session",
        "js execution timed out",
        "kernel reset",
        "ReferenceError",
        "SyntaxError",
        "TypeError"
    ]

    /// True when an `mcp_tool_call_end` result for `node_repl` looks like
    /// a JS error rather than a successful browser/REPL call. We only
    /// treat very short text-only bodies as errors — long output (DOM
    /// snapshots, JSON dumps) and multi-item content (text + screenshot
    /// image) are always success.
    private static func jsResultLooksLikeError(_ raw: Any?) -> Bool {
        guard let result = raw as? [String: Any] else { return false }
        let payload = (result["Ok"] as? [String: Any])
                   ?? (result["Err"] as? [String: Any])
                   ?? result
        guard let content = payload["content"] as? [[String: Any]] else { return false }
        if content.count != 1 { return false }
        guard let first = content.first,
              (first["type"] as? String) == "text",
              let text = first["text"] as? String else { return false }
        if text.count > 1500 { return false }
        return jsErrorMarkers.contains { text.contains($0) }
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

    /// Resolve the optional `images: [{filename, mimeType}]` array from a
    /// `user_message` payload into inline-base64 `WireAttachment`s so the
    /// daemon can ship them on the wire when the iPhone hydrates the
    /// chat. Files are read from `CLAWIX_IMAGE_FIXTURE_DIR` (set by
    /// `dummy.sh` to `<workspace>/dummy/images/`); missing or empty
    /// entries are dropped silently so a typo in a fixture doesn't break
    /// the whole chat hydrate. nil / non-array `images` returns [], so
    /// real Codex rollouts (which never carry this field) are no-ops.
    fileprivate static func loadImageAttachments(from raw: Any?) -> [WireAttachment] {
        guard let arr = raw as? [[String: Any]], !arr.isEmpty else { return [] }
        guard let dirString = ProcessInfo.processInfo.environment["CLAWIX_IMAGE_FIXTURE_DIR"],
              !dirString.isEmpty else {
            return []
        }
        let dir = URL(fileURLWithPath: dirString, isDirectory: true)
        var out: [WireAttachment] = []
        for entry in arr {
            guard let filename = (entry["filename"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !filename.isEmpty else { continue }
            // Defensive against fixture authors writing absolute paths or
            // `..` traversal: treat the basename only so the load is
            // always rooted at CLAWIX_IMAGE_FIXTURE_DIR.
            let base = (filename as NSString).lastPathComponent
            let fileURL = dir.appendingPathComponent(base)
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { continue }
            let mime = (entry["mimeType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.guessMimeType(forFilename: base)
            let id = (entry["id"] as? String) ?? UUID().uuidString
            let kindRaw = (entry["kind"] as? String) ?? "image"
            let kind: WireAttachmentKind = (kindRaw == "audio") ? .audio : .image
            out.append(WireAttachment(
                id: id,
                kind: kind,
                mimeType: mime,
                filename: base,
                dataBase64: data.base64EncodedString()
            ))
        }
        return out
    }

    private static func guessMimeType(forFilename name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default:     return "image/png"
        }
    }
}

/// Mutable accumulator for a single assistant turn while we walk the
/// rollout. Tracks the chronological mix of text paragraphs and tool
/// invocations so the final ChatMessage matches what the live streaming
/// pipeline produces.
private struct PendingAssistant {
    let timestamp: Date
    /// Last parsed timestamp seen while this turn was being assembled.
    /// Bumped from the parser loop on every line that belongs to the
    /// turn so `finalize()` can stamp `WorkSummary.endedAt` with the
    /// actual close time instead of leaving the live counter ticking.
    var endedAt: Date
    var timeline: [AssistantTimelineEntry] = []
    var finalText: String = ""

    init(timestamp: Date) {
        self.timestamp = timestamp
        self.endedAt = timestamp
    }

    mutating func appendText(_ text: String, isFinal: Bool) {
        // Each agent_message lands as a `.message` entry in the
        // timeline, mirroring the live streaming pipeline (where
        // `nAgentMsgDelta` extends a trailing `.message` block). If the
        // last entry already is a `.message`, extend it so a single
        // assistant turn split across multiple `agent_message` lines
        // doesn't render as multiple paragraphs.
        if case .message(let lastId, let existing) = timeline.last {
            timeline[timeline.count - 1] = .message(id: lastId, text: existing + "\n\n" + text)
        } else {
            timeline.append(.message(id: UUID(), text: text))
        }
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
        // Mirror the live streaming pipeline: ChatMessage.content holds
        // the last final_answer text. Commentary-only turns fall back to
        // the last `.message` (agent text) chunk, then to the last
        // `.reasoning` chunk, so the body never goes invisible (the
        // renderer collapses the timeline behind the chevron once the
        // turn is finished).
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
            if fallback.isEmpty {
                for entry in timeline.reversed() {
                    if case .reasoning(_, let text) = entry {
                        fallback = text
                        break
                    }
                }
            }
            body = fallback
        }
        return RolloutHistoryEntry(
            role: .assistant,
            text: body,
            timestamp: timestamp,
            timeline: timeline,
            attachments: [],
            workSummary: WorkSummary(
                startedAt: timestamp,
                endedAt: endedAt,
                items: []
            )
        )
    }
}
