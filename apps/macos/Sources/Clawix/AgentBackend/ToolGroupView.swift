import SwiftUI

// Inline tool-group row that appears between reasoning chunks in an
// assistant message timeline. While a command is in flight it shows
// "Ejecutando <cmd>" verbatim (matching Clawix's live view); once the
// turn finishes, completed commands collapse into "Ran N commands".

struct ToolGroupView: View {
    let items: [WorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Chronological order: completed items happened first (they
            // had to finish before the next one could start in Codex's
            // sequential tool flow), so their aggregate rows go on top.
            // The currently-running command is the freshest action and
            // always renders at the bottom of the group, matching how
            // the user mentally appends "what Clawix is doing right now"
            // below "what Clawix already did".
            ForEach(aggregateRows) { row in
                aggregateRow(row)
            }
            ForEach(runningCommands) { item in
                if case .command(let text, _) = item.kind, let cmd = text, !cmd.isEmpty {
                    inlineRow(
                        prefix: String(localized: "Running", bundle: AppLocale.bundle, locale: AppLocale.current),
                        body: cmd
                    )
                }
            }
        }
    }

    // MARK: - Live rows

    private var runningCommands: [WorkItem] {
        items.filter { item in
            guard case .command = item.kind else { return false }
            return item.status == .inProgress
        }
    }

