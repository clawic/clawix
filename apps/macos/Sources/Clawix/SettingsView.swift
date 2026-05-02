import SwiftUI

// MARK: - Settings categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case configuration
    case personalization
    case mcp
    case git
    case environments
    case worktrees
    case browserUsage
    case archivedChats
    case usage

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:          return "General"
        case .appearance:       return "Appearance"
        case .configuration:    return "Settings"
        case .personalization:  return "Personalization"
        case .mcp:              return "MCP servers"
        case .git:              return "Git"
        case .environments:     return "Environments"
        case .worktrees:        return "Worktrees"
        case .browserUsage:     return "Browser usage"
        case .archivedChats:    return "Chats archivados"
        case .usage:            return "Uso"
        }
    }

    var iconName: String {
        switch self {
        case .general:          return "house"
        case .appearance:       return "circle.lefthalf.filled"
        case .configuration:    return "slider.horizontal.3"
        case .personalization:  return "person.crop.circle"
        case .mcp:              return "server.rack"
        case .git:              return "arrow.triangle.branch"
        case .environments:     return "macwindow"
        case .worktrees:        return "rectangle.stack"
        case .browserUsage:     return "globe"
        case .archivedChats:    return "archivebox"
        case .usage:            return "chart.bar"
        }
    }
}

// MARK: - Settings sidebar (replaces the chat sidebar while in .settings)

struct SettingsSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var backHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                appState.currentRoute = .home
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16, alignment: .center)
                    Text("Back to app")
                        .font(.system(size: 13))
                    Spacer(minLength: 10)
                }
                .foregroundColor(Color(white: 0.78))
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(backHovered ? Color.white.opacity(0.05) : .clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { backHovered = $0 }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 14)

            VStack(spacing: 1) {
                ForEach(SettingsCategory.allCases) { cat in
                    SettingsSidebarRow(category: cat)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
    }
}

private struct SettingsSidebarRow: View {
    let category: SettingsCategory
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    private var isSelected: Bool { appState.settingsCategory == category }

    var body: some View {
        Button {
            appState.settingsCategory = category
        } label: {
            HStack(spacing: 15) {
                IconImage(category.iconName, size: 13)
                    .frame(width: 16, alignment: .center)
                    .foregroundColor(isSelected ? .white : Color(white: 0.78))
                Text(category.title)
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(isSelected ? .white : Color(white: 0.88))
                Spacer(minLength: 10)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.white.opacity(0.07) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}

// MARK: - Settings content router (right column)

struct SettingsContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch appState.settingsCategory {
                    case .general:         GeneralPage()
                    case .appearance:      AppearancePage()
                    case .configuration:   ConfigurationPage()
                    case .personalization: PersonalizationPage()
                    case .git:             GitPage()
                    case .environments:    EnvironmentsPage()
                    case .browserUsage:    BrowserUsagePage()
                    case .archivedChats:   ArchivedChatsPage()
                    case .usage:           UsagePage()
                    case .mcp:             MCPPage()
                    default:               PlaceholderPage(category: appState.settingsCategory)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.background)
    }
}

// MARK: - Shared building blocks

private struct PageHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.bottom, 26)
    }
}

private struct SectionLabel: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Palette.textPrimary)
            .padding(.bottom, 14)
            .padding(.top, 28)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

private struct RowLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ToggleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            PillToggle(isOn: $isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct PillToggle: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 34
    private let trackHeight: CGFloat = 20
    private let knobSize: CGFloat = 16
    private let inset: CGFloat = 2

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn
                          ? Color(red: 0.16, green: 0.46, blue: 0.98)
                          : Color(white: 0.22))
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .padding(.horizontal, inset)
                    .shadow(color: .black.opacity(0.20), radius: 1, x: 0, y: 1)
            }
            .frame(width: trackWidth, height: trackHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}

private struct DropdownRow<T: Hashable>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let options: [(T, String)]
    @Binding var selection: T
    var iconForOption: ((T) -> AnyView?)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            SettingsDropdown(
                options: options,
                selection: $selection,
                iconForOption: iconForOption
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Canonical settings/config dropdown. Wide capsule trigger with a clearly
/// visible dark fill, optional leading glyph and a chevron on the right.
/// The popup uses the project-wide menu chrome via `menuStandardBackground()`
/// (anchorPreference + softNudge transition), never SwiftUI's `Menu` or
/// `.popover`, so it never inherits system arrows or chrome.
/// Uses the project-wide dropdown menu style.
struct SettingsDropdown<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var iconForOption: ((T) -> AnyView?)? = nil
    var minWidth: CGFloat = 240

    @State private var isOpen = false
    @State private var hovered = false

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 10) {
                if let icon = iconForOption?(selection) {
                    icon
                }
                Text(currentLabel)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: minWidth, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(hovered || isOpen
                          ? Color(white: 0.165)
                          : Color(white: 0.135))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .anchorPreference(key: SettingsDropdownAnchorKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(SettingsDropdownAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if isOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    SettingsDropdownPopup(
                        options: options,
                        selection: $selection,
                        isOpen: $isOpen,
                        iconForOption: iconForOption,
                        minWidth: buttonFrame.width
                    )
                    .offset(x: buttonFrame.minX, y: buttonFrame.maxY + 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(isOpen)
        }
        .animation(MenuStyle.openAnimation, value: isOpen)
    }
}

private struct SettingsDropdownAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct SettingsDropdownPopup<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Binding var isOpen: Bool
    var iconForOption: ((T) -> AnyView?)? = nil
    let minWidth: CGFloat

    @State private var hoveredIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                Button {
                    selection = opt.0
                    isOpen = false
                } label: {
                    HStack(spacing: 10) {
                        if let icon = iconForOption?(opt.0) {
                            icon
                        }
                        Text(opt.1)
                            .font(.system(size: 12.5))
                            .foregroundColor(MenuStyle.rowText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if opt.0 == selection {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(MenuStyle.rowText)
                        }
                    }
                    .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                    .padding(.vertical, MenuStyle.rowVerticalPadding)
                    .background(MenuRowHover(active: hoveredIndex == idx))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { hoveredIndex = idx }
                    else if hoveredIndex == idx { hoveredIndex = nil }
                }
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isOpen))
    }
}

