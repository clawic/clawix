import SwiftUI
import ClawixCore

// iOS-side rendering of an assistant message's chronological timeline,
// mirroring what the macOS app shows. Three pieces:
//
//   - `WorkSummaryHeaderView`: the elapsed-time disclosure that sits
//     above the assistant body. Collapsed by default; tapping reveals an
//     aggregated list of rows ("Ran 4 commands", "Edited 2 files",
//     "Used the browser", …) the same way the Mac does it.
//   - `AssistantTimelineView`: walks the `[WireTimelineEntry]` and
//     renders each `.reasoning` chunk as text and each `.tools` group
//     as a `ToolGroupRowsView` (aggregate rows for that group only).
//   - `ToolGroupRowsView`: per-tool-group aggregate rows.
//
// We intentionally keep the visual language simple (SF Symbols, plain
// text). The point is fidelity of CONTENT, not the bespoke iconography
// the desktop has. Matches Tarea: "paridad completa con Mac".

// MARK: - Public entry point

struct AssistantTimelineView: View {
    let timeline: [WireTimelineEntry]
    let workSummary: WireWorkSummary?
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary = workSummary,
               !summary.items.isEmpty,
               summary.endedAt != nil || isStreaming {
                WorkSummaryHeaderView(summary: summary, isStreaming: isStreaming)
            }

            ForEach(Array(timeline.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .reasoning(_, let text):
                    if !text.isEmpty {
                        Text(text)
                            .font(Typography.bodyFont)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineSpacing(3)
                    }
                case .tools(_, let items):
                    ToolGroupRowsView(items: items)
                }
            }
        }
    }
}

// MARK: - Work summary header

