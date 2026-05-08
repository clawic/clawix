import SwiftUI
import ClawixCore
import LucideIcon

// iOS-side rendering of an assistant message's chronological timeline,
// mirroring what the macOS app shows. Behavior parity with Mac:
//
//   - While the turn is streaming, every reasoning chunk and tool
//     group renders inline so the user watches the agent's work
//     accumulate in real time.
//   - The instant `streamingFinished` flips, the whole timeline
//     collapses behind the "Worked for Xs" header. Only the assistant's
//     final reply (rendered by the parent `MessageView`) stays visible.
//   - Tapping the header chevron expands the timeline back, revealing
//     every intermediate reasoning chunk and tool call.
//
// We intentionally keep the visual language simple (SF Symbols, plain
// text). The point is fidelity of CONTENT, not the bespoke iconography
// the desktop has.

// MARK: - Public entry point

struct AssistantTimelineView: View {
    let timeline: [WireTimelineEntry]
    let workSummary: WireWorkSummary?
    let isStreaming: Bool

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary = workSummary,
               !summary.items.isEmpty,
               summary.endedAt != nil || isStreaming {
                WorkSummaryHeaderView(
                    summary: summary,
                    isStreaming: isStreaming,
                    expanded: $expanded
                )
            }

            // Mac parity: timeline entries are visible while streaming
            // (the user watches the agent work) or when the user has
            // tapped the header to reveal the hidden history. Otherwise
            // they collapse so only the final answer remains.
            if isStreaming || expanded {
                ForEach(Array(timeline.enumerated()), id: \.offset) { _, entry in
                    switch entry {
                    case .reasoning(_, let text):
                        if !text.isEmpty {
                            Text(text)
                                .font(Typography.chatBodyFont)
                                .foregroundStyle(Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineSpacing(3)
                        }
                    case .message(_, let text):
                        if !text.isEmpty {
                            Text(text)
                                .font(Typography.chatBodyFont)
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
}

// MARK: - Work summary header

private struct WorkSummaryHeaderView: View {
    let summary: WireWorkSummary
    let isStreaming: Bool
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            disclosure
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
            // While streaming the timeline is forced visible, so the
            // chevron is a no-op until the turn ends. Matches Mac,
            // which swaps the live header out for the disclosure header
            // only on `turn/completed`.
            guard !isStreaming else { return }
            Haptics.tap()
            withAnimation(.easeOut(duration: 0.16)) {
                expanded.toggle()
            }
        } label: {
            // While streaming, the elapsed-seconds string ticks once a
            // second via `TimelineView`. After the turn ends, the
            // header is static, so we drop the TimelineView entirely
            // rather than parking it at a 1-hour cadence: SwiftUI no
            // longer keeps a CADisplayLink wired up for a label that
            // never changes again.
            if isStreaming {
                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    HStack(spacing: 6) {
                        Text(headerText(now: ctx.date))
                            .font(BodyFont.system(size: 13, weight: .regular))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
            } else {
                HStack(spacing: 6) {
                    Text(headerText(now: Date()))
                        .font(BodyFont.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                    Image(lucide: .chevron_right)
                        .font(BodyFont.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.easeOut(duration: 0.16), value: expanded)
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
                .font(BodyFont.system(size: 13))
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
                .font(BodyFont.system(size: 13))
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
            Image(lucideOrSystem: systemImage)
                .font(BodyFont.system(size: 12, weight: .regular))
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

// MARK: - File-change pills (after the assistant body)

struct ChangedFilePills: View {
    let timeline: [WireTimelineEntry]
    var onOpen: (String) -> Void = { _ in }

    var body: some View {
        let paths = changedFilePaths(in: timeline)
        if !paths.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(paths, id: \.self) { path in
                    ChangedFilePill(path: path, onOpen: { onOpen(path) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChangedFilePill: View {
    let path: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            onOpen()
        }) {
            HStack(spacing: 8) {
                FileChipIcon(size: 14)
                    .foregroundStyle(Palette.textSecondary)
                Text((path as NSString).lastPathComponent)
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
