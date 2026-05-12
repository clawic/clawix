import SwiftUI

// MARK: - Settings categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    // case appearance  // hidden temporarily
    case configuration
    case personalization
    case skills
    case dictation
    case screenTools
    case quickAsk
    case localModels
    case modelProviders
    case mcp
    case machines
    case git
    case browserUsage
    case usage
    case macUtilities
    case secrets
    case clawjs
    case telegram
    case apps

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:          return "General"
        // case .appearance:       return "Appearance"
        case .configuration:    return "Settings"
        case .personalization:  return "Personalization"
        case .skills:           return "Skills"
        case .dictation:        return "Voice to Text"
        case .screenTools:      return "Screen Tools"
        case .quickAsk:         return "QuickAsk"
        case .localModels:      return "Local models"
        case .modelProviders:   return "Model Providers"
        case .mcp:              return "MCP servers"
        case .machines:         return "Hosts"
        case .git:              return "Git"
        case .browserUsage:     return "Browser usage"
        case .usage:            return "Usage"
        case .macUtilities:     return "Mac Utilities"
        case .secrets:          return "Secrets"
        case .clawjs:           return "ClawJS"
        case .telegram:         return "Telegram"
        case .apps:             return "Apps"
        }
    }

    var iconName: String {
        switch self {
        case .general:          return "house"
        // case .appearance:       return "circle.lefthalf.filled"
        case .configuration:    return "slider.horizontal.3"
        case .personalization:  return "person.crop.circle"
        case .skills:           return "wand.and.stars"
        case .dictation:        return "mic.fill"
        case .screenTools:      return "camera.viewfinder"
        case .quickAsk:         return "command"
        case .localModels:      return "cpu"
        case .modelProviders:   return "layers"
        case .mcp:              return "server.rack"
        case .machines:         return "laptopcomputer"
        case .git:              return "arrow.triangle.branch"
        case .browserUsage:     return "cursor"
        case .usage:            return "chart.bar"
        case .macUtilities:     return "bolt"
        case .secrets:          return "lock.shield"
        case .clawjs:           return "shippingbox"
        case .telegram:         return "paperplane.fill"
        case .apps:             return "square.grid.2x2"
        }
    }

    var gatedFeature: AppFeature? {
        switch self {
        case .dictation:    return .voiceToText
        case .quickAsk:     return .quickAsk
        case .secrets:      return .secrets
        case .mcp:          return .mcp
        case .localModels:  return .localModels
        case .browserUsage: return .browserUsage
        case .git:          return .git
        case .machines:     return .remoteMesh
        default:            return nil
        }
    }

    static func visibleCases(isVisible: (AppFeature) -> Bool) -> [SettingsCategory] {
        allCases.filter { category in
            guard let feature = category.gatedFeature else { return true }
            return isVisible(feature)
        }
    }
}

// MARK: - Settings sidebar (replaces the chat sidebar while in .settings)