    private func inlineRow(prefix: String, body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TerminalIcon(size: 14)
                .foregroundColor(Color(white: 0.45))
                .frame(width: 16, alignment: .leading)
            ShimmerText(
                text: prefix + " " + body,
                font: BodyFont.system(size: 13, wght: 500),
                color: .white,
                baseOpacity: 0.30,
                peakOpacity: 0.80,
                cycleDuration: 3.0,
                radius: 6.0
            )
        }
    }

    // MARK: - Aggregated rows

    private struct AggregateRow: Identifiable {
        let id: String
        let icon: String
        let text: String
    }

    private var aggregateRows: [AggregateRow] {
        var rows: [AggregateRow] = []

        // Clawix tags each shell command with one or more parsed_cmd
        // actions (read / list_files / search / unknown). Each command
        // contributes to exactly one bucket: if any action is typed
        // (read/list/search) it splits across those typed counters and
        // does NOT also bump ranCommands; only fully-opaque commands
        // (just .unknown, or no parsed_cmd at all) add to ranCommands.
        var readFiles = 0
        var listed = 0
        var searchedItems = 0
        var ranCommands = 0
        var fileChanges = 0
        var browserUsed = false
        var webSearchCount = 0
        var mcpTools: [(server: String, tool: String)] = []
        var dynamicTools: [String] = []
        var imageGenerations = 0
        var imageViews = 0
        // browser-use plugin: count `js` calls that drove the in-app
        // browser separately from plain Node REPL calls (setup, errors,
        // js_reset). One row per bucket; jsReset folds into the REPL one
        // because Codex's UI doesn't surface it as its own pill.
        var jsBrowserCount = 0
        var jsReplCount = 0

        for item in items {
            switch item.kind {
            case .command(_, let actions):
                if item.status == .inProgress { continue }
                let reads = actions.filter { $0 == .read }.count
                let lists = actions.filter { $0 == .listFiles }.count
                let searches = actions.filter { $0 == .search }.count
                if reads + lists + searches > 0 {
                    readFiles += reads
                    listed += lists
                    searchedItems += searches
                } else {
                    ranCommands += 1
                }
            case .fileChange(let paths):
                fileChanges += max(1, paths.count)
            case .webSearch:
                webSearchCount += 1
            case .mcpTool(let server, let tool):
                mcpTools.append((server, tool))
            case .dynamicTool(let name):
                let lower = name.lowercased()
                if lower.contains("browser") {
                    browserUsed = true
                } else if lower.contains("web") {
                    webSearchCount += 1
                } else {
                    dynamicTools.append(name)
                }
            case .imageGeneration:
                imageGenerations += 1
            case .imageView:
                imageViews += 1
            case .jsCall(_, .browser):
                jsBrowserCount += 1
            case .jsCall(_, .repl):
                jsReplCount += 1
            case .jsReset:
                jsReplCount += 1
            }
        }

        if readFiles > 0 || listed > 0 || searchedItems > 0 || ranCommands > 0 {
            var parts: [String] = []
            if readFiles > 0 { parts.append(L10n.exploredFiles(readFiles)) }
            if searchedItems > 0 { parts.append(L10n.searchedItems(searchedItems)) }
            if listed > 0 { parts.append(L10n.listedItems(listed)) }
            if ranCommands > 0 {
                // Standalone "Ran N commands" starts a sentence and
                // must capitalise; when it trails other parts ("Explored
                // 1 file, ran 3 commands") it stays inline lowercase.
                parts.append(parts.isEmpty
                    ? L10n.ranCommands(ranCommands)
                    : L10n.ranCommandsInline(ranCommands))
            }
            // Stacked folders when the row includes any directory
            // listing; magnifying glass when it reads files or runs
            // searches; terminal sentinel when it only ran opaque
            // commands.
            let icon: String
            if listed > 0 {
                icon = "clawix.folderStack"
            } else if readFiles > 0 || searchedItems > 0 {
                icon = "magnifyingglass"
            } else {
                icon = "clawix.terminal"
            }
            rows.append(AggregateRow(
                id: "exec",
                icon: icon,
                text: parts.joined(separator: ", ")
            ))
        }
        if fileChanges > 0 {
            rows.append(AggregateRow(
                id: "files",
                icon: "clawix.pencil",
                text: L10n.modifiedFiles(fileChanges)
            ))
        }
        // "Used the browser" pill. Backed both by the legacy `browserUsed`
        // flag (older `dynamicTool` shape from MCP integrations that
        // returned a screenshot) and the new `jsBrowserCount` from the
        // browser-use plugin classifier. When several `js` calls in the
        // same tools group all drove the browser the row counts them as
        // `Used the browser N times`, matching how MCP rows already work.
        let totalBrowser = jsBrowserCount + (browserUsed ? 1 : 0)
        if totalBrowser > 0 {
            let text: String
            if totalBrowser <= 1 {
                text = String(localized: "Used the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
            } else {
                text = L10n.usedToolTimes("the browser", totalBrowser)
            }
            rows.append(AggregateRow(
                id: "browser",
                icon: "clawix.cursor",
                text: text
            ))
        }
        // "Used Node Repl" pill. Plain JS REPL invocations and js_reset
        // events both land here so a run of `Used Node Repl` reads as one
        // counted row (Codex's UI does the same: `js_reset` doesn't get
        // its own pill).
        if jsReplCount > 0 {
            let text = jsReplCount <= 1
                ? L10n.usedTool("Node Repl")
                : L10n.usedToolTimes("Node Repl", jsReplCount)
            rows.append(AggregateRow(
                id: "nodeRepl",
                icon: "command",
                text: text
            ))
        }
        if webSearchCount > 0 {
            let text = webSearchCount == 1
                ? String(localized: "Searched the web", bundle: AppLocale.bundle, locale: AppLocale.current)
                : String(localized: "Searched the web \(webSearchCount) times", bundle: AppLocale.bundle, locale: AppLocale.current)
            rows.append(AggregateRow(id: "webSearch", icon: "clawix.globe", text: text))
        }
        // Collapse runs of MCP calls that target the same server into a
        // single row, carrying the call count so two `Used Revenuecat`
        // hits in a row render as `Used Revenuecat 2 times` instead of
        // stacking duplicate rows.
        var serverOrder: [String] = []
        var serverCounts: [String: Int] = [:]
        for mcp in mcpTools where !mcp.server.isEmpty {
            if serverCounts[mcp.server] == nil { serverOrder.append(mcp.server) }
            serverCounts[mcp.server, default: 0] += 1
        }
        for (idx, server) in serverOrder.enumerated() {
            let count = serverCounts[server] ?? 1
            let pretty = prettyMcpServer(server)
            let text = count <= 1 ? L10n.usedTool(pretty) : L10n.usedToolTimes(pretty, count)
            rows.append(AggregateRow(
                id: "mcp\(idx)",
                icon: "clawix.mcp",
                text: text
            ))
        }
        for (idx, name) in dynamicTools.enumerated() {
            rows.append(AggregateRow(
                id: "dyn\(idx)",
                icon: "wrench.and.screwdriver",
                text: L10n.usedTool(name)
            ))
        }
        if imageGenerations > 0 {
            rows.append(AggregateRow(
                id: "imgGen",
                icon: "photo",
                text: L10n.generatedImages(imageGenerations)
            ))
        }
        if imageViews > 0 {
            rows.append(AggregateRow(
                id: "imgView",
                icon: "eye",
                text: L10n.viewedImages(imageViews)
            ))
        }
        return rows
    }

    private func aggregateRow(_ row: AggregateRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                switch row.icon {
                case "clawix.terminal":
                    TerminalIcon(size: 14)
                case "clawix.globe":
                    GlobeIcon(size: 13)
                case "clawix.cursor":
                    CursorIcon(size: 13)
                case "clawix.mcp":
                    McpIcon(size: 14)
                case "clawix.pencil":
                    PencilIconView(color: Color(white: 0.45), lineWidth: 1.0)
                        .frame(width: 15, height: 15)
                        .offset(y: 2)
                case "magnifyingglass":
                    SearchIcon(size: 11.5)
                case "clawix.folderStack":
                    FolderStackIcon(size: 17)
                        .offset(y: 3.5)
                case "command":
                    // `⌘` glyph for `Used Node Repl`, mirroring Codex's
                    // own UI. SF Symbol's `command` is Apple's canonical
                    // mark; rendering at 13pt medium matches the visual
                    // weight of the other custom icons in this row set.
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .medium))
                default:
                    Image(systemName: row.icon)
                        .font(BodyFont.system(size: 11.5))
                }
            }
            .foregroundColor(Color(white: 0.45))
            .frame(width: 16, alignment: .leading)
            Text(row.text)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

