import SwiftUI

// MARK: - Slash command catalog

struct SlashCommand: Identifiable, Equatable {
    let id: String
    let label: String
    let description: String?
    let iconName: String
    let gatedFeature: AppFeature?

    init(
        id: String,
        label: String,
        description: String?,
        iconName: String,
        gatedFeature: AppFeature? = nil
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.iconName = iconName
        self.gatedFeature = gatedFeature
    }
}

enum SlashCommandCatalog {
    static let all: [SlashCommand] = [
        SlashCommand(id: "chat",
                     label: "Chat",
                     description: "Don’t work on a project",
                     iconName: "bubble.left"),
        SlashCommand(id: "estado",
                     label: "Status",
                     description: "Show chat ID, context usage and rate limits",
                     iconName: "gauge.medium"),
        SlashCommand(id: "mcp",
                     label: "MCP",
                     description: "Show MCP server status",
                     iconName: "paperclip",
                     gatedFeature: .mcp),
        SlashCommand(id: "modelo",
                     label: "Model",
                     description: "GPT-5.5",
                     iconName: "cube"),
        SlashCommand(id: "modo-plan",
                     label: "Plan mode",
                     description: "Enable plan mode",
                     iconName: "checklist"),
        SlashCommand(id: "opinion",
                     label: "Feedback",
                     description: nil,
                     iconName: "ellipsis.message"),
        SlashCommand(id: "personalidad",
                     label: "Personality",
                     description: nil,
                     iconName: "person.crop.circle",
                     gatedFeature: .agents),
        SlashCommand(id: "proyecto",
                     label: "Project",
                     description: "Select project for new chats",
                     iconName: "folder"),
        SlashCommand(id: "razonamiento",
                     label: "Reasoning",
                     description: "High",
                     iconName: "brain"),
        SlashCommand(id: "revisar-codigo",
                     label: "Review code",
                     description: nil,
                     iconName: "alarm"),
        SlashCommand(id: "rapido",
                     label: "Fast",
                     description: "Speed up inference across chats, subagents and compaction. Uses more of your plan quota.",
                     iconName: "bolt")
    ]

    static func filter(_ query: String, isVisible: (AppFeature) -> Bool) -> [SlashCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = all.filter { cmd in
            guard let feature = cmd.gatedFeature else { return true }
            return isVisible(feature)
        }
        guard !trimmed.isEmpty else { return visible }
        return visible.filter { cmd in
            cmd.id.lowercased().hasPrefix(trimmed)
                || cmd.label.lowercased().hasPrefix(trimmed)
                || cmd.label.lowercased().contains(trimmed)
        }
    }
}

// MARK: - Menu view

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let highlightedID: String?
    let onSelect: (SlashCommand) -> Void
    let onHover: (SlashCommand) -> Void


    var body: some View {
        Group {
            if commands.isEmpty {
                Text("No matches")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(MenuStyle.headerText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                ThinScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commands) { cmd in
                            SlashCommandRow(
                                command: cmd,
                                isHighlighted: cmd.id == highlightedID,
                                onTap: { onSelect(cmd) },
                                onHover: { onHover(cmd) }
                            )
                        }
                    }
                    .padding(.vertical, MenuStyle.menuVerticalPadding)
                }
            }
        }
        .frame(maxHeight: 340)
        .menuStandardBackground()
    }
}

private struct SlashCommandRow: View {
    let command: SlashCommand
    let isHighlighted: Bool
    let onTap: () -> Void
    let onHover: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                IconImage(command.iconName, size: 12)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 14, alignment: .center)

                Text(command.label)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Color(white: 0.86))
                    .fixedSize(horizontal: true, vertical: false)

                if let desc = command.description {
                    Text(desc)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(MenuStyle.rowSubtle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 2)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered || isHighlighted))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering { onHover() }
        }
    }
}
