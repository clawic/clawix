import SwiftUI

// Elapsed-time disclosure that sits above the assistant reply. While
// the turn is running the seconds counter ticks live; once the turn
// completes the duration freezes and clicking the chevron reveals a
// small list summarizing what the agent actually did (commands, file
// reads, browser, …) — the same rows Clawix shows.

struct WorkSummaryHeader: View {
    let summary: WorkSummary

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            disclosure
            if expanded {
                let rows = aggregate(summary.items)
                if rows.isEmpty {
                    Text("No actions recorded")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(white: 0.42))
                        .padding(.leading, 2)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            WorkRowView(row: row)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(height: 0.5)
        }
        .padding(.bottom, 6)
    }

    private var disclosure: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
        } label: {
            // Live-updating label: TimelineView re-renders once a second
            // while the turn is active, then freezes when endedAt is set.
            TimelineView(.periodic(from: .now, by: summary.isActive ? 1.0 : 3600)) { ctx in
                HStack(spacing: 6) {
                    Text(headerText(now: ctx.date))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(white: 0.55))
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.42))
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Work summary")
    }

    private func headerText(now: Date) -> String {
        let s = summary.elapsedSeconds(asOf: now)
        return summary.isActive ? L10n.workingFor(seconds: s) : L10n.workedFor(seconds: s)
    }
}

// MARK: - Aggregation

/// One row in the expanded summary. Several `WorkItem`s of the same
/// family collapse into one row (e.g. three `commandExecution` items
/// with read actions become "Se han explorado 3 archivos").
private struct WorkRow: Identifiable {
    let id: String
    let icon: String
    let text: String
}

private func aggregate(_ items: [WorkItem]) -> [WorkRow] {
    var rows: [WorkRow] = []

    var readFiles = 0
    var nonReadCommands = 0
    var fileChanges = 0
    var browserUsed = false
    var mcpTools: [(server: String, tool: String)] = []
    var dynamicTools: [String] = []
    var imageGenerations = 0
    var imageViews = 0

    for item in items {
        switch item.kind {
        case .command(_, let actions):
            // A single shell command may chain pipes; if any action is a
            // "read"/"listFiles"/"search" the user perceives it as
            // exploration, otherwise as a generic command.
            let exploratory = actions.contains { $0 == .read || $0 == .listFiles || $0 == .search }
            if exploratory {
                readFiles += max(1, actions.filter { $0 == .read }.count)
            } else {
                nonReadCommands += 1
            }
        case .fileChange(let count):
            fileChanges += max(1, count)
        case .webSearch:
            browserUsed = true
        case .mcpTool(let server, let tool):
            mcpTools.append((server, tool))
        case .dynamicTool(let name):
            // Clawix's own browser surfaces as a dynamic tool too; group it
            // visually with `webSearch` instead of listing it raw.
            let lower = name.lowercased()
            if lower.contains("browser") || lower.contains("web") {
                browserUsed = true
            } else {
                dynamicTools.append(name)
            }
        case .imageGeneration:
            imageGenerations += 1
        case .imageView:
            imageViews += 1
        }
    }

    // If both reads and other commands happened, surface them on a
    // single comma-joined row to match the compact phrasing.
    if readFiles > 0 || nonReadCommands > 0 {
        var parts: [String] = []
        if readFiles > 0 {
            parts.append(L10n.exploredFiles(readFiles))
        }
        if nonReadCommands > 0 {
            parts.append(L10n.ranCommands(nonReadCommands))
        }
        rows.append(WorkRow(id: "exec", icon: "shippingbox", text: parts.joined(separator: ", ")))
    }
    if fileChanges > 0 {
        rows.append(WorkRow(
            id: "fileChange",
            icon: "doc.text",
            text: L10n.modifiedFiles(fileChanges)
        ))
    }
    if browserUsed {
        rows.append(WorkRow(
            id: "browser",
            icon: "cursorarrow",
            text: String(localized: "Se han usado the browser", bundle: AppLocale.bundle, locale: AppLocale.current)
        ))
    }
    for (idx, mcp) in mcpTools.enumerated() {
        let label = mcp.server.isEmpty ? mcp.tool : "\(mcp.server) · \(mcp.tool)"
        rows.append(WorkRow(id: "mcp\(idx)", icon: "puzzlepiece.extension", text: L10n.usedTool(label)))
    }
    for (idx, name) in dynamicTools.enumerated() {
        rows.append(WorkRow(id: "dyn\(idx)", icon: "wrench.and.screwdriver", text: L10n.usedTool(name)))
    }
    if imageGenerations > 0 {
        rows.append(WorkRow(
            id: "imgGen",
            icon: "photo",
            text: L10n.generatedImages(imageGenerations)
        ))
    }
    if imageViews > 0 {
        rows.append(WorkRow(
            id: "imgView",
            icon: "eye",
            text: L10n.viewedImages(imageViews)
        ))
    }
    return rows
}

private struct WorkRowView: View {
    let row: WorkRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: row.icon)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.42))
                .frame(width: 16, alignment: .leading)
            Text(row.text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.50))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
