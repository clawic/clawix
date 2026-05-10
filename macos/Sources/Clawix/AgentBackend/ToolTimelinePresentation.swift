import Foundation

struct ToolTimelineRow: Identifiable, Equatable {
    let id: String
    let icon: String
    let text: String
}

struct ToolTimelinePresentationSnapshot: Equatable {
    let aggregateRows: [ToolTimelineRow]
    let runningCommands: [WorkItem]
    let accessibilityLabel: String
}

enum ToolTimelinePresentation {
    static func aggregateRows(for items: [WorkItem]) -> [ToolTimelineRow] {
        snapshot(for: items).aggregateRows
    }

    static func snapshot(for items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        ToolTimelinePresentationCache.shared.snapshot(for: items)
    }

    fileprivate static func buildSnapshot(for items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        let aggregateRows = buildAggregateRows(for: items)
        let runningCommands = items.filter { item in
            guard case .command = item.kind else { return false }
            return item.status == .inProgress
        }
        let runningText = runningCommands.compactMap { item -> String? in
            guard case .command(let text, _) = item.kind, let text, !text.isEmpty else {
                return nil
            }
            return text
        }
        let accessibilityLabel = AccessibilityText.clipped(
            (aggregateRows.map(\.text) + runningText).joined(separator: ". ")
        )
        return ToolTimelinePresentationSnapshot(
            aggregateRows: aggregateRows,
            runningCommands: runningCommands,
            accessibilityLabel: accessibilityLabel
        )
    }

    private static func buildAggregateRows(for items: [WorkItem]) -> [ToolTimelineRow] {
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

private final class ToolTimelinePresentationCache {
    static let shared = ToolTimelinePresentationCache()

    private var values: [Key: ToolTimelinePresentationSnapshot] = [:]
    private var order: [Key] = []
    private let limit = 512

    private init() {}

    func snapshot(for items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        let key = Key(items: items)
        if let cached = values[key] {
            PerfSignpost.uiChat.event("tool.snapshot.cache_hit", items.count)
            return cached
        }
        let snapshot = ToolTimelinePresentation.buildSnapshot(for: items)
        values[key] = snapshot
        order.append(key)
        PerfSignpost.uiChat.event("tool.snapshot.cache_miss", items.count)
        if order.count > limit {
            let overflow = order.count - limit
            for oldKey in order.prefix(overflow) {
                values.removeValue(forKey: oldKey)
            }
            order.removeFirst(overflow)
        }
        return snapshot
    }

    private struct Key: Hashable {
        let parts: [String]

        init(items: [WorkItem]) {
            parts = items.map(Self.part)
        }

        private static func part(_ item: WorkItem) -> String {
            "\(item.id)|\(status(item.status))|\(kind(item.kind))|\(item.generatedImagePath ?? "")"
        }

        private static func status(_ status: WorkItemStatus) -> String {
            switch status {
            case .inProgress: return "inProgress"
            case .completed: return "completed"
            case .failed: return "failed"
            }
        }

        private static func kind(_ kind: WorkItemKind) -> String {
            switch kind {
            case .command(let text, let actions):
                return "command:\(text ?? ""):\(actions.map(action).joined(separator: ","))"
            case .fileChange(let paths):
                return "fileChange:\(paths.joined(separator: "||"))"
            case .webSearch:
                return "webSearch"
            case .mcpTool(let server, let tool):
                return "mcp:\(server):\(tool)"
            case .dynamicTool(let name):
                return "dynamic:\(name)"
            case .imageGeneration:
                return "imageGeneration"
            case .imageView:
                return "imageView"
            case .jsCall(let title, let flavor):
                return "js:\(title ?? ""):\(jsFlavor(flavor))"
            case .jsReset:
                return "jsReset"
            }
        }

        private static func action(_ action: CommandActionKind) -> String {
            switch action {
            case .read: return "read"
            case .listFiles: return "listFiles"
            case .search: return "search"
            case .unknown: return "unknown"
            }
        }

        private static func jsFlavor(_ flavor: JSCallFlavor) -> String {
            switch flavor {
            case .browser: return "browser"
            case .repl: return "repl"
            }
        }
    }
}