private struct WorkSummaryHeaderView: View {
    let summary: WireWorkSummary
    let isStreaming: Bool
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            disclosure
            if expanded {
                let rows = aggregateForSummary(summary.items)
                if rows.isEmpty {
                    Text("No actions recorded")
                        .font(Typography.captionFont)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            ToolRowView(row: row)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.borderSubtle)
                .frame(height: 0.5)
        }
        .padding(.bottom, 6)
    }

    private var disclosure: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                expanded.toggle()
            }
        } label: {
            TimelineView(.periodic(from: .now, by: isStreaming ? 1.0 : 3600)) { ctx in
                HStack(spacing: 6) {
                    Text(headerText(now: ctx.date))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private func headerText(now: Date) -> String {
        let end = summary.endedAt ?? now
        let seconds = max(0, Int(end.timeIntervalSince(summary.startedAt).rounded()))
        if isStreaming {
            return "Working for \(seconds)s"
        }
        return "Worked for \(seconds)s"
    }
}

// MARK: - Per-group rows

struct ToolGroupRowsView: View {
    let items: [WireWorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(runningCommands, id: \.id) { item in
                if let text = item.commandText, !text.isEmpty {
                    InlineRow(prefix: "Running", text: text, shimmer: true)
                }
            }
            ForEach(aggregateForGroup(items)) { row in
                ToolRowView(row: row)
            }
        }
    }

    private var runningCommands: [WireWorkItem] {
        items.filter { $0.kind == "command" && $0.status == .inProgress }
    }
}

private struct InlineRow: View {
    let prefix: String
    let text: String
    let shimmer: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TerminalIcon(size: 13)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 16, alignment: .leading)
            Text(prefix + " " + text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .opacity(shimmer ? 0.7 : 1.0)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Aggregation

struct ToolRow: Identifiable {
    let id: String
    let systemImage: String
    let text: String
}

private struct ToolRowView: View {
    let row: ToolRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ToolRowIcon(systemImage: row.systemImage)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 16, alignment: .leading)
            Text(row.text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Resolves the aggregate-row icon name to either a custom Clawix icon
/// (matching the macOS work-summary glyphs) or, when no custom glyph
/// exists yet, falls back to the original SF Symbol.
private struct ToolRowIcon: View {
    let systemImage: String

    var body: some View {
        switch systemImage {
        case "magnifyingglass", "magnifyingglass.circle":
            SearchIcon(size: 12)
        case "terminal":
            TerminalIcon(size: 13)
        case "list.bullet":
            FolderStackIcon(size: 14)
        case "globe":
            GlobeIcon(size: 13)
        case "safari":
            CursorIcon(size: 13)
        case "puzzlepiece.extension":
            McpIcon(size: 13)
        case "pencil":
            PencilIconView(color: Palette.textTertiary, lineWidth: 1.0)
                .frame(width: 14, height: 14)
        default:
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
        }
    }
}

/// Per-`.tools` group aggregation: how a single timeline tools entry
/// flattens into rows ("Ran 3 commands", "Edited 2 files", …).
/// Mirrors the macOS `ToolGroupView` aggregation.
private func aggregateForGroup(_ items: [WireWorkItem]) -> [ToolRow] {
    var rows: [ToolRow] = []
    var readFiles = 0
    var listed = 0
    var searchedItems = 0
    var ranCommands = 0
    var fileChanges = 0
    var browserUsed = false
    var webSearchCount = 0
    var mcpServers: [String] = []
    var dynamicTools: [String] = []
    var imageGenerations = 0
    var imageViews = 0

    for item in items {
        switch item.kind {
        case "command":
            if item.status == .inProgress { continue }
            let actions = item.commandActions ?? []
            let reads = actions.filter { $0 == "read" }.count
            let lists = actions.filter { $0 == "listFiles" }.count
            let searches = actions.filter { $0 == "search" }.count
            if reads + lists + searches > 0 {
                readFiles += reads
                listed += lists
                searchedItems += searches
            } else {
                ranCommands += 1
            }
        case "fileChange":
            fileChanges += max(1, item.paths?.count ?? 0)
        case "webSearch":
            webSearchCount += 1
        case "mcpTool":
            if let s = item.mcpServer, !s.isEmpty, !mcpServers.contains(s) {
                mcpServers.append(s)
            }
        case "dynamicTool":
            let name = item.dynamicToolName ?? ""
            let lower = name.lowercased()
            if lower.contains("browser") {
                browserUsed = true
            } else if lower.contains("web") {
                webSearchCount += 1
            } else if !name.isEmpty {
                dynamicTools.append(name)
            }
        case "imageGeneration":
            imageGenerations += 1
        case "imageView":
            imageViews += 1
        default:
            break
        }
    }

    if readFiles > 0 {
        rows.append(.init(id: "read", systemImage: "magnifyingglass", text: pluralize("Read \(readFiles) file", count: readFiles)))
    }
    if listed > 0 {
        rows.append(.init(id: "list", systemImage: "list.bullet", text: pluralize("Listed \(listed) directory", count: listed, plural: "Listed \(listed) directories")))
    }
    if searchedItems > 0 {
        rows.append(.init(id: "search", systemImage: "magnifyingglass.circle", text: pluralize("Searched \(searchedItems) time", count: searchedItems)))
    }
    if ranCommands > 0 {
        rows.append(.init(id: "ran", systemImage: "terminal", text: pluralize("Ran \(ranCommands) command", count: ranCommands)))
    }
    if fileChanges > 0 {
        rows.append(.init(id: "edit", systemImage: "pencil", text: pluralize("Edited \(fileChanges) file", count: fileChanges)))
    }
    if browserUsed {
        rows.append(.init(id: "browser", systemImage: "safari", text: "Used the browser"))
    }
    if webSearchCount > 0 {
        rows.append(.init(id: "web", systemImage: "globe", text: webSearchCount == 1 ? "Searched the web" : "Searched the web \(webSearchCount) times"))
    }
    for (idx, server) in mcpServers.enumerated() {
        rows.append(.init(id: "mcp\(idx)", systemImage: "puzzlepiece.extension", text: "Used \(prettyMcp(server))"))
    }
    for (idx, name) in dynamicTools.enumerated() {
        rows.append(.init(id: "dyn\(idx)", systemImage: "wrench.and.screwdriver", text: "Used \(name)"))
    }
    if imageGenerations > 0 {
        rows.append(.init(id: "imgGen", systemImage: "photo", text: pluralize("Generated \(imageGenerations) image", count: imageGenerations)))
    }
    if imageViews > 0 {
        rows.append(.init(id: "imgView", systemImage: "eye", text: pluralize("Viewed \(imageViews) image", count: imageViews)))
    }
    return rows
}

/// Whole-turn aggregation for the `WorkSummary` disclosure header.
/// Combines reads + non-read commands into a single row to match the
/// macOS phrasing.
private func aggregateForSummary(_ items: [WireWorkItem]) -> [ToolRow] {
    var rows: [ToolRow] = []
    var readFiles = 0
    var nonReadCommands = 0
    var fileChanges = 0
    var browserUsed = false
    var webSearchCount = 0
    var mcpServers: [String] = []
    var dynamicTools: [String] = []
    var imageGenerations = 0
    var imageViews = 0

    for item in items {
        switch item.kind {
        case "command":
            let actions = item.commandActions ?? []
            let exploratory = actions.contains(where: { $0 == "read" || $0 == "listFiles" || $0 == "search" })
            if exploratory {
                readFiles += max(1, actions.filter { $0 == "read" }.count)
            } else {
                nonReadCommands += 1
            }
        case "fileChange":
            fileChanges += max(1, item.paths?.count ?? 0)
        case "webSearch":
            webSearchCount += 1
        case "mcpTool":
            if let s = item.mcpServer, !s.isEmpty, !mcpServers.contains(s) {
                mcpServers.append(s)
            }
        case "dynamicTool":
            let lower = (item.dynamicToolName ?? "").lowercased()
            if lower.contains("browser") {
                browserUsed = true
            } else if lower.contains("web") {
                webSearchCount += 1
            } else if let name = item.dynamicToolName, !name.isEmpty {
                dynamicTools.append(name)
            }
        case "imageGeneration":
            imageGenerations += 1
        case "imageView":
            imageViews += 1
        default:
            break
        }
    }

    if readFiles > 0 || nonReadCommands > 0 {
        var parts: [String] = []
        if readFiles > 0 {
            parts.append(pluralize("Explored \(readFiles) file", count: readFiles))
        }
        if nonReadCommands > 0 {
            parts.append(pluralize("Ran \(nonReadCommands) command", count: nonReadCommands))
        }
        let icon = readFiles > 0 ? "magnifyingglass" : "terminal"
        rows.append(.init(id: "exec", systemImage: icon, text: parts.joined(separator: ", ")))
    }
    if fileChanges > 0 {
        rows.append(.init(id: "edit", systemImage: "pencil", text: pluralize("Modified \(fileChanges) file", count: fileChanges)))
    }
    if browserUsed {
        rows.append(.init(id: "browser", systemImage: "safari", text: "Used the browser"))
    }
    if webSearchCount > 0 {
        let text = webSearchCount == 1 ? "Searched the web" : "Searched the web \(webSearchCount) times"
        rows.append(.init(id: "web", systemImage: "globe", text: text))
    }
    for (idx, server) in mcpServers.enumerated() {
        rows.append(.init(id: "mcp\(idx)", systemImage: "puzzlepiece.extension", text: "Used \(prettyMcp(server))"))
    }
    for (idx, name) in dynamicTools.enumerated() {
        rows.append(.init(id: "dyn\(idx)", systemImage: "wrench.and.screwdriver", text: "Used \(name)"))
    }
    if imageGenerations > 0 {
        rows.append(.init(id: "imgGen", systemImage: "photo", text: pluralize("Generated \(imageGenerations) image", count: imageGenerations)))
    }
    if imageViews > 0 {
        rows.append(.init(id: "imgView", systemImage: "eye", text: pluralize("Viewed \(imageViews) image", count: imageViews)))
    }
    return rows
}

// MARK: - File-change pills (after the assistant body)

struct ChangedFilePills: View {
    let timeline: [WireTimelineEntry]

    var body: some View {
        let paths = changedFilePaths(in: timeline)
        if !paths.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(paths, id: \.self) { path in
                    ChangedFilePill(path: path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChangedFilePill: View {
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            FileChipIcon(size: 16)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.cardFill)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(path)
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.cardFill)
        )
    }
}

func changedFilePaths(in timeline: [WireTimelineEntry]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for entry in timeline {
        guard case .tools(_, let items) = entry else { continue }
        for item in items where item.kind == "fileChange" {
            for path in (item.paths ?? []) where seen.insert(path).inserted {
                result.append(path)
            }
        }
    }
    return result
}

// MARK: - Helpers

private func pluralize(_ singularPhrase: String, count: Int, plural: String? = nil) -> String {
    if count == 1 { return singularPhrase }
    if let plural { return plural }
    // crude fallback: append 's' to the last word ("file" → "files").
    return singularPhrase + "s"
}

private func prettyMcp(_ server: String) -> String {
    server.replacingOccurrences(of: "_", with: " ").capitalized
}