/// Resolves an app icon view for known "open with" targets. Returns nil when
/// the option name isn't a recognised app, so the dropdown row falls back to
/// a plain text trigger.
private func openTargetIcon(for name: String) -> AnyView? {
    let map: [String: (String, String)] = [
        "Ghostty":  ("com.mitchellh.ghostty",
                     "/Applications/Ghostty.app"),
        "Terminal": ("com.apple.Terminal",
                     "/System/Applications/Utilities/Terminal.app"),
        "VS Code":  ("com.microsoft.VSCode",
                     "/Applications/Visual Studio Code.app"),
        "Cursor":   ("com.todesktop.230313mzl4w4u92",
                     "/Applications/Cursor.app"),
        "Finder":   ("com.apple.finder",
                     "/System/Library/CoreServices/Finder.app"),
        "Xcode":    ("com.apple.dt.Xcode",
                     "/Applications/Xcode.app"),
    ]
    guard let entry = map[name] else { return nil }
    return AnyView(
        AppIconImage(bundleId: entry.0, fallbackPath: entry.1, size: 18)
    )
}

private struct SegmentedRow<T: Hashable>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    let isOn = opt.0 == selection
                    Button {
                        selection = opt.0
                    } label: {
                        Text(opt.1)
                            .font(.system(size: 12, weight: isOn ? .medium : .regular))
                            .foregroundColor(isOn ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isOn ? Color.white.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ActionPillRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let primaryLabel: LocalizedStringKey
    var trailingDisabled: LocalizedStringKey? = nil
    let onPrimary: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if let trailingDisabled {
                    Text(trailingDisabled)
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - General page

private struct GeneralPage: View {
    @EnvironmentObject var appState: AppState
    @State private var workMode: WorkMode = .daily
    @State private var permDefault: Bool = true
    @State private var permAuto: Bool = true
    @State private var permFull: Bool = true
    @State private var openTarget: String = "Ghostty"
    @State private var showInMenuBar: Bool = true
    @State private var preventSleep: Bool = true
    @State private var requireCmdEnter: Bool = false
    @State private var speed: String = "Standard"
    @State private var followBehavior: FollowBehavior = .queue
    @State private var codeReview: CodeReview = .inline
    @State private var dictionaryEntries: [String] = ["Jane Doe"]
    @State private var recentDictations: [(stamp: String, text: String)] = [
        ("May 1, 11:42", "OK, this is a test, let's see how it works."),
        ("May 1, 11:35", "Hi, just testing how this works.")
    ]
    @State private var completionNotify: String = "Siempre"
    @State private var permissionNotify: Bool = true
    @State private var questionNotify: Bool = true

    enum WorkMode: Hashable { case coding, daily }
    enum FollowBehavior: Hashable { case queue, drive }
    enum CodeReview: Hashable { case inline, detached }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "General")

            Text("Work mode")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            Text("Choose how much technical detail Clawix shows")
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            HStack(spacing: 12) {
                WorkModeCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "For coding",
                    subtitle: "More technical responses and finer control",
                    isOn: workMode == .coding
                ) { workMode = .coding }
                WorkModeCard(
                    icon: "bubble.left.and.bubble.right",
                    title: "For daily work",
                    subtitle: "Same power, fewer technical details...",
                    isOn: workMode == .daily
                ) { workMode = .daily }
            }
            .padding(.bottom, 4)

            SectionLabel(title: "Permissions")
            SettingsCard {
                ToggleRow(
                    title: "Default permissions",
                    detail: "By default, Clawix can read and edit files in your workspace. It can request additional access when needed.",
                    isOn: $permDefault
                )
                CardDivider()
                ToggleRow(
                    title: "Automatic review",
                    detail: "Clawix can read and edit files in your workspace. Clawix automatically reviews requests for additional access. Auto-review may make mistakes. Learn more about the elevated risks.",
                    isOn: $permAuto
                )
                CardDivider()
                ToggleRow(
                    title: "Full access",
                    detail: "When Clawix runs with full access, it can edit any file on your computer and run commands over the network without your authorization. This significantly increases the risk of data loss, leaks, or unexpected behavior. Learn more about the elevated risks.",
                    isOn: $permFull
                )
            }

            SectionLabel(title: "General")
            SettingsCard {
                DropdownRow(
                    title: "Default open destination",
                    detail: "Where files and folders open by default",
                    options: [("Ghostty", "Ghostty"), ("Terminal", "Terminal"), ("VS Code", "VS Code")],
                    selection: $openTarget,
                    iconForOption: { openTargetIcon(for: $0) }
                )
                CardDivider()
                DropdownRow(
                    title: "Idioma",
                    detail: "App interface language",
                    options: AppLanguage.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { appState.preferredLanguage },
                        set: { appState.preferredLanguage = $0 }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Show in the menu bar",
                    detail: "Keep Clawix in the macOS menu bar when the main window closes",
                    isOn: $showInMenuBar
                )
                CardDivider()
                ActionPillRow(
                    title: "Popover keyboard shortcut",
                    detail: "Set a global keyboard shortcut for the popover. Leave empty to keep it disabled.",
                    primaryLabel: "Change",
                    trailingDisabled: "⌥Space",
                    onPrimary: {}
                )
                CardDivider()
                ToggleRow(
                    title: "Prevent sleep during execution",
                    detail: "Keep the computer awake while Clawix is running a chat",
                    isOn: $preventSleep
                )
                CardDivider()
                ToggleRow(
                    title: "Require ⌘ + Return to send long prompts",
                    detail: "When enabled, multi-line prompts require ⌘ + Return to send.",
                    isOn: $requireCmdEnter
                )
                CardDivider()
                DropdownRow(
                    title: "Speed",
                    detail: "Choose how fast inference runs in chats, sub-agents and compaction. Fast uses more of the plan",
                    options: [
                        ("Standard", "Standard"),
                        ("Fast", "Fast"),
                        ("Auto", "Auto")
                    ],
                    selection: $speed
                )
                CardDivider()
                SegmentedRow(
                    title: "Follow-up behavior",
                    detail: "Queue follow-up messages while Clawix runs, or steer the current run. Press ⌘Return to do the opposite for a single message.",
                    options: [(.queue, "Cola"), (.drive, "Dirigir")],
                    selection: $followBehavior
                )
                CardDivider()
                SegmentedRow(
                    title: "Code review",
                    detail: "Start /review in the current chat when possible, or open a separate review chat",
                    options: [(.inline, "En línea"), (.detached, "Desvinculado")],
                    selection: $codeReview
                )
                CardDivider()
                ImportAgentRow()
            }

            SectionLabel(title: "Dictado")
            SettingsCard {
                ActionPillRow(
                    title: "Push-to-dictate keyboard shortcut",
                    detail: "Hold down anywhere on the desktop to dictate where the cursor is",
                    primaryLabel: "Establecer",
                    trailingDisabled: "Off",
                    onPrimary: {}
                )
                CardDivider()
                ActionPillRow(
                    title: "Toggle dictation keyboard shortcut",
                    detail: "Press once anywhere on the desktop to dictate, press again to stop",
                    primaryLabel: "Establecer",
                    trailingDisabled: "Off",
                    onPrimary: {}
                )
                CardDivider()
                DictionaryExpandableRow(entries: $dictionaryEntries)
                ForEach(Array(recentDictations.enumerated()), id: \.offset) { _, item in
                    CardDivider()
                    RecentDictationRow(stamp: item.stamp, text: item.text)
                }
            }

            SectionLabel(title: "Notificaciones")
            SettingsCard {
                DropdownRow(
                    title: "Enable completion notifications",
                    detail: "Set when Clawix notifies you it has finished",
                    options: [
                        ("Siempre", "Siempre"),
                        ("Solo en segundo plano", "Solo en segundo plano"),
                        ("Nunca", "Nunca")
                    ],
                    selection: $completionNotify
                )
                CardDivider()
                ToggleRow(
                    title: "Enable permission notifications",
                    detail: "Show alerts when notification permissions are required",
                    isOn: $permissionNotify
                )
                CardDivider()
                ToggleRow(
                    title: "Enable question notifications",
                    detail: "Show alerts when your input is needed to continue",
                    isOn: $questionNotify
                )
            }
        }
    }
}

