import SwiftUI

// MARK: - Settings categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    // case appearance  // hidden temporarily
    case configuration
    case personalization
    case shortcuts
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
    case databaseWorkbench
    case secrets
    case identity
    case claw
    case telegram
    case apps

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general:          return "General"
        // case .appearance:       return "Appearance"
        case .configuration:    return "Settings"
        case .personalization:  return "Personalization"
        case .shortcuts:        return "Keyboard Shortcuts"
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
        case .databaseWorkbench: return "Database Workbench"
        case .secrets:          return "Secrets"
        case .identity:         return "Identity"
        case .claw:           return "ClawJS"
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
        case .shortcuts:        return "keyboard"
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
        case .databaseWorkbench: return "cylinder.split.1x2"
        case .secrets:          return "lock.shield"
        case .identity:         return "fingerprint"
        case .claw:           return "shippingbox"
        case .telegram:         return "paperplane.fill"
        case .apps:             return "square.grid.2x2"
        }
    }

    var gatedFeature: AppFeature? {
        switch self {
        case .dictation:        return .voiceToText
        case .quickAsk:         return .quickAsk
        case .secrets:          return .secrets
        case .mcp:              return .mcp
        case .localModels:      return .localModels
        case .browserUsage:     return .browserUsage
        case .git:              return .git
        case .machines:         return .remoteMesh
        case .skills:           return .skills
        case .screenTools:      return .screenTools
        case .macUtilities:     return .macUtilities
        case .databaseWorkbench: return .databaseWorkbench
        case .identity:         return .identity
        case .claw:           return .claw
        case .telegram:         return .telegram
        case .apps:             return .apps
        default:                return nil
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
            // this row is nav chrome — the actual secrets state is reflected on
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
                    case .shortcuts:       ShortcutsSettingsPage()
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
                    case .databaseWorkbench: DatabaseWorkbenchSettingsPage()
                    case .mcp:             MCPPage()
                    case .machines:        HostsPage()
                    case .secrets:         SecretsSettingsPage()
                    case .identity:        IdentitySettingsPage()
                    case .claw:          ClawJSSettingsPage()
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

// MARK: - PillToggle (kept here, every other shared building block lives in SettingsKit.swift)


/// Canonical settings/config dropdown. Wide capsule trigger with a clearly
/// visible dark fill, optional leading glyph and a chevron on the right.
/// The popup uses the project-wide menu chrome via `menuStandardBackground()`
/// (anchorPreference + softNudge transition), never SwiftUI's `Menu` or
/// `.popover`, so it never inherits system arrows or chrome.
/// Uses the project-wide dropdown menu style.

/// Bubbles up "is any descendant `SettingsDropdown` currently open?".
/// Combined via OR so a single open dropdown anywhere in the subtree wins.


/// Standard settings row with a label on the left and a control
/// (dropdown, button, etc.) on the right. The label takes whatever
/// horizontal space is left after the trailing control sizes itself
/// to its natural content. This keeps every dropdown wide enough for
/// its longest option and lets rows that share the trailing slot with
/// extra widgets (e.g. the Audio Input meter next to the device
/// dropdown) grow as needed without forcing a global percentage.


/// Resolves an app icon view for known "open with" targets. Returns nil when
/// the option name isn't a recognised app, so the dropdown row falls back to
/// a plain text trigger.
func openTargetIcon(for name: String) -> AnyView? {
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


// MARK: - General page


// MARK: - Apariencia page


// MARK: - Settings page


/// Visual toggle that behaves like a radio inside the Permissions group:
/// tapping an inactive row promotes its mode to the active one; tapping
/// the already-active row is a no-op so there's always a mode selected.


// MARK: - Personalization page


/// NSTextView subclass that yields its I-beam cursor in the top-right
/// corner so the SwiftUI overlay button (`ExpandIconButton`) can show
/// `.pointingHand` reliably. Overriding the cursor inside the textview
/// itself avoids racing with NSTextView's own cursor management on every
/// `mouseMoved` (the previous monitor-based attempt flickered for that
/// reason).


// MARK: - Placeholder page (categories without a screenshot yet)


// MARK: - Uso page


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


// MARK: - Browser usage page


// MARK: - Git page


// MARK: - MCP servers page
//
// Lists every MCP server exposed by the ClawJS JSON adapter, with toggles
// to enable/disable each entry and a sheet (popup) to add or edit them.
// Persistence flows through `MCPServersStore`; the GUI never parses or
// rewrites Codex-owned configuration directly.

/// Identifiable wrapper so SwiftUI's `.sheet(item:)` can present the
/// editor for either a new or an existing server.
