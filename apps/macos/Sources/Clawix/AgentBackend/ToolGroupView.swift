import SwiftUI

// Inline tool-group row that appears between reasoning chunks in an
// assistant message timeline. While a command is in flight it shows
// "Ejecutando <cmd>" verbatim (matching Clawix's live view); once the
// turn finishes, completed commands collapse into "Ran N commands".

struct ToolGroupView: View {
    let items: [WorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Currently-running commands: render each one verbatim with
            // the live "Running" prefix so the user can read what
            // Clawix is doing right now.
            ForEach(runningCommands) { item in
                if case .command(let text, _) = item.kind, let cmd = text, !cmd.isEmpty {
                    inlineRow(
                        prefix: String(localized: "Running", bundle: AppLocale.bundle, locale: AppLocale.current),
                        body: cmd
                    )
                }
            }
            // Everything else (completed commands, file changes, web,
            // tool calls, image gen/view) collapses into one or more
            // aggregate rows the way Clawix does.
            ForEach(aggregateRows) { row in
                aggregateRow(row)
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
            (Text(prefix + " ")
                .foregroundColor(Color(white: 0.50))
             + Text(body)
                .foregroundColor(Color(white: 0.55))
            )
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
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
        if browserUsed {
            rows.append(AggregateRow(
                id: "browser",
                icon: "clawix.cursor",
                text: String(localized: "Used the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
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
                default:
                    Image(systemName: row.icon)
                        .font(.system(size: 11.5))
                }
            }
            .foregroundColor(Color(white: 0.45))
            .frame(width: 16, alignment: .leading)
            Text(row.text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