private struct WorkModeCard: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.86))
                    .frame(width: 28, height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        .frame(width: 16, height: 16)
                    if isOn {
                        Circle()
                            .fill(Color(red: 0.30, green: 0.55, blue: 1.0))
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 18)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isOn ? Color.white.opacity(0.16) : Color.white.opacity(0.06),
                                    lineWidth: 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ImportAgentRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.86))
                Text("2")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 0.30, green: 0.55, blue: 1.0)))
                    .offset(x: 10, y: 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Import another agent configuration")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                Text("Clawix detected useful preferences from another local agent on this Mac")
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Button {} label: {
                Text("Import")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CollapsibleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @State private var open: Bool = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                RowLabel(title: title, detail: detail)
                Spacer(minLength: 12)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DictionaryExpandableRow: View {
    @Binding var entries: [String]
    @State private var open: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    RowLabel(title: "Dictation dictionary",
                             detail: "Words or phrases dictation should recognize")
                    Spacer(minLength: 12)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 8) {
                    ForEach(entries.indices, id: \.self) { idx in
                        DictionaryEntryField(
                            text: $entries[idx],
                            onDelete: {
                                guard entries.indices.contains(idx) else { return }
                                entries.remove(at: idx)
                            }
                        )
                    }
                    Button {
                        entries.append("")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Add entry")
                                .font(.system(size: 12.5))
                        }
                        .foregroundColor(Color(white: 0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.30))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
}

private struct DictionaryEntryField: View {
    @Binding var text: String
    let onDelete: () -> Void
    @FocusState private var focused: Bool
    @State private var trashHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
                .padding(.leading, 12)
                .padding(.vertical, 9)
            Spacer(minLength: 8)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: trashHovered ? 0.94 : 0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { trashHovered = $0 }
            .padding(.trailing, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(focused
                                ? Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.85)
                                : Color.white.opacity(0.08),
                                lineWidth: focused ? 1.0 : 0.5)
                )
        )
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

private struct RecentDictationRow: View {
    let stamp: String
    let text: String
    @State private var copyHovered: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(stamp)
                .font(.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                withAnimation(.easeOut(duration: 0.12)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.18)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "square.on.square")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: copyHovered ? 0.94 : 0.60))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { copyHovered = $0 }
            .hoverHint("Copy")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Apariencia page

