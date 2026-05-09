import Foundation

struct ToolTimelineRow: Identifiable, Equatable {
    let id: String
    let icon: String
    let text: String
}

enum ToolTimelinePresentation {
    static func aggregateRows(for items: [WorkItem]) -> [ToolTimelineRow] {
        var rows: [ToolTimelineRow] = []

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
                parts.append(parts.isEmpty
                    ? L10n.ranCommands(ranCommands)
                    : L10n.ranCommandsInline(ranCommands))
            }
            let icon: String
            if listed > 0 {
                icon = "clawix.folderStack"
            } else if readFiles > 0 || searchedItems > 0 {
                icon = "magnifyingglass"
            } else {
                icon = "clawix.terminal"
            }
            rows.append(ToolTimelineRow(
                id: "exec",
                icon: icon,
                text: parts.joined(separator: ", ")
            ))
        }
        if fileChanges > 0 {
            rows.append(ToolTimelineRow(
                id: "files",
                icon: "clawix.pencil",
                text: L10n.modifiedFiles(fileChanges)
            ))
        }
        let totalBrowser = jsBrowserCount + (browserUsed ? 1 : 0)
        if totalBrowser > 0 {
            let text: String
            if totalBrowser <= 1 {
                text = String(localized: "Used the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
            } else {
                text = L10n.usedToolTimes("the browser", totalBrowser)
            }
            rows.append(ToolTimelineRow(
                id: "browser",
                icon: "clawix.cursor",
                text: text
            ))
        }
        if jsReplCount > 0 {
            let text = jsReplCount <= 1
                ? L10n.usedTool("Node Repl")
                : L10n.usedToolTimes("Node Repl", jsReplCount)
            rows.append(ToolTimelineRow(
                id: "nodeRepl",
                icon: "command",
                text: text
            ))
        }
        if webSearchCount > 0 {
            let text = webSearchCount == 1
                ? String(localized: "Searched the web", bundle: AppLocale.bundle, locale: AppLocale.current)
                : String(localized: "Searched the web \(webSearchCount) times", bundle: AppLocale.bundle, locale: AppLocale.current)
            rows.append(ToolTimelineRow(id: "webSearch", icon: "clawix.globe", text: text))
        }

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
            rows.append(ToolTimelineRow(
                id: "mcp\(idx)",
                icon: isComputerUseMcpServer(server) ? "clawix.computerUse" : "clawix.mcp",
                text: text
            ))
        }
        for (idx, name) in dynamicTools.enumerated() {
            rows.append(ToolTimelineRow(
                id: "dyn\(idx)",
                icon: "wrench.and.screwdriver",
                text: L10n.usedTool(name)
            ))
        }
        if imageGenerations > 0 {
            rows.append(ToolTimelineRow(
                id: "imgGen",
                icon: "photo",
                text: L10n.generatedImages(imageGenerations)
            ))
        }
        if imageViews > 0 {
            rows.append(ToolTimelineRow(
                id: "imgView",
                icon: "eye",
                text: L10n.viewedImages(imageViews)
            ))
        }
        return rows
    }
}
