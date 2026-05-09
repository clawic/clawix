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

    private var aggregateRows: [ToolTimelineRow] {
        ToolTimelinePresentation.aggregateRows(for: items)
    }

    private func aggregateRow(_ row: ToolTimelineRow) -> some View {
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
                case "clawix.computerUse":
                    LucideIcon(.appWindow, size: 13)
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
                    LucideIcon.auto(row.icon, size: 12)
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