private struct AppearancePage: View {
    @State private var theme: ThemeMode = .system
    @State private var lightAccent: String = "#0169CC"
    @State private var lightBg: String = "#FFFFFF"
    @State private var lightFg: String = "#0D0D0D"
    @State private var lightTranslucent: Bool = true
    @State private var lightContrast: Double = 45
    @State private var darkAccent: String = "#0169CC"
    @State private var darkBg: String = "#111111"
    @State private var darkFg: String = "#FCFCFC"
    @State private var darkTranslucent: Bool = true
    @State private var darkContrast: Double = 57
    @State private var pointerCursors: Bool = false
    @State private var fontSize: String = "14"
    @State private var fontSmoothing: Bool = true

    enum ThemeMode: Hashable { case light, dark, system }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Appearance")

            // Theme switcher card
            SettingsCard {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Theme")
                            .font(.system(size: 13))
                            .foregroundColor(Palette.textPrimary)
                        Text("Use light, dark, or system appearance")
                            .font(.system(size: 11.5))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        ThemeChip(icon: "sun.max", label: "Claro", isOn: theme == .light) { theme = .light }
                        ThemeChip(icon: "moon", label: "Oscuro", isOn: theme == .dark) { theme = .dark }
                        ThemeChip(icon: "laptopcomputer", label: "Sistema", isOn: theme == .system) { theme = .system }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                CardDivider()

                ThemePreviewDiff()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
            .padding(.bottom, 14)

            // Light theme
            ThemeSubSection(
                title: "Light theme",
                accentHex: $lightAccent,
                bgHex: $lightBg,
                fgHex: $lightFg,
                translucent: $lightTranslucent,
                contrast: $lightContrast,
                bgPreview: Color.white,
                fgPreview: Color.black
            )
            .padding(.bottom, 14)

            // Dark theme
            ThemeSubSection(
                title: "Dark theme",
                accentHex: $darkAccent,
                bgHex: $darkBg,
                fgHex: $darkFg,
                translucent: $darkTranslucent,
                contrast: $darkContrast,
                bgPreview: Color(white: 0.07),
                fgPreview: Color.white
            )
            .padding(.bottom, 14)

            SettingsCard {
                ToggleRow(
                    title: "Use pointer cursors",
                    detail: "Switch the cursor to a pointer over interactive elements",
                    isOn: $pointerCursors
                )
                CardDivider()
                FontSizeRow(value: $fontSize)
                CardDivider()
                ToggleRow(
                    title: "Font smoothing",
                    detail: "Use the native macOS font smoothing",
                    isOn: $fontSmoothing
                )
            }
        }
    }
}