struct SettingsSidebar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var flags: FeatureFlags
    @State private var backHovered = false

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.visibleCases(isVisible: flags.isVisible)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                appState.currentRoute = .home
            } label: {
                HStack(spacing: 11) {
                    LucideIcon(.arrowLeft, size: 13)
                        .frame(width: 15, alignment: .center)
                        .foregroundColor(Color(white: backHovered ? 0.92 : 0.78))
                    Text("Back to app")
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(Color(white: 0.92))
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 10)
                .frame(height: 35)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(backHovered ? Color.white.opacity(0.035) : .clear)
                )
                .animation(.easeOut(duration: 0.12), value: backHovered)
            }
            .buttonStyle(.plain)
            .sidebarHover { backHovered = $0 }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 14)

            VStack(spacing: 1) {
                ForEach(visibleCategories) { cat in
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
            HStack(spacing: 11) {
                categoryIcon
                    .frame(width: 15, alignment: .center)
                    .foregroundColor(iconColor)
                Text(category.title)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(labelColor)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .frame(height: 35)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .sidebarHover { hovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return Color(white: hovered ? 0.92 : 0.78)
    }

    private var labelColor: Color {
        isSelected ? .white : Color(white: 0.92)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.white.opacity(0.06) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }

    @ViewBuilder
    private var categoryIcon: some View {
        switch category {
        case .configuration:
            SettingsIcon(size: 19, lineWidth: 0.9)
        case .personalization:
            BotIcon(size: 16, lineWidth: 1.4)
        case .browserUsage:
            IconImage(category.iconName, size: 20)
                .offset(y: 2)
        case .git:
            IconImage(category.iconName, size: 14)
                .offset(y: 1)
        case .usage:
            UsageIcon(size: 16, lineWidth: 1.7)
        case .localModels:
            LocalModelsIcon(size: 16, lineWidth: 1.4)
        case .secrets:
            // Match the padlock used in the main sidebar's SecretsToolRow so
            // both navs share the same glyph. `isLocked` is true here because
            // this row is nav chrome — the actual vault state is reflected on
            // the Secrets page itself.
            SecretsIcon(size: 15, lineWidth: 1.28, isLocked: true)
        case .mcp:
            McpIcon(size: 16, lineWidth: 1.28)
        default:
            IconImage(category.iconName, size: 14)
        }
    }
}

// MARK: - Settings content router (right column)

struct SettingsContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var flags: FeatureFlags

    private var resolvedCategory: SettingsCategory {
        if let feature = appState.settingsCategory.gatedFeature,
           !flags.isVisible(feature) {
            return .general
        }
        return appState.settingsCategory
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch resolvedCategory {
                    case .general:         GeneralPage()
                    // case .appearance:      AppearancePage()
                    case .configuration:   ConfigurationPage()
                    case .personalization: PersonalizationPage()
                    case .skills:          SkillsSettingsPage()
                    case .dictation:       DictationSettingsPage()
                    case .screenTools:     ScreenToolsSettingsPage()
                    case .quickAsk:        QuickAskSettingsPage()
                    case .localModels:     LocalModelsPage()
                    case .modelProviders:  ProvidersSettingsPage()
                    case .git:             GitPage()
                    case .browserUsage:    BrowserUsagePage()
                    case .usage:           UsagePage()
                    case .macUtilities:    MacUtilitiesSettingsPage()
                    case .mcp:             MCPPage()
                    case .machines:        HostsPage()
                    case .secrets:         SecretsSettingsPage()
                    case .clawjs:          ClawJSSettingsPage()
                    case .telegram:        TelegramSettingsPage()
                    case .apps:            AppsSettingsPage()
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .thinScrollers()
        .background(Palette.background)
    }
}

@MainActor
private enum SettingsUtilities {
    static func revealDiagnosticsFolder() {
        ResourceSampler.persistLastSample()
        guard let file = ResourceSampler.diagnosticsFileURL(named: "last-resources.json") else {
            ToastCenter.shared.show("Diagnostics folder unavailable", icon: .error)
            return
        }
        let dir = file.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        ToastCenter.shared.show("Diagnostics folder opened")
    }

    static func openConfigToml(scope: String, selectedProject: Project?) {
        let url: URL
        if scope == "Project settings" {
            guard let path = selectedProject?.path, !path.isEmpty else {
                ToastCenter.shared.show("Select a project before opening project config", icon: .warning)
                return
            }
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                .appendingPathComponent(".codex/config.toml", isDirectory: false)
        } else {
            url = CodexConfigToml.configURL
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            ToastCenter.shared.show("config.toml not found", icon: .warning)
            return
        }
        NSWorkspace.shared.open(url)
        ToastCenter.shared.show("config.toml opened")
    }
}

// MARK: - PillToggle (kept here, every other shared building block lives in SettingsKit.swift)

struct PillToggle: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 34
    private let trackHeight: CGFloat = 20
    private let knobSize: CGFloat = 16
    private let inset: CGFloat = 2

    private var knobOffset: CGFloat {
        isOn ? trackWidth - knobSize - inset : inset
    }

    private var trackFill: Color {
        isOn ? Color(red: 0.16, green: 0.46, blue: 0.98) : Color(white: 0.22)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
            Circle()
                .fill(Color.white)
                .frame(width: knobSize, height: knobSize)
                .shadow(color: .black.opacity(0.20), radius: 1, x: 0, y: 1)
                .offset(x: knobOffset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                isOn.toggle()
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
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
    var descriptionForOption: ((T) -> String?)? = nil
    /// Optional view rendered inside the trigger, between the label
    /// and the chevron. Used by the Microphone row to inline the
    /// level meter with the device name.
    var trailingAccessory: (() -> AnyView)? = nil
    /// Minimum capsule width. The trigger will only ever be wider than
    /// this if its content (longest option's text + icon + chevron +
    /// padding) requires it.
    var minWidth: CGFloat = 160
    /// Kept for source compatibility with existing call sites; the
    /// trigger now sizes adaptively to its content, so this flag is a
    /// no-op. It can be deleted once nothing references it.
    var fillsWidth: Bool = false

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
                // ZStack overlays a phantom layer (every option's
                // label, hidden) on top of the visible current
                // selection. The ZStack's intrinsic width is the max
                // of its children's widths, so the capsule is exactly
                // wide enough to display the LONGEST option without
                // truncation, regardless of which one is currently
                // selected. Keeps the trigger from jumping width when
                // the user picks a longer option.
                ZStack(alignment: .leading) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                        triggerLabel(option: opt.0, label: opt.1)
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                    triggerLabel(option: selection, label: currentLabel)
                }
                Spacer(minLength: 8)
                if let accessory = trailingAccessory?() {
                    accessory
                }
                LucideIcon(.chevronDown, size: 11)
                    .foregroundColor(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: minWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
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
                        descriptionForOption: descriptionForOption,
                        minWidth: buttonFrame.width
                    )
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .leading()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(isOpen)
        }
        .animation(MenuStyle.openAnimation, value: isOpen)
        // Bubbles "any descendant dropdown is open" up the view tree so
        // wrappers (row, card, page) can apply `.zIndex` and keep the
        // popup above later siblings that would otherwise paint on top.
        .preference(key: SettingsDropdownOpenKey.self, value: isOpen)
    }

    @ViewBuilder
    private func triggerLabel(option: T, label: String) -> some View {
        HStack(spacing: 10) {
            if let icon = iconForOption?(option) {
                icon
            }
            Text(label)
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// Bubbles up "is any descendant `SettingsDropdown` currently open?".
/// Combined via OR so a single open dropdown anywhere in the subtree wins.
struct SettingsDropdownOpenKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Lifts this view above its layout siblings while any descendant
    /// `SettingsDropdown` is open, so the open popup paints over later
    /// siblings (next row, next card, next section). Apply on every
    /// layout level that has siblings the popup might extend into.
    func liftWhenSettingsDropdownOpen() -> some View {
        modifier(LiftWhenSettingsDropdownOpenModifier())
    }
}

private struct LiftWhenSettingsDropdownOpenModifier: ViewModifier {
    @State private var hasOpenDropdown = false
    func body(content: Content) -> some View {
        content
            .zIndex(hasOpenDropdown ? 1 : 0)
            .onPreferenceChange(SettingsDropdownOpenKey.self) { hasOpenDropdown = $0 }
    }
}

/// Standard settings row with a label on the left and a control
/// (dropdown, button, etc.) on the right. The label takes whatever
/// horizontal space is left after the trailing control sizes itself
/// to its natural content. This keeps every dropdown wide enough for
/// its longest option and lets rows that share the trailing slot with
/// extra widgets (e.g. the Audio Input meter next to the device
/// dropdown) grow as needed without forcing a global percentage.
struct SettingsRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    var descriptionForOption: ((T) -> String?)? = nil
    let minWidth: CGFloat

    @State private var hoveredIndex: Int? = nil

    private var hasAnyDescription: Bool {
        guard let resolver = descriptionForOption else { return false }
        return options.contains { resolver($0.0)?.isEmpty == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                Button {
                    selection = opt.0
                    isOpen = false
                } label: {
                    HStack(alignment: hasAnyDescription ? .top : .center, spacing: 10) {
                        if let icon = iconForOption?(opt.0) {
                            icon
                        }
                        if hasAnyDescription {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.1)
                                    .font(BodyFont.system(size: 13, wght: 600))
                                    .foregroundColor(MenuStyle.rowText)
                                    .lineLimit(1)
                                if let desc = descriptionForOption?(opt.0), !desc.isEmpty {
                                    Text(desc)
                                        .font(BodyFont.system(size: 11.5, wght: 500))
                                        .foregroundColor(MenuStyle.rowSubtle)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(opt.1)
                                .font(BodyFont.system(size: 12.5))
                                .foregroundColor(MenuStyle.rowText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if opt.0 == selection {
                            CheckIcon(size: 11)
                                .foregroundColor(MenuStyle.rowText)
                                .padding(.top, hasAnyDescription ? 3 : 0)
                        }
                    }
                    .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                    .padding(.vertical, hasAnyDescription ? 8 : MenuStyle.rowVerticalPadding)
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
    var width: CGFloat = 190

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            SlidingSegmented(selection: $selection, options: options)
                .frame(width: width)
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
    var isEnabled = true
    let onPrimary: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                if let trailingDisabled {
                    Text(trailingDisabled)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                Button(action: onPrimary) {
                    Text(primaryLabel)
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(isEnabled ? Palette.textPrimary : Palette.textSecondary)
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
                .disabled(!isEnabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - General page

private struct GeneralPage: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var flags: FeatureFlags
    @State private var workMode: WorkMode = .daily
    @State private var permDefault: Bool = true
    @State private var permAuto: Bool = true
    @State private var permFull: Bool = true
    @State private var openTarget: String = "Ghostty"
    @State private var showInMenuBar: Bool = true
    @State private var preventSleep: Bool = true
    @StateObject private var backgroundBridge: BackgroundBridgeService = .shared
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
    @State private var syncArchiveWithCodex: Bool = SyncSettings.syncArchiveWithCodex
    @State private var syncRenamesWithCodex: Bool = SyncSettings.syncRenamesWithCodex
    @State private var pushProjectsToCodex: Bool = SyncSettings.pushProjectsToCodex
    @State private var autoReloadOnFocus: Bool = SyncSettings.autoReloadOnFocus

    enum WorkMode: Hashable { case coding, daily }
    enum FollowBehavior: Hashable { case queue, drive }
    enum CodeReview: Hashable { case inline, detached }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "General")

#if DEBUG
            // Beta + Experimental toggles ship in dev builds only. Release
            // builds compile both flags as `let beta = false` /
            // `let experimental = false` (see FeatureFlags.swift), so the
            // setter Binding below cannot exist there. Hiding the whole
            // card keeps the Settings page tidy and prevents users on a
            // notarized build from poking at half-finished surfaces.
            SectionLabel(title: "Feature previews")
            SettingsCard {
                ToggleRow(
                    title: "Beta features",
                    detail: "Show features in active development. They generally work but may still have rough edges. Off by default.",
                    isOn: Binding(
                        get: { flags.beta },
                        set: { flags.beta = $0 }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Experimental features",
                    detail: "Show very early features that may not work well yet. For previewing only, not for serious use. Off by default.",
                    isOn: Binding(
                        get: { flags.experimental },
                        set: { flags.experimental = $0 }
                    )
                )
            }
            .padding(.bottom, 8)
#endif

            if flags.experimental {
                Text("Work mode")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Choose how much technical detail Clawix shows")
                    .font(BodyFont.system(size: 11, wght: 500))
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
            }

            SectionLabel(title: "General")
            SettingsCard {
                DropdownRow(
                    title: "Language",
                    detail: "App interface language",
                    options: AppLanguage.allCases.map { ($0, $0.displayName) },
                    selection: Binding(
                        get: { appState.preferredLanguage },
                        set: { appState.preferredLanguage = $0 }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Run bridge in background",
                    detail: "Registers a LaunchAgent helper that keeps a bridge process alive even after Clawix is fully quit. Closing the window already keeps the in-process bridge alive thanks to the menu bar item; this toggle is a foundation for the upcoming \"daemon owns chat state\" mode and currently registers a stub helper that won't have your chats yet. Status: \(backgroundBridge.statusLabel)\(backgroundBridge.lastError.map { " — \($0)" } ?? "")",
                    isOn: Binding(
                        get: { backgroundBridge.isEnabled },
                        set: { backgroundBridge.toggle($0) }
                    )
                )
                CardDivider()
                SegmentedRow(
                    title: "Agent runtime",
                    detail: appState.selectedAgentRuntime == .opencode
                        ? "OpenCode uses \(appState.openCodeModelSelection). Restart the background bridge after switching."
                        : "Codex remains the default runtime.",
                    options: AgentRuntimeChoice.allCases.map { ($0, $0.label) },
                    selection: $appState.selectedAgentRuntime
                )
                CardDivider()
                DropdownRow(
                    title: "OpenCode model",
                    detail: "Provider/model id used when OpenCode is active. DeepSeek V4 Pro is selected by default.",
                    options: [(AgentRuntimeChoice.defaultOpenCodeModel, AgentRuntimeChoice.defaultOpenCodeModel)],
                    selection: Binding(
                        get: { appState.openCodeModelSelection },
                        set: {
                            appState.selectedModel = $0
                            appState.selectedAgentRuntime = .opencode
                        }
                    )
                )
                if flags.experimental {
                    CardDivider()
                    DropdownRow(
                        title: "Default open destination",
                        detail: "Where files and folders open by default",
                        options: [("Ghostty", "Ghostty"), ("Terminal", "Terminal"), ("VS Code", "VS Code")],
                        selection: $openTarget,
                        iconForOption: { openTargetIcon(for: $0) }
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
                        isEnabled: false,
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
                        options: [(.queue, L10n.t("Queue")), (.drive, L10n.t("Drive"))],
                        selection: $followBehavior
                    )
                    CardDivider()
                    SegmentedRow(
                        title: "Code review",
                        detail: "Start /review in the current chat when possible, or open a separate review chat",
                        options: [(.inline, L10n.t("Inline")), (.detached, L10n.t("Detached"))],
                        selection: $codeReview
                    )
                    CardDivider()
                    ImportAgentRow()
                }
            }

            SectionLabel(title: "Sync with Codex")
            SettingsCard {
                ToggleRow(
                    title: "Sync archived chats with Codex",
                    detail: "When you archive or unarchive a chat, mirror that to Codex CLI. Disable to keep archive state local to this app. Reactivating sync does not propagate previous local-only changes.",
                    isOn: Binding(
                        get: { syncArchiveWithCodex },
                        set: { newValue in
                            syncArchiveWithCodex = newValue
                            SyncSettings.syncArchiveWithCodex = newValue
                        }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Sync chat renames with Codex",
                    detail: "When you rename a chat, also update the title in Codex CLI. Disable to keep custom titles only in this app.",
                    isOn: Binding(
                        get: { syncRenamesWithCodex },
                        set: { newValue in
                            syncRenamesWithCodex = newValue
                            SyncSettings.syncRenamesWithCodex = newValue
                        }
                    )
                )
                CardDivider()
                ToggleRow(
                    title: "Push local projects to Codex",
                    detail: "When enabled, projects you create in this app are written to Codex's global state file so other Codex apps see them. Default off to keep your local projects local.",
                    isOn: Binding(
                        get: { pushProjectsToCodex },
                        set: { newValue in
                            handlePushProjectsToggle(newValue)
                        }
                    )
                )
                CardDivider()
                PinsSourceInfoRow()
            }

            HiddenCodexFoldersSection()

            if flags.experimental {
                SectionLabel(title: "Dictation")
                SettingsCard {
                    ActionPillRow(
                        title: "Push-to-dictate keyboard shortcut",
                        detail: "Hold down anywhere on the desktop to dictate where the cursor is",
                        primaryLabel: "Set",
                        trailingDisabled: "Off",
                        isEnabled: false,
                        onPrimary: {}
                    )
                    CardDivider()
                    ActionPillRow(
                        title: "Toggle dictation keyboard shortcut",
                        detail: "Press once anywhere on the desktop to dictate, press again to stop",
                        primaryLabel: "Set",
                        trailingDisabled: "Off",
                        isEnabled: false,
                        onPrimary: {}
                    )
                    CardDivider()
                    DictionaryExpandableRow(entries: $dictionaryEntries)
                    ForEach(Array(recentDictations.enumerated()), id: \.offset) { _, item in
                        CardDivider()
                        RecentDictationRow(stamp: item.stamp, text: item.text)
                    }
                }

                SectionLabel(title: "Notifications")
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

            SectionLabel(title: "App behavior")
            SettingsCard {
                ToggleRow(
                    title: "Auto-refresh on focus",
                    detail: "Reload chats from Codex automatically when this app becomes the active window.",
                    isOn: Binding(
                        get: { autoReloadOnFocus },
                        set: { newValue in
                            autoReloadOnFocus = newValue
                            SyncSettings.autoReloadOnFocus = newValue
                        }
                    )
                )
            }

            SectionLabel(title: "Danger zone")
            SettingsCard {
                ResetLocalOverridesRow()
            }
        }
    }

    /// Toggling Push projects ON triggers a confirmation dialog explaining
    /// that we will write to a Codex-managed file. Cancelling reverts the
    /// toggle to OFF so the @State stays in sync with the actual setting.
    /// Toggling OFF is silent (no confirm, no Codex side-effect).
    private func handlePushProjectsToggle(_ newValue: Bool) {
        if !newValue {
            pushProjectsToCodex = false
            SyncSettings.pushProjectsToCodex = false
            return
        }
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Sync local projects to Codex?",
            body: "This will write your local projects to Codex's global state file at ~/.codex/.codex-global-state.json. Other Codex apps (CLI, Electron desktop) will see them. Existing Codex data is not affected.\n\nThis is a write to a file managed by Codex. We cannot guarantee that future Codex updates won't change its format.",
            confirmLabel: "Enable sync",
            isDestructive: false,
            onConfirm: {
                self.pushProjectsToCodex = true
                SyncSettings.pushProjectsToCodex = true
            }
        )
    }
}

private struct PinsSourceInfoRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pins")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Text("Pins are mirrored from Codex on each launch. Pinning or unpinning from this app applies locally and never writes back to Codex.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.55))
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct HiddenCodexFoldersSection: View {
    @EnvironmentObject var appState: AppState
    @State private var hidden: [String] = []

    var body: some View {
        SectionLabel(title: "Hidden Codex folders")
        SettingsCard {
            if hidden.isEmpty {
                HStack {
                    Text("No hidden folders. Right-click a Codex folder in the sidebar to hide it.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(hidden.enumerated()), id: \.element) { idx, path in
                    if idx > 0 { CardDivider() }
                    HiddenFolderRow(path: path) {
                        appState.showCodexRoot(path: path)
                        reload()
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: appState.projects) { _, _ in reload() }
    }

    private func reload() {
        hidden = appState.hiddenCodexRoots()
    }
}

private struct HiddenFolderRow: View {
    let path: String
    let onShow: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Text(path)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button("Show", action: onShow)
                .buttonStyle(SheetCancelButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ResetLocalOverridesRow: View {
    @EnvironmentObject var appState: AppState
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset local overrides")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.94))
                Text("Permanently delete all local pins, archives, custom titles, project overrides and hidden Codex folders. The app will resync from Codex on next refresh. Codex's data is not affected.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Reset") { presentConfirmation() }
                .buttonStyle(SheetDestructiveButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func presentConfirmation() {
        let counts = appState.localOverrideCounts()
        let header = NSLocalizedString(
            "This will permanently delete the following local data from this app:",
            comment: "reset local overrides body header"
        )
        let footer = NSLocalizedString(
            "After reset, the app will reload from Codex on the next refresh. Codex's data and other Codex apps are not affected. This cannot be undone.",
            comment: "reset local overrides body footer"
        )
        let lines = [
            String(format: "• %@: %d", NSLocalizedString("Pinned threads", comment: ""), counts.pins),
            String(format: "• %@: %d", NSLocalizedString("Local projects", comment: ""), counts.projects),
            String(format: "• %@: %d", NSLocalizedString("Chat-project overrides", comment: ""), counts.chatProjectOverrides),
            String(format: "• %@: %d", NSLocalizedString("Projectless markers", comment: ""), counts.projectlessThreads),
            String(format: "• %@: %d", NSLocalizedString("Local archive entries", comment: ""), counts.archives),
            String(format: "• %@: %d", NSLocalizedString("Custom titles", comment: ""), counts.titles),
            String(format: "• %@: %d", NSLocalizedString("Hidden Codex folders", comment: ""), counts.hiddenRoots)
        ].joined(separator: "\n")
        let body = "\(header)\n\n\(lines)\n\n\(footer)"
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Reset local overrides?",
            body: LocalizedStringKey(body),
            confirmLabel: "Reset",
            isDestructive: true,
            onConfirm: { appState.resetLocalOverrides() }
        )
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
                LucideIcon.auto(icon, size: 14)
                    .foregroundColor(Color(white: 0.86))
                    .frame(width: 28, height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
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
                SettingsIcon(size: 19)
                    .foregroundColor(Color(white: 0.86))
                Text("2")
                    .font(BodyFont.system(size: 9, wght: 700))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 0.30, green: 0.55, blue: 1.0)))
                    .offset(x: 10, y: 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Import another agent configuration")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Clawix detected useful preferences from another local agent on this Mac")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Button {} label: {
                Text("Import")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(true)
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
                LucideIcon.auto(open ? "chevron.up" : "chevron.down", size: 11)
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
                    LucideIcon.auto(open ? "chevron.up" : "chevron.down", size: 11)
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
                            LucideIcon(.plus, size: 11)
                            Text("Add entry")
                                .font(BodyFont.system(size: 12.5))
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
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .padding(.leading, 12)
                .padding(.vertical, 9)
            Spacer(minLength: 8)
            Button(action: onDelete) {
                LucideIcon(.trash, size: 13)
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
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            Text(text)
                .font(BodyFont.system(size: 12.5))
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
                Group {
                    if copied {
                        CheckIcon(size: 13)
                    } else {
                        CopyIconViewSquircle(
                            color: Color(white: copyHovered ? 0.94 : 0.60),
                            lineWidth: 1.0
                        )
                        .frame(width: 13, height: 13)
                    }
                }
                .foregroundColor(Color(white: copyHovered ? 0.94 : 0.60))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { copyHovered = $0 }
            .hoverHint(L10n.t("Copy"))
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
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(Palette.textPrimary)
                        Text("Use light, dark, or system appearance")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        ThemeChip(icon: "sun.max", label: "Light", isOn: theme == .light) { theme = .light }
                        ThemeChip(icon: "moon", label: "Dark", isOn: theme == .dark) { theme = .dark }
                        ThemeChip(icon: "laptopcomputer", label: "System", isOn: theme == .system) { theme = .system }
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
                LucideIcon.auto(icon, size: 11)
                Text(label)
                    .font(BodyFont.system(size: 12, wght: 500))
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
                        .font(BodyFont.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                        .frame(width: 22, alignment: .trailing)
                    Text(text)
                        .font(BodyFont.system(size: 11.5, design: .monospaced))
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
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer(minLength: 8)
                Text("Import")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                Text("Copy theme")
                    .font(BodyFont.system(size: 12, wght: 500))
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
            SliderRow(title: "Contrast", value: $contrast, range: 0...100)
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
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.5))
                Text(hex)
                    .font(BodyFont.system(size: 12, design: .monospaced))
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
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(BodyFont.system(size: 12, design: .monospaced))
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
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer(minLength: 12)
            Slider(value: $value, in: range)
                .frame(width: 220)
                .tint(Color(red: 0.30, green: 0.55, blue: 1.0))
            Text("\(Int(value))")
                .font(BodyFont.system(size: 12, wght: 500))
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
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Adjust the base size used for the Clawix interface")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                TextField("", text: $value)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(BodyFont.system(size: 12, design: .monospaced))
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
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Settings page

private struct ConfigurationPage: View {
    @EnvironmentObject var appState: AppState
    @State private var depsEnabled: Bool = true
    @State private var configScope: String = "User settings"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Settings",
                subtitle: "Configure the approval policy and sandbox settings. Learn more"
            )

            Text("Custom config.toml settings")
                .font(BodyFont.system(size: 13, wght: 600))
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
                Button {
                    SettingsUtilities.openConfigToml(scope: configScope, selectedProject: appState.selectedProject)
                } label: {
                    HStack(spacing: 4) {
                        Text("Open config.toml")
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        LucideIcon(.arrowUpRight, size: 10)
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            .liftWhenSettingsDropdownOpen()

            SectionLabel(title: "Permissions")
            SettingsCard {
                PermissionToggleRow(
                    mode: .defaultPermissions,
                    title: "Default permissions",
                    detail: "By default, Clawix can read and edit files in your workspace. It can request additional access when needed."
                )
                CardDivider()
                PermissionToggleRow(
                    mode: .autoReview,
                    title: "Automatic review",
                    detail: "Clawix can read and edit files in your workspace. Clawix automatically reviews requests for additional access. Auto-review may make mistakes. Learn more about the elevated risks."
                )
                CardDivider()
                PermissionToggleRow(
                    mode: .fullAccess,
                    title: "Full access",
                    detail: "When Clawix runs with full access, it can edit any file on your computer and run commands over the network without your authorization. This significantly increases the risk of data loss, leaks, or unexpected behavior. Learn more about the elevated risks."
                )
            }

            SectionLabel(title: "Workspace dependencies")
            SettingsCard {
                HStack {
                    Text("Current version")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Text(AppVersion.displayString)
                        .font(BodyFont.system(size: 12, design: .monospaced))
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
                    primaryLabel: "Diagnose",
                    onPrimary: { SettingsUtilities.revealDiagnosticsFolder() }
                )
                CardDivider()
                ReinstallRow()
            }
        }
    }
}

/// Visual toggle that behaves like a radio inside the Permissions group:
/// tapping an inactive row promotes its mode to the active one; tapping
/// the already-active row is a no-op so there's always a mode selected.
private struct PermissionToggleRow: View {
    @EnvironmentObject var appState: AppState
    let mode: PermissionMode
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        let binding = Binding<Bool>(
            get: { appState.permissionMode == mode },
            set: { newValue in
                guard newValue else { return }
                appState.permissionMode = mode
            }
        )
        ToggleRow(title: title, detail: detail, isOn: binding)
    }
}

private struct DeprecationBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(.circleAlert, size: 13)
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
                .font(BodyFont.system(size: 12, wght: 500))
                HStack(spacing: 0) {
                    Text("Enable it with ").foregroundColor(Color(white: 0.75))
                    InlineCode("--enable multi_agent")
                    Text(" or ").foregroundColor(Color(white: 0.75))
                    InlineCode("[features].multi_agent")
                    Text(" in config.toml. See").foregroundColor(Color(white: 0.75))
                }
                .font(BodyFont.system(size: 11.5, wght: 500))
                HStack(spacing: 4) {
                    LucideIcon(.globe, size: 11)
                        .foregroundColor(Palette.pastelBlue)
                    Text("Toggle experimental features by editing the configuration file.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.pastelBlue)
                    Text("for details.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
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
            .font(BodyFont.system(size: 11.5, design: .monospaced))
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
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Removes the local package, fetches it fresh, and reloads the tools")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Button {} label: {
                HStack(spacing: 5) {
                    LucideIcon(.arrowDown, size: 11)
                    Text("Reinstall")
                        .font(BodyFont.system(size: 12, wght: 600))
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
            .disabled(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Personalization page

private struct PersonalizationPage: View {
    @EnvironmentObject var flags: FeatureFlags
    @EnvironmentObject var appState: AppState
    @State private var expanded: Bool = false
    @State private var instructions: String = ""
    @State private var savedSnapshot: String = ""
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil
    @State private var didLoad: Bool = false

    private var isDirty: Bool { instructions != savedSnapshot }

    private func localizedPersonalityLabel(_ personality: Personality) -> String {
        switch personality {
        case .friendly: return L10n.t("Friendly")
        case .pragmatic: return L10n.t("Pragmatic")
        }
    }

    private func localizedPersonalityBlurb(_ personality: Personality) -> String {
        switch personality {
        case .friendly: return L10n.t("Warm, collaborative, and helpful")
        case .pragmatic: return L10n.t("Concise, task-focused, and direct")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Personalization")

            SettingsCard {
                DropdownRow(
                    title: "Personality",
                    detail: "Choose a default tone for Clawix's responses",
                    options: Personality.allCases.map { ($0.rawValue, localizedPersonalityLabel($0)) },
                    selection: Binding(
                        get: { appState.personality.rawValue },
                        set: { newValue in
                            if let next = Personality(rawValue: newValue) {
                                appState.personality = next
                            }
                        }
                    ),
                    descriptionForOption: { key in
                        Personality(rawValue: key).map { localizedPersonalityBlurb($0) }
                    }
                )
            }
            .padding(.bottom, 28)

            Text("Custom instructions")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Give Codex extra instructions and context for your project. Learn more")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                InstructionsTextEditor(
                    text: $instructions,
                    isEditable: didLoad || loadError != nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                ExpandIconButton { expanded = true }
                    .padding(8)
            }
            .frame(height: 240)

            HStack(spacing: 10) {
                if let loadError {
                    Text("Could not load AGENTS.md: \(loadError)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                } else if let saveError {
                    Text("Save failed: \(saveError)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                } else if isDirty {
                    Text("Unsaved changes")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                Button { save() } label: {
                    Text("Save")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(isDirty ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isDirty ? 0.12 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isDirty)
            }
            .padding(.top, 14)

            if flags.isVisible(.secrets) {
                SecretsCodexInjectionCard()
                    .padding(.top, 28)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $expanded) {
            InstructionsExpandedSheet(text: $instructions, isPresented: $expanded)
        }
    }

    private func load() {
        do {
            let text = try CodexInstructionsFile.read()
            instructions = text
            savedSnapshot = text
            loadError = nil
            didLoad = true
        } catch {
            loadError = error.localizedDescription
            didLoad = false
        }
    }

    private func save() {
        do {
            try CodexInstructionsFile.write(instructions)
            savedSnapshot = instructions
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct InstructionsTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerInsets = NSEdgeInsets(top: 40, left: 0, bottom: 8, right: 0)

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let bigSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: bigSize)
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = InstructionsNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 12)
        textView.string = text
        textView.isEditable = isEditable

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: InstructionsTextEditor
        init(_ parent: InstructionsTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let snapshot = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != snapshot {
                    self.parent.text = snapshot
                }
            }
        }
    }
}

private struct ExpandIconButton: View {
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            CornerBracketsIcon(size: 12, variant: .expanded, lineWidth: 1.5)
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
        .hoverHint(L10n.t("Edit in large view"))
    }
}

/// NSTextView subclass that yields its I-beam cursor in the top-right
/// corner so the SwiftUI overlay button (`ExpandIconButton`) can show
/// `.pointingHand` reliably. Overriding the cursor inside the textview
/// itself avoids racing with NSTextView's own cursor management on every
/// `mouseMoved` (the previous monitor-based attempt flickered for that
/// reason).
private final class InstructionsNSTextView: NSTextView {
    /// Square corner reserved for the overlay button, in screen-stable
    /// (visibleRect) coordinates. Matches `ExpandIconButton.padding(8)`
    /// plus its content size with a couple of pixels of slack.
    private let pointerCornerSize: CGFloat = 40

    private var pointerCornerRect: NSRect {
        let visible = visibleRect
        let s = pointerCornerSize
        return NSRect(x: visible.maxX - s, y: visible.minY, width: s, height: s)
    }

    override func cursorUpdate(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pointerCornerRect.contains(p) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pointerCornerRect.contains(p) {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }
}

private struct InstructionsExpandedSheet: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Custom instructions")
                    .font(BodyFont.system(size: 14, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    LucideIcon(.x, size: 11)
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
                .font(BodyFont.system(size: 13, design: .monospaced))
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
                        .font(BodyFont.system(size: 12, wght: 600))
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
                    LucideIcon.auto(category.iconName, size: 11)
                        .foregroundColor(Palette.textSecondary)
                    Text("Coming soon")
                        .font(BodyFont.system(size: 13, wght: 500))
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

private enum UsageDisplayMode: String, CaseIterable {
    case used
    case remaining
}

private struct UsagePage: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("clawix.settings.usage.displayMode") private var displayMode: UsageDisplayMode = .used

    /// Per-bucket entries other than the base "codex" id (which mirrors
    /// the general snapshot we already render at the top). Sorted by
    /// limit name so the order is stable across renders.
    private var perModelBuckets: [(id: String, snapshot: RateLimitSnapshot)] {
        appState.rateLimitsByLimitId
            .filter { $0.key != "codex" }
            .sorted { ($0.value.limitName ?? $0.key) < ($1.value.limitName ?? $1.key) }
            .map { ($0.key, $0.value) }
    }

    private var hasAnyBars: Bool {
        let general = appState.rateLimits.map { $0.primary != nil || $0.secondary != nil } ?? false
        return general || !perModelBuckets.isEmpty
    }

    private var usageOptions: [(UsageDisplayMode, String)] {
        [(.used, "Used"), (.remaining, "Remaining")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Usage")

            if let snapshot = appState.rateLimits, snapshot.primary != nil || snapshot.secondary != nil {
                HStack(alignment: .center) {
                    Text("General usage limits")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.leading, 3)
                    Spacer()
                    if hasAnyBars {
                        SlidingSegmented(selection: $displayMode, options: usageOptions)
                            .frame(width: 190)
                    }
                }
                .padding(.bottom, 14)

                SettingsCard {
                    UsageBarStack(snapshot: snapshot, mode: displayMode)
                }
            }

            ForEach(perModelBuckets, id: \.id) { entry in
                Text(verbatim: SettingsLimitsFormatter.perModelSectionTitle(name: entry.snapshot.limitName ?? entry.id))
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.leading, 3)
                    .padding(.bottom, 14)
                    .padding(.top, 28)
                SettingsCard {
                    UsageBarStack(snapshot: entry.snapshot, mode: displayMode)
                }
            }

            if let credits = appState.rateLimits?.credits {
                SectionLabel(title: "Credit")
                SettingsCard {
                    CreditRow(title: SettingsLimitsFormatter.creditTitle(for: credits),
                              detail: "Use credit to send messages when you hit your usage limits.")
                }
            }

            if !hasAnyBars && appState.rateLimits?.credits == nil {
                SettingsCard {
                    HStack(alignment: .center, spacing: 12) {
                        UsageIcon(size: 15, lineWidth: 1.7)
                            .foregroundColor(Palette.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "No usage data yet")
                                .font(BodyFont.system(size: 13, wght: 600))
                                .foregroundColor(Palette.textPrimary)
                            Text(verbatim: "Usage limits appear here after the runtime reports a rate-limit snapshot.")
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .padding(.top, 14)
            }
        }
    }
}

private struct UsageBarStack: View {
    let snapshot: RateLimitSnapshot
    let mode: UsageDisplayMode

    private var windows: [RateLimitWindow] {
        [snapshot.primary, snapshot.secondary].compactMap { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(windows.enumerated()), id: \.offset) { entry in
                if entry.offset > 0 {
                    CardDivider()
                }
                UsageBarRow(
                    title: SettingsLimitsFormatter.detailedWindowLabel(for: entry.element),
                    detail: SettingsLimitsFormatter.detailedResetLabel(for: entry.element),
                    percent: entry.element.usedPercent,
                    mode: mode
                )
            }
        }
    }
}

private struct UsageBarRow: View {
    let title: String
    let detail: String
    let percent: Int
    let mode: UsageDisplayMode

    private var displayPercent: Int {
        switch mode {
        case .used: return percent
        case .remaining: return max(0, 100 - percent)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 90, height: 7)
                    if displayPercent > 0 {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .frame(width: max(7, 90 * CGFloat(displayPercent) / 100), height: 7)
                    }
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: "\(displayPercent) %")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(.white)
                    Text(mode == .used ? "used" : "remaining")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

/// Canonical segmented selector for the macOS app.
///
/// Visual: outer squircle (cornerRadius 13, dark fill, hairline stroke)
/// with a single inner squircle indicator (cornerRadius 10, white fill)
/// that slides between options. No `Capsule()`, no `matchedGeometryEffect`
/// (unreliable when the binding writes through `@AppStorage` on macOS).
///
/// The indicator's `.offset` is animated with `.snappy(duration: 0.32)`
/// so the highlight glides left↔right instead of jumping or fading.
///
/// Sizing: height is fixed (default 30); width comes from the parent.
/// In a row layout pin it with `.frame(width: 190)` (or any intrinsic
/// width that fits all labels). When the selector should fill its
/// container — full-width form fields, MCP transport, etc. — leave the
/// width unset and the inner `GeometryReader` handles the math.
///
/// All chips have equal width by construction. If labels differ in
/// length, size the segmented to the longest one.
///
/// Use this whenever you need a 2-N choice picker in the macOS chrome.
/// Don't roll a new one with `Capsule` or `Picker(.segmented)`.
struct SlidingSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var animation: Animation = .snappy(duration: 0.32, extraBounce: 0)
    var height: CGFloat = 30
    var fontSize: CGFloat = 11.5

    private var selectedIndex: CGFloat {
        CGFloat(options.firstIndex(where: { $0.0 == selection }) ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 3
            let chipW = max(0, (geo.size.width - inset * 2) / CGFloat(options.count))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: chipW, height: height - inset * 2)
                    .offset(x: inset + selectedIndex * chipW, y: inset)
                    .animation(animation, value: selection)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                        let isOn = opt.0 == selection
                        Button {
                            selection = opt.0
                        } label: {
                            Text(verbatim: opt.1)
                                .font(BodyFont.system(size: fontSize, weight: isOn ? .medium : .regular))
                                .foregroundColor(isOn ? Palette.textPrimary : Palette.textSecondary)
                                .frame(width: chipW, height: height - inset * 2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(inset)
            }
        }
        .frame(height: height)
    }
}

private struct CreditRow: View {
    let title: String
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Browser usage page

private struct BrowserUsagePage: View {
    @AppStorage(BrowserPermissionPolicy.approvalStorageKey) private var approval: String = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue
    @AppStorage("clawix.browser.historyApproval") private var history: String = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue
    @State private var browsingData: BrowserPermissionPolicy.BrowsingDataKind = .all
    @State private var clearStatus: String?
    @State private var clearingBrowsingData = false
    @State private var blockedDomains: [String] = []
    @State private var allowedDomains: [String] = []

    private var browsingDataOptions: [(BrowserPermissionPolicy.BrowsingDataKind, String)] {
        [
            (.all, "Clear all browsing data"),
            (.cache, "Clear cache"),
            (.cookies, "Clear cookies")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Browser usage")

            /*
            Text("Plugins")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            SettingsCard {
                BrowserPluginRow(title: "Browser Use",
                                 detail: "Control the in-app browser with Clawix")
            }
            */

            SectionLabel(title: "Browser")
            SettingsCard {
                SettingsRow {
                    RowLabel(
                        title: "Browsing data",
                        detail: "Clear site data and the cache of the in-app browser"
                    )
                } trailing: {
                    HStack(spacing: 8) {
                        SettingsDropdown(
                            options: browsingDataOptions,
                            selection: $browsingData,
                            minWidth: 190
                        )
                        Button(clearingBrowsingData ? "Clearing…" : "Clear") {
                            clearSelectedBrowsingData()
                        }
                        .buttonStyle(.borderless)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(clearingBrowsingData ? Palette.textSecondary : Palette.textPrimary)
                        .disabled(clearingBrowsingData)
                    }
                }
                .liftWhenSettingsDropdownOpen()
            }
            if let clearStatus {
                InfoBanner(text: clearStatus, kind: .ok)
                    .padding(.top, 10)
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                DropdownRow(
                    title: "Approval",
                    detail: "Choose whether Clawix asks for permission before opening websites",
                    options: [
                        (BrowserPermissionPolicy.Approval.alwaysAsk.rawValue, "Always ask"),
                        (BrowserPermissionPolicy.Approval.alwaysAllow.rawValue, "Always allow"),
                        (BrowserPermissionPolicy.Approval.alwaysBlock.rawValue, "Always block")
                    ],
                    selection: $approval
                )
                CardDivider()
                DropdownRow(
                    title: "History",
                    detail: "Choose whether Clawix asks for approval before accessing your history",
                    options: [
                        (BrowserPermissionPolicy.Approval.alwaysAsk.rawValue, "Always ask"),
                        (BrowserPermissionPolicy.Approval.alwaysAllow.rawValue, "Always allow"),
                        (BrowserPermissionPolicy.Approval.alwaysBlock.rawValue, "Always block")
                    ],
                    selection: $history
                )
            }

            DomainListSection(title: "Blocked domains",
                              subtitle: "Clawix will never open these sites",
                              emptyText: "No blocked domains",
                              domains: $blockedDomains,
                              list: .blocked,
                              onChanged: reloadDomains)
                .padding(.top, 28)

            DomainListSection(title: "Allowed domains",
                              subtitle: "Domains that open without prompting",
                              emptyText: "No allowed domains",
                              domains: $allowedDomains,
                              list: .allowed,
                              onChanged: reloadDomains)
                .padding(.top, 28)
        }
        .onAppear {
            normalizeBrowserPermissionValues()
            reloadDomains()
        }
    }

    private func normalizeBrowserPermissionValues() {
        let valid = [
            BrowserPermissionPolicy.Approval.alwaysAsk.rawValue,
            BrowserPermissionPolicy.Approval.alwaysAllow.rawValue,
            BrowserPermissionPolicy.Approval.alwaysBlock.rawValue,
        ]
        if !valid.contains(approval) { approval = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue }
        if !valid.contains(history) { history = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue }
    }

    private func reloadDomains() {
        blockedDomains = BrowserPermissionPolicy.blockedDomains
        allowedDomains = BrowserPermissionPolicy.allowedDomains
    }

    private func clearSelectedBrowsingData() {
        clearingBrowsingData = true
        clearStatus = nil
        let selected = browsingData
        BrowserPermissionPolicy.clearBrowsingData(selected) {
            clearingBrowsingData = false
            clearStatus = "\(selected.rawValue) completed."
            ToastCenter.shared.show(clearStatus ?? "Browsing data cleared")
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
                LucideIcon(.send, size: 14)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(-12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            CheckIcon(size: 13)
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
    @Binding var domains: [String]
    let list: BrowserPermissionPolicy.DomainList
    let onChanged: () -> Void

    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {
                    addDomain()
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.plus, size: 11)
                        Text("Add")
                            .font(BodyFont.system(size: 12, wght: 600))
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
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(subtitle)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("example.com", text: $draft)
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary)
                        .onSubmit(addDomain)
                    Button("Add") {
                        addDomain()
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if let error {
                    CardDivider()
                    Text(error)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                if domains.isEmpty {
                    CardDivider()
                    HStack {
                        Spacer()
                        Text(emptyText)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                } else {
                    ForEach(domains, id: \.self) { domain in
                        CardDivider()
                        HStack(spacing: 10) {
                            Text(verbatim: domain)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            Spacer()
                            Button("Remove") {
                                BrowserPermissionPolicy.removeDomain(domain, from: list)
                                onChanged()
                            }
                            .buttonStyle(.borderless)
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
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

    private func addDomain() {
        guard let domain = BrowserPermissionPolicy.addDomain(draft, to: list) else {
            error = "Enter a valid domain such as example.com."
            return
        }
        error = nil
        draft = ""
        switch list {
        case .blocked:
            domains = BrowserPermissionPolicy.blockedDomains
        case .allowed:
            domains = BrowserPermissionPolicy.allowedDomains
        }
        onChanged()
        ToastCenter.shared.show("Added \(domain)")
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
                    options: [(.merge, "Merge"), (.squash, "Squash")],
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
                placeholder: "Add a guideline for the commit message...",
                storageKey: "clawix.git.commitInstructions"
            )
            .padding(.top, 28)

            CommitInstructionsBlock(
                title: "Pull request instructions",
                detail: "Added to the prompts that generate the PR title and description",
                placeholder: "Add a guideline for the pull request...",
                storageKey: "clawix.git.pullRequestInstructions"
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
                .font(BodyFont.system(size: 12, design: monospaced ? .monospaced : .default))
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
    let storageKey: String
    @State private var text: String = ""

    init(title: LocalizedStringKey, detail: LocalizedStringKey, placeholder: String, storageKey: String) {
        self.title = title
        self.detail = detail
        self.placeholder = placeholder
        self.storageKey = storageKey
        _text = State(initialValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(detail)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                Button {
                    UserDefaults.standard.set(text, forKey: storageKey)
                    ToastCenter.shared.show("Instructions saved")
                } label: {
                    Text("Save")
                        .font(BodyFont.system(size: 12, wght: 600))
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
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(BodyFont.system(size: 12, wght: 500))
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

// MARK: - MCP servers page
//
// Lists every `[mcp_servers.<name>]` declared in `~/.codex/config.toml`,
// with toggles to enable/disable each entry and a sheet (popup) to
// add or edit them. Persistence flows through `MCPServersStore`, which
// preserves the rest of `config.toml` byte-for-byte and only rewrites
// the MCP blocks.
private struct MCPPage: View {
    @StateObject private var store: MCPServersStore = .shared
    @State private var sheet: MCPSheetItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MCP servers")
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                (
                    Text("Connect external tools and data sources.")
                        .foregroundColor(Palette.textSecondary)
                    + Text(" ")
                    + Text("Learn more.")
                        .foregroundColor(Palette.pastelBlue)
                )
                .font(BodyFont.system(size: 12.5))
            }
            .padding(.bottom, 26)

            HStack {
                Text("Servers")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {
                    sheet = .init(
                        server: MCPServerConfig(),
                        isExisting: false
                    )
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.plus, size: 11)
                        Text("Add server")
                            .font(BodyFont.system(size: 12, wght: 600))
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

            if store.servers.isEmpty {
                MCPEmptyState(onAdd: {
                    sheet = .init(
                        server: MCPServerConfig(),
                        isExisting: false
                    )
                })
            } else {
                VStack(spacing: 7) {
                    ForEach(store.servers) { server in
                        MCPServerRow(
                            server: server,
                            isOn: Binding(
                                get: { server.enabled },
                                set: { store.toggleEnabled(server, isOn: $0) }
                            ),
                            onConfigure: {
                                sheet = .init(server: server, isExisting: true)
                            }
                        )
                    }
                }
            }

            if let err = store.lastError {
                Text(err)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.45))
                    .padding(.top, 12)
            }
        }
        .sheet(item: $sheet) { item in
            MCPEditorSheet(
                store: store,
                initial: item.server,
                isExisting: item.isExisting,
                onClose: { sheet = nil }
            )
        }
    }
}

/// Identifiable wrapper so SwiftUI's `.sheet(item:)` can present the
/// editor for either a new or an existing server.
private struct MCPSheetItem: Identifiable {
    let id = UUID()
    let server: MCPServerConfig
    let isExisting: Bool
}

private struct MCPServerRow: View {
    let server: MCPServerConfig
    @Binding var isOn: Bool
    let onConfigure: () -> Void

    @State private var configHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(transportSummary)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onConfigure) {
                SettingsIcon(size: 18)
                    .foregroundColor(Color(white: configHovered ? 0.94 : 0.62))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { configHovered = $0 }
            .hoverHint(L10n.t("Configure"))
            PillToggle(isOn: $isOn)
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

    private var transportSummary: String {
        switch server.transport {
        case .http:
            let u = server.url
            return u.isEmpty ? "Streamable HTTP" : "HTTP · \(u)"
        case .stdio:
            let c = server.command
            return c.isEmpty ? "STDIO" : "STDIO · \(c)"
        }
    }
}

private struct MCPEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("No MCP servers connected yet.")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Button(action: onAdd) {
                HStack(spacing: 5) {
                    LucideIcon(.plus, size: 11)
                    Text("Add server")
                        .font(BodyFont.system(size: 12, wght: 600))
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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