private struct ThemeChip: View {
    let icon: String
    let label: LocalizedStringKey
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundColor(isOn ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ThemePreviewDiff: View {
    var body: some View {
        HStack(spacing: 0) {
            DiffSide(
                lines: [
                    (.gutter, "1", "const themePreview: ThemeConfig ="),
                    (.removed, "2", "  surface: \"sidebar\","),
                    (.removed, "3", "  accent: \"#2563eb\","),
                    (.removed, "4", "  contrast: 42,"),
                    (.gutter, "5", "};")
                ],
                isAdd: false
            )
            DiffSide(
                lines: [
                    (.gutter, "1", "const themePreview: ThemeConfig ="),
                    (.added, "2", "  surface: \"sidebar-elevated\","),
                    (.added, "3", "  accent: \"#0ea5e9\","),
                    (.added, "4", "  contrast: 68,"),
                    (.gutter, "5", "};")
                ],
                isAdd: true
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

private enum DiffLineKind { case gutter, added, removed }

private struct DiffSide: View {
    let lines: [(DiffLineKind, String, String)]
    let isAdd: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                let (kind, num, text) = l
                HStack(spacing: 10) {
                    Text(num)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                        .frame(width: 22, alignment: .trailing)
                    Text(text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(textColor(kind: kind))
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(rowBackground(kind: kind))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textColor(kind: DiffLineKind) -> Color {
        switch kind {
        case .gutter:  return Color(white: 0.65)
        case .added:   return Color(red: 0.55, green: 0.95, blue: 0.65)
        case .removed: return Color(red: 1.0, green: 0.55, blue: 0.55)
        }
    }

    private func rowBackground(kind: DiffLineKind) -> Color {
        switch kind {
        case .gutter:  return .clear
        case .added:   return Color(red: 0.10, green: 0.30, blue: 0.15).opacity(0.55)
        case .removed: return Color(red: 0.35, green: 0.10, blue: 0.10).opacity(0.55)
        }
    }
}

private struct ThemeSubSection: View {
    let title: LocalizedStringKey
    @Binding var accentHex: String
    @Binding var bgHex: String
    @Binding var fgHex: String
    @Binding var translucent: Bool
    @Binding var contrast: Double
    let bgPreview: Color
    let fgPreview: Color

    @State private var themeFont: String = "Clawix"

    var body: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Spacer(minLength: 8)
                Text("Import")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                Text("Copy theme")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                SettingsDropdown(
                    options: [("Clawix", "Clawix"), ("Mono", "Mono"), ("Sans", "Sans")],
                    selection: $themeFont,
                    minWidth: 130
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            CardDivider()
            ColorRow(title: "Accent color", hex: $accentHex, swatch: Color(red: 0.0, green: 0.42, blue: 0.85))
            CardDivider()
            ColorRow(title: "Background color", hex: $bgHex, swatch: bgPreview)
            CardDivider()
            ColorRow(title: "Foreground color", hex: $fgHex, swatch: fgPreview)
            CardDivider()
            FontFieldRow(title: "Interface font", value: "-apple-system, BlinkM")
            CardDivider()
            ToggleRow(title: "Translucent sidebar", detail: nil, isOn: $translucent)
            CardDivider()
            SliderRow(title: "Contraste", value: $contrast, range: 0...100)
        }
    }
}

private struct ColorRow: View {
    let title: LocalizedStringKey
    @Binding var hex: String
    let swatch: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.5))
                Text(hex)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(swatch == .white || swatch == Color.white
                                     ? Color.black
                                     : Palette.textPrimary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(swatch)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .frame(width: 170)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct FontFieldRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .frame(width: 170, alignment: .leading)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Slider(value: $value, in: range)
                .frame(width: 220)
                .tint(Color(red: 0.30, green: 0.55, blue: 1.0))
            Text("\(Int(value))")
                .font(.system(size: 12))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct FontSizeRow: View {
    @Binding var value: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Interface font size")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                Text("Adjust the base size used for the Clawix interface")
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                TextField("", text: $value)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                Text("px")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Settings page

private struct ConfigurationPage: View {
    @State private var approvalPolicy: String = "On request"
    @State private var sandbox: String = "Read only"
    @State private var depsEnabled: Bool = true
    @State private var configScope: String = "User settings"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Settings",
                subtitle: "Configure the approval policy and sandbox settings. Learn more"
            )

            Text("Custom config.toml settings")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            DeprecationBanner()
                .padding(.bottom, 14)

            HStack {
                SettingsDropdown(
                    options: [
                        ("User settings", "User settings"),
                        ("Project settings", "Project settings")
                    ],
                    selection: $configScope,
                    minWidth: 230
                )
                Spacer()
                Button {} label: {
                    HStack(spacing: 4) {
                        Text("Open config.toml")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.textSecondary)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            SettingsCard {
                DropdownRow(
                    title: "Approval policy",
                    detail: "Choose when Clawix asks for approval",
                    options: [("On request", "On request"), ("Always", "Always"), ("Never", "Never")],
                    selection: $approvalPolicy
                )
                CardDivider()
                DropdownRow(
                    title: "Sandbox configuration",
                    detail: "Choose how much Clawix can do when running commands",
                    options: [("Read only", "Read only"), ("Workspace write", "Workspace write"), ("Full access", "Full access")],
                    selection: $sandbox
                )
            }

            SectionLabel(title: "Workspace dependencies")
            SettingsCard {
                HStack {
                    Text("Current version")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Text("26.430.10722")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                CardDivider()
                ToggleRow(
                    title: "Clawix dependencies",
                    detail: "Allow Clawix to install and expose the bundled Node.js and Python tools",
                    isOn: $depsEnabled
                )
                CardDivider()
                ActionPillRow(
                    title: "Diagnose Clawix Workspace issues",
                    detail: "Check the current bundle and save diagnostic logs",
                    primaryLabel: "Diagnosticar",
                    onPrimary: {}
                )
                CardDivider()
                ReinstallRow()
            }
        }
    }
}

private struct DeprecationBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.30))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    InlineCode("[features].collab")
                    Text(" is deprecated. Use ")
                        .foregroundColor(Color(white: 0.85))
                    InlineCode("[features].multi_agent")
                    Text(" instead.")
                        .foregroundColor(Color(white: 0.85))
                }
                .font(.system(size: 12))
                HStack(spacing: 0) {
                    Text("Enable it with ").foregroundColor(Color(white: 0.75))
                    InlineCode("--enable multi_agent")
                    Text(" or ").foregroundColor(Color(white: 0.75))
                    InlineCode("[features].multi_agent")
                    Text(" in config.toml. See").foregroundColor(Color(white: 0.75))
                }
                .font(.system(size: 11.5))
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.45, green: 0.65, blue: 1.0))
                    Text("Toggle experimental features by editing the configuration file.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(red: 0.45, green: 0.65, blue: 1.0))
                    Text("for details.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.75))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.18, green: 0.10, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(red: 0.55, green: 0.30, blue: 0.10), lineWidth: 0.7)
                )
        )
    }
}

private struct InlineCode: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundColor(Color(white: 0.95))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

private struct ReinstallRow: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reset and install workspace")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                Text("Removes the local package, fetches it fresh, and reloads the tools")
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11))
                    Text("Reinstall")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.30, green: 0.10, blue: 0.07))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color(red: 0.55, green: 0.20, blue: 0.15), lineWidth: 0.7)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Personalization page

private struct PersonalizationPage: View {
    @State private var personality: String = "Pragmática"
    @State private var expanded: Bool = false
    @State private var instructions: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Personalization")

            SettingsCard {
                DropdownRow(
                    title: "Personality",
                    detail: "Choose a default tone for Clawix's responses",
                    options: [
                        ("Pragmática", "Pragmática"),
                        ("Amistosa", "Amistosa"),
                        ("Concisa", "Concisa"),
                        ("Técnica", "Técnica")
                    ],
                    selection: $personality
                )
            }
            .padding(.bottom, 28)

            Text("Custom instructions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            Text("Provide extra instructions and context that Clawix should keep in mind for this project. Learn more")
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            ZStack(alignment: .topTrailing) {
                TextEditor(text: $instructions)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 300)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                ExpandIconButton { expanded = true }
                    .padding(8)
            }

            HStack {
                Spacer()
                Button {} label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .sheet(isPresented: $expanded) {
            InstructionsExpandedSheet(text: $instructions, isPresented: $expanded)
        }
    }
}

private struct ExpandIconButton: View {
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: hovered ? 0.95 : 0.78))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.10 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverHint("Edit in large view")
    }
}

private struct InstructionsExpandedSheet: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Custom instructions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(white: 0.78))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(18)
                .background(Color(white: 0.06))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack {
                Spacer()
                Button { isPresented = false } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 820, idealWidth: 980, maxWidth: 1200,
               minHeight: 600, idealHeight: 720, maxHeight: 900)
        .background(Color(white: 0.07))
    }
}

// MARK: - Placeholder page (categories without a screenshot yet)

private struct PlaceholderPage: View {
    let category: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: category.title)

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: category.iconName)
                        .font(.system(size: 16))
                        .foregroundColor(Palette.textSecondary)
                    Text("Coming soon")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 22)
            }
        }
    }
}

// MARK: - Uso page

private struct UsagePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Uso")

            Text("General usage limits")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            SettingsCard {
                UsageBarRow(title: "5-hour usage limit",
                            detail: "Resets at 17:09",
                            percent: 100)
                CardDivider()
                UsageBarRow(title: "Weekly usage limit",
                            detail: "Resets on May 5",
                            percent: 82)
            }

            SectionLabel(title: "Usage limits for GPT-5.3-Clawix-Spark")
            SettingsCard {
                UsageBarRow(title: "5-hour usage limit",
                            detail: "Resets at 18:02",
                            percent: 100)
                CardDivider()
                UsageBarRow(title: "Weekly usage limit",
                            detail: "Resets on May 8",
                            percent: 100)
            }

            SectionLabel(title: "Credit")
            SettingsCard {
                CreditRow(title: "0 credit remaining",
                          detail: "Use credit to send messages when you hit your usage limits. Docs",
                          primaryLabel: "Comprar",
                          showLink: true)
                CardDivider()
                CreditRow(title: "Auto top-up credit",
                          detail: "Top up automatically when your balance hits the minimum.",
                          primaryLabel: "Settings",
                          showLink: false)
            }
        }
    }
}

private struct UsageBarRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let percent: Int

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 120, height: 5)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: max(2, 120 * CGFloat(percent) / 100), height: 5)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(percent) %")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Text("remaining")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }
                .frame(width: 56, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

private struct CreditRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let primaryLabel: LocalizedStringKey
    let showLink: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                HStack(spacing: 4) {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                    if showLink {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 12)
            Button {} label: {
                Text(primaryLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Chats archivados page

private struct ArchivedChatItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let project: String
}

private struct ArchivedChatsPage: View {
    private let items: [ArchivedChatItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Chats archivados")

            if items.isEmpty {
                Text("You have no archived chats.")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.top, 12)
            } else {
                SettingsCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        ArchivedChatRow(item: item)
                        if idx < items.count - 1 {
                            CardDivider()
                        }
                    }
                }
            }
        }
    }
}

private struct ArchivedChatRow: View {
    let item: ArchivedChatItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(item.date) · \(item.project)")
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button {} label: {
                Text("Unarchive")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Browser usage page

private struct BrowserUsagePage: View {
    @State private var browsingData: String = "Clear all browsing data"
    @State private var approval: String = "Preguntar siempre"
    @State private var history: String = "Preguntar siempre"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Browser usage")

            /*
            Text("Plugins")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            SettingsCard {
                BrowserPluginRow(title: "Browser Use",
                                 detail: "Control the in-app browser with Clawix")
            }
            */

            SectionLabel(title: "Browser")
            SettingsCard {
                DropdownRow(
                    title: "Browsing data",
                    detail: "Clear site data and the cache of the in-app browser",
                    options: [
                        ("Clear all browsing data", "Clear all browsing data"),
                        ("Clear cache", "Clear cache"),
                        ("Clear cookies", "Clear cookies")
                    ],
                    selection: $browsingData
                )
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                DropdownRow(
                    title: "Approval",
                    detail: "Choose whether Clawix asks for permission before opening websites",
                    options: [
                        ("Preguntar siempre", "Preguntar siempre"),
                        ("Permitir siempre", "Permitir siempre"),
                        ("Bloquear siempre", "Bloquear siempre")
                    ],
                    selection: $approval
                )
                CardDivider()
                DropdownRow(
                    title: "Historial",
                    detail: "Choose whether Clawix asks for approval before accessing your history",
                    options: [
                        ("Preguntar siempre", "Preguntar siempre"),
                        ("Permitir siempre", "Permitir siempre"),
                        ("Bloquear siempre", "Bloquear siempre")
                    ],
                    selection: $history
                )
            }

            DomainListSection(title: "Dominios bloqueados",
                              subtitle: "Clawix will never open these sites",
                              emptyText: "No hay dominios bloqueados")
                .padding(.top, 28)

            DomainListSection(title: "Dominios permitidos",
                              subtitle: "Domains that open without prompting",
                              emptyText: "No hay dominios permitidos")
                .padding(.top, 28)
        }
    }
}

private struct BrowserPluginRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.20, blue: 0.36),
                                     Color(red: 0.06, green: 0.10, blue: 0.20)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct DomainListSection: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let emptyText: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {} label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .padding(.top, 4)
                .padding(.bottom, 10)

            HStack {
                Spacer()
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Entornos page

private struct EnvironmentsPage: View {
    @State private var selected: ProjectEntry? = nil

    private let projects: [ProjectEntry] = [
        .init(name: "New project"),
    ]

    var body: some View {
        if let project = selected {
            EnvironmentsDetail(project: project, onBack: { selected = nil })
        } else {
            EnvironmentsList(projects: projects, onSelect: { selected = $0 })
        }
    }
}

private struct ProjectEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var tag: String? = nil
}

private struct EnvironmentsList: View {
    let projects: [ProjectEntry]
    let onSelect: (ProjectEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Environments",
                subtitle: "Local environments tell Clawix how to set up worktrees for a project. ..."
            )

            HStack {
                Text("Select a project")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {} label: {
                    Text("Add project")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            VStack(spacing: 7) {
                ForEach(projects) { project in
                    ProjectListRow(project: project, onTap: { onSelect(project) })
                }
            }
        }
    }
}

private struct ProjectListRow: View {
    let project: ProjectEntry
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 18)
            Text(project.name)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            if let tag = project.tag {
                Text(tag)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.50))
            }
            Spacer()
            Button(action: onTap) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .frame(width: 28, height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

private struct EnvironmentsDetail: View {
    let project: ProjectEntry
    let onBack: () -> Void

    @State private var name: String
    @State private var setupTab: String = "Default"
    @State private var setupScript: String = """
    cd "$CLAWIX_WORKTREE_PATH"
    pip install -r requirements.txt
    npm install
    ./run/setup.sh
    """
    @State private var cleanupTab: String = "Default"
    @State private var cleanupScript: String = """
    docker compose down --remove-orphans
    rm -rf .cache/tmp
    """

    init(project: ProjectEntry, onBack: @escaping () -> Void) {
        self.project = project
        self.onBack = onBack
        _name = State(initialValue: project.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .hoverHint("Volver")
                Text("Environments")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
            }
            .padding(.bottom, 26)

            Text("Local environment")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundColor(Palette.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13))
                        .foregroundColor(Palette.textPrimary)
                    Text("~/Documents/\(project.name)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )

            SectionLabel(title: "Name")
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: 280, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )

            ScriptBlock(
                title: "Setup script",
                detail: "Runs at the project root when the worktree is created",
                tab: $setupTab,
                script: $setupScript
            )
            .padding(.top, 28)

            ScriptBlock(
                title: "Cleanup script",
                detail: "Runs at the project root before cleaning up the worktree",
                tab: $cleanupTab,
                script: $cleanupScript
            )
            .padding(.top, 28)

            HStack {
                Text("Actions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {} label: {
                    Text("Add an action")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 28)

            Text("Each action can run any command and shows up in the toolbar header.")
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecondary)
                .padding(.top, 4)
                .padding(.bottom, 14)

            HStack {
                Spacer()
                Text("Register an action that runs a command from the local toolbar.")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )

            HStack {
                Spacer()
                Button {} label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
    }
}

private struct ScriptBlock: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var tab: String
    @Binding var script: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .padding(.top, 3)
                .padding(.bottom, 12)

            ScriptTabs(selected: $tab)
                .padding(.bottom, 8)

            TextEditor(text: $script)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 130)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
    }
}

private struct ScriptTabs: View {
    @Binding var selected: String
    private let tabs = ["Default", "macOS", "Linux", "Windows"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selected = tab
                } label: {
                    Text(tab)
                        .font(.system(size: 12, weight: selected == tab ? .medium : .regular))
                        .foregroundColor(selected == tab ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected == tab ? Color.white.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Variables")
                .font(.system(size: 12))
                .foregroundColor(Palette.textSecondary)
        }
    }
}

// MARK: - Git page

private struct GitPage: View {
    @State private var prefix: String = "clawix/"
    @State private var mergeMethod: GitMergeMethod = .merge
    @State private var showPRIcons: Bool = false
    @State private var forcePush: Bool = false
    @State private var draftPR: Bool = true
    @State private var autoRemoveWorktrees: Bool = true
    @State private var autoLimit: String = "15"

    enum GitMergeMethod: Hashable { case merge, squash }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Git")

            SettingsCard {
                GitTextFieldRow(
                    title: "Branch prefix",
                    detail: "Prefix used when creating new branches in Clawix",
                    text: $prefix,
                    width: 160
                )
                CardDivider()
                SegmentedRow(
                    title: "Pull request merge method",
                    detail: "Choose how Clawix merges pull requests",
                    options: [(.merge, "Fusionar"), (.squash, "Squash")],
                    selection: $mergeMethod
                )
                CardDivider()
                ToggleRow(
                    title: "Show PR icons in the sidebar",
                    detail: "Show PR status icons on chat rows in the sidebar",
                    isOn: $showPRIcons
                )
                CardDivider()
                ToggleRow(
                    title: "Always force-push",
                    detail: "Use --force-with-lease when pushing from Clawix",
                    isOn: $forcePush
                )
                CardDivider()
                ToggleRow(
                    title: "Create pull request drafts",
                    detail: "Use drafts by default when creating PRs from Clawix",
                    isOn: $draftPR
                )
                CardDivider()
                ToggleRow(
                    title: "Auto-delete old worktrees",
                    detail: "Recommended for most users. Disable only if you want to manage old worktrees and disk usage yourself.",
                    isOn: $autoRemoveWorktrees
                )
                CardDivider()
                GitTextFieldRow(
                    title: "Auto-delete limit",
                    detail: "Number of Clawix worktrees kept before older ones are auto-deleted. Clawix snapshots worktrees before removing them, so deleted worktrees should always be restorable.",
                    text: $autoLimit,
                    width: 80,
                    monospaced: true,
                    rightAligned: true,
                    alignment: .top
                )
            }

            CommitInstructionsBlock(
                title: "Commit instructions",
                detail: "Added to the prompts that generate commit messages",
                placeholder: "Add a guideline for the commit message..."
            )
            .padding(.top, 28)

            CommitInstructionsBlock(
                title: "Pull request instructions",
                detail: "Added to the prompts that generate the PR title and description",
                placeholder: "Add a guideline for the pull request..."
            )
            .padding(.top, 28)
        }
    }
}

private struct GitTextFieldRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var text: String
    var width: CGFloat = 160
    var monospaced: Bool = false
    var rightAligned: Bool = false
    var alignment: VerticalAlignment = .center

    var body: some View {
        HStack(alignment: alignment, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(rightAligned ? .trailing : .leading)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(width: width)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct CommitInstructionsBlock: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let placeholder: String
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                Button {} label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 110)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Servidores MCP page

private struct MCPServer: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var isOn: Bool
}

private struct MCPPage: View {
    @State private var creating: Bool = false
    @State private var editing: MCPServer? = nil
    @State private var servers: [MCPServer] = []

    var body: some View {
        if creating || editing != nil {
            MCPDetailView(onBack: {
                creating = false
                editing = nil
            })
        } else {
            MCPListView(
                servers: $servers,
                onAdd: { creating = true },
                onConfig: { server in editing = server }
            )
        }
    }
}

private struct MCPListView: View {
    @Binding var servers: [MCPServer]
    let onAdd: () -> Void
    let onConfig: (MCPServer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MCP servers")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                (
                    Text("Connect external tools and data sources.")
                        .foregroundColor(Palette.textSecondary)
                    + Text(" ")
                    + Text("Learn more.")
                        .foregroundColor(Color(red: 0.45, green: 0.65, blue: 1.0))
                )
                .font(.system(size: 12.5))
            }
            .padding(.bottom, 26)

            HStack {
                Text("Servers")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add server")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            VStack(spacing: 7) {
                ForEach($servers) { $server in
                    MCPServerRow(server: $server, onConfig: { onConfig(server) })
                }
            }
        }
    }
}

private struct MCPServerRow: View {
    @Binding var server: MCPServer
    let onConfig: () -> Void
    @State private var configHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(server.name)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            Button(action: onConfig) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: configHovered ? 0.94 : 0.62))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { configHovered = $0 }
            .hoverHint("Configure")
            PillToggle(isOn: $server.isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

// MCP detail / connect view

private enum MCPTransport: Hashable { case stdio, http }

private struct MCPDetailView: View {
    let onBack: () -> Void

    @State private var name: String = ""
    @State private var transport: MCPTransport = .stdio
    @State private var command: String = ""
    @State private var args: [MCPField] = [.init()]
    @State private var envVars: [MCPKeyValue] = [.init()]
    @State private var passEnvs: [MCPField] = [.init()]
    @State private var workDir: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .hoverHint("Volver")
                Text("Connect to a custom MCP")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
            }
            Button {} label: {
                HStack(spacing: 4) {
                    Text("Documents")
                        .font(.system(size: 12.5))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                }
                .foregroundColor(Color(red: 0.45, green: 0.65, blue: 1.0))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 12) {
                MCPFieldLabel("Name")
                MCPInputField(placeholder: "MCP server name", text: $name)
                MCPTransportSegmented(selection: $transport)
            }
            .padding(14)
            .background(mcpCardBackground)

            VStack(alignment: .leading, spacing: 12) {
                MCPFieldLabel("Command to start")
                MCPInputField(placeholder: "dev-mcp serve-sqlite", text: $command)
            }
            .padding(14)
            .background(mcpCardBackground)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    MCPFieldLabel("Arguments")
                    ForEach($args) { $entry in
                        HStack(spacing: 10) {
                            MCPInputField(placeholder: "", text: $entry.value)
                            MCPTrashButton {
                                args.removeAll { $0.id == entry.id }
                                if args.isEmpty { args.append(.init()) }
                            }
                        }
                    }
                    MCPAddRowButton(label: "Add argument") {
                        args.append(.init())
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    MCPFieldLabel("Environment variables")
                    ForEach($envVars) { $entry in
                        HStack(spacing: 10) {
                            MCPInputField(placeholder: "Clave", text: $entry.key)
                            MCPInputField(placeholder: "Valor", text: $entry.value)
                            MCPTrashButton {
                                envVars.removeAll { $0.id == entry.id }
                                if envVars.isEmpty { envVars.append(.init()) }
                            }
                        }
                    }
                    MCPAddRowButton(label: "Add environment variable") {
                        envVars.append(.init())
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    MCPFieldLabel("Environment variable pass-through")
                    ForEach($passEnvs) { $entry in
                        HStack(spacing: 10) {
                            MCPInputField(placeholder: "", text: $entry.value)
                            MCPTrashButton {
                                passEnvs.removeAll { $0.id == entry.id }
                                if passEnvs.isEmpty { passEnvs.append(.init()) }
                            }
                        }
                    }
                    MCPAddRowButton(label: "Add variable") {
                        passEnvs.append(.init())
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    MCPFieldLabel("Working directory")
                    MCPInputField(placeholder: "~/code", text: $workDir)
                }
            }
            .padding(14)
            .background(mcpCardBackground)
            .padding(.top, 12)

            HStack {
                Spacer()
                Button {} label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
    }

    private var mcpCardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(white: 0.085))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}

private struct MCPField: Identifiable, Hashable {
    let id = UUID()
    var value: String = ""
}

private struct MCPKeyValue: Identifiable, Hashable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}

private struct MCPFieldLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Palette.textPrimary)
    }
}

private struct MCPInputField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
}

private struct MCPTrashButton: View {
    let action: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(Color(white: hovered ? 0.94 : 0.55))
                .frame(width: 30, height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.06 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverHint("Delete")
    }
}

private struct MCPAddRowButton: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12.5))
            }
            .foregroundColor(Color(white: hovered ? 0.94 : 0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(hovered ? 0.36 : 0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct MCPTransportSegmented: View {
    @Binding var selection: MCPTransport

    var body: some View {
        HStack(spacing: 4) {
            chip(label: "STDIO", value: .stdio)
            chip(label: "HTTP streaming", value: .http)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func chip(label: LocalizedStringKey, value: MCPTransport) -> some View {
        let isOn = value == selection
        Button {
            selection = value
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: isOn ? .medium : .regular))
                .foregroundColor(isOn ? Palette.textPrimary : Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.white.opacity(0.10) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
