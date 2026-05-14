import SwiftUI
import AppKit

// MARK: - Anchor keys

struct PlusButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ModelButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct PermissionsButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ProjectPickerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ContextIndicatorAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Project picker popup

struct ProjectPickerPopup: View {
    @Binding var isPresented: Bool
    let projects: [Project]
    let selectedId: UUID?
    let onSelect: (Project?) -> Void
    let onCreate: () -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    static let popupWidth: CGFloat = 320
    static let scrollMaxHeight: CGFloat = 220

    private var filtered: [Project] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return projects }
        return projects.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, MenuStyle.rowHorizontalPadding)
                .padding(.top, MenuStyle.menuVerticalPadding + 2)
                .padding(.bottom, 4)

            scrollableList

            MenuStandardDivider()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                ProjectPickerRow(
                    label: String(localized: "Add project", bundle: AppLocale.bundle, locale: AppLocale.current),
                    iconName: "folder.badge.plus",
                    isSelected: false
                ) { onCreate() }

                ProjectPickerRow(
                    label: "No project",
                    iconName: "folder.badge.minus",
                    isSelected: selectedId == nil
                ) { onSelect(nil) }
            }
            .padding(.bottom, MenuStyle.menuVerticalPadding)
        }
        .frame(width: Self.popupWidth, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
        .onAppear {
            searchFocused = true
            DispatchQueue.main.async { searchFocused = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: MenuStyle.rowIconLabelSpacing) {
            SearchIcon(size: 11)
                .foregroundColor(MenuStyle.rowSubtle)
                .frame(width: 18, alignment: .center)
            TextField(
                "",
                text: $query,
                prompt: Text(String(localized: "Search projects", bundle: AppLocale.bundle, locale: AppLocale.current))
                    .foregroundColor(MenuStyle.rowSubtle)
            )
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 11.5))
            .foregroundColor(MenuStyle.rowText)
            .focused($searchFocused)
            .onSubmit {
                if let first = filtered.first { onSelect(first) }
            }
        }
        .padding(.vertical, MenuStyle.rowVerticalPadding - 1)
    }

    @ViewBuilder
    private var scrollableList: some View {
        if filtered.isEmpty {
            Text(String(localized: "No matches", bundle: AppLocale.bundle, locale: AppLocale.current))
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(MenuStyle.rowSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MenuStyle.rowHorizontalPadding + 18 + MenuStyle.rowIconLabelSpacing)
                .padding(.vertical, 12)
        } else {
            ThinScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { project in
                        ProjectPickerRow(
                            label: project.name,
                            iconName: "folder",
                            isSelected: selectedId == project.id
                        ) {
                            onSelect(project)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: Self.scrollMaxHeight)
        }
    }
}

struct ProjectPickerRow: View {
    let label: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                IconImage(iconName, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Standard 1-pt divider for menu rows. Indents 14pt to mirror row padding.
struct MenuStandardDivider: View {
    var body: some View {
        Rectangle()
            .fill(MenuStyle.dividerColor)
            .frame(height: 1)
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
    }
}

// MARK: - Permissions menu popup

struct PermissionsMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var selection: PermissionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PermissionMode.allCases) { mode in
                PermissionsMenuRow(
                    mode: mode,
                    isSelected: selection == mode
                ) {
                    selection = mode
                    isPresented = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(minWidth: 244, alignment: .leading)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }
}

struct PermissionsMenuRow: View {
    let mode: PermissionMode
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                LucideIcon.auto(mode.iconName, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(mode.label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 10)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Context indicator (left of the model button)

/// Small donut showing how full the active model's context window is.
/// Hover surfaces the detailed breakdown tooltip.
struct ContextIndicatorButton: View {
    let usage: ContextUsage
    @Binding var isHovering: Bool

    var body: some View {
        ContextRing(fraction: usage.usedFraction)
            .frame(width: 13, height: 13)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .anchorPreference(key: ContextIndicatorAnchorKey.self, value: .bounds) { $0 }
            .onHover { hovering in
                isHovering = hovering
            }
            .accessibilityLabel(contextA11yLabel(usage: usage))
    }
}

struct ContextRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 2.0)
            Circle()
                .trim(from: 0, to: max(0.02, min(1.0, fraction)))
                .stroke(
                    Color(white: 0.92),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
        }
    }
}

struct ContextTooltip: View {
    let usage: ContextUsage

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Context window:")
                .font(BodyFont.system(size: 11.5, weight: .light))
                .foregroundColor(Color(white: 0.55))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if usage.contextWindow != nil {
                Text(percentLine)
                    .font(BodyFont.system(size: 12, weight: .light))
                    .foregroundColor(Color(white: 0.94))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(tokensLine)
                .font(BodyFont.system(size: 12, weight: .light))
                .foregroundColor(Color(white: 0.94))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text("Clawix automatically compacts its context")
                .font(BodyFont.system(size: 11.5, weight: .regular))
                .foregroundColor(Color(white: 0.94))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 185)
        .menuStandardBackground()
    }

    private var percentLine: String {
        let used = Int((usage.usedFraction * 100).rounded())
        let remaining = max(0, 100 - used)
        return "\(used) % usado (\(remaining) % restante)"
    }

    private var tokensLine: String {
        let usedStr = formatTokens(usage.usedTokens)
        if let window = usage.contextWindow {
            return "\(usedStr)/\(formatTokens(window)) tokens used"
        }
        return "\(usedStr) tokens used"
    }

    private func formatTokens(_ value: Int64) -> String {
        if value < 1_000 {
            return "\(value)"
        }
        let k = Double(value) / 1_000.0
        if k < 10 {
            return String(format: "%.1f k", k)
        }
        return "\(Int(k.rounded())) k"
    }
}

func contextA11yLabel(usage: ContextUsage) -> String {
    let used = Int((usage.usedFraction * 100).rounded())
    if usage.contextWindow == nil {
        return "Context window: \(usage.usedTokens) tokens used"
    }
    return "Context window: \(used) % used"
}

// MARK: - Model menu popup

enum ModelSubmenu { case none, model, otherModels, speed }

enum ModelChevronRow: Hashable { case gpt, velocidad, otrosModelos }

struct ModelChevronAnchorsKey: PreferenceKey {
    static var defaultValue: [ModelChevronRow: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ModelChevronRow: Anchor<CGRect>],
                       nextValue: () -> [ModelChevronRow: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Collects the global window-coordinate frames of every popup column
/// currently rendered (mainColumn + any visible submenu overlays). The
/// `MenuOutsideClickWatcher` consults the union as additional "inside"
/// hit area so clicks on submenu rows propagate to SwiftUI buttons
/// instead of being swallowed as outside-clicks.
struct PopupFramesPref: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

struct ModelMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var runtime: AgentRuntimeChoice
    @Binding var intelligence: IntelligenceLevel
    @Binding var model: String
    @Binding var speed: SpeedLevel
    let primaryModels: [String]
    let otherModels: [String]
    let localModels: [String]

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var agentStore: AgentStore
    @ObservedObject private var flags = FeatureFlags.shared

    static let mainColumnWidth: CGFloat = 232
    private static let modelColumnWidth: CGFloat = 220
    private static let otherModelsColumnWidth: CGFloat = 200
    private static let speedColumnWidth: CGFloat = 244
    private static let columnGap: CGFloat = 6

    @State private var openSubmenu: ModelSubmenu = .none
    @State private var submenuFrames: [CGRect] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainColumn
        }
        .overlayPreferenceValue(ModelChevronAnchorsKey.self) { anchors in
            GeometryReader { proxy in
                let parentGlobalMinX = proxy.frame(in: .global).minX
                if openSubmenu == .speed, let anchor = anchors[.velocidad] {
                    let row = proxy[anchor]
                    let placement = submenuLeadingPlacement(
                        parentGlobalMinX: parentGlobalMinX,
                        row: row,
                        submenuWidth: Self.speedColumnWidth,
                        gap: Self.columnGap
                    )
                    speedColumn
                        .background(popupFrameReader)
                        .alignmentGuide(.leading) { _ in placement.offset }
                        .alignmentGuide(.top) { _ in -row.minY }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                }
                if (openSubmenu == .model || openSubmenu == .otherModels), let anchor = anchors[.gpt] {
                    let row = proxy[anchor]
                    let placement = submenuLeadingPlacement(
                        parentGlobalMinX: parentGlobalMinX,
                        row: row,
                        submenuWidth: Self.modelColumnWidth,
                        gap: Self.columnGap
                    )
                    modelSubmenuTree(parentPlacedRight: placement.placedRight)
                        .alignmentGuide(.leading) { _ in placement.offset }
                        .alignmentGuide(.top) { _ in -row.minY }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                }
            }
            .animation(.easeOut(duration: 0.18), value: openSubmenu)
        }
        .onPreferenceChange(PopupFramesPref.self) { frames in
            submenuFrames = frames
        }
        .background(
            MenuOutsideClickWatcher(
                isPresented: $isPresented,
                extraInsideTest: { [submenuFrames] point in
                    submenuFrames.contains { $0.contains(point) }
                }
            )
        )
    }

    /// `.background` content that publishes the column's global frame
    /// up to `PopupFramesPref` so the click watcher knows the submenu
    /// is still inside the popup's hit area.
    private var popupFrameReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: PopupFramesPref.self,
                value: [geo.frame(in: .global)]
            )
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            agentSection
            MenuStandardDivider()
                .padding(.vertical, 5)
            ModelMenuHeader(L10n.t("Runtime"))

            ForEach(AgentRuntimeChoice.visibleCases()) { choice in
                ModelMenuCheckRow(
                    label: choice.label,
                    isSelected: runtime == choice
                ) {
                    runtime = choice
                    if choice == .opencode, !model.contains("/") {
                        model = AgentRuntimeChoice.defaultOpenCodeModel
                    } else if choice == .codex, model.contains("/") {
                        model = "5.5"
                    }
                    isPresented = false
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .none }
                }
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuHeader(L10n.t("Intelligence"))

            ForEach(IntelligenceLevel.allCases) { level in
                ModelMenuCheckRow(
                    label: level.label,
                    isSelected: intelligence == level
                ) {
                    intelligence = level
                    isPresented = false
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .none }
                }
            }

            MenuStandardDivider()
                .padding(.vertical, 5)

            ModelMenuChevronRow(
                label: flags.isVisible(.openCode) && runtime == .opencode ? model : "GPT-\(model)",
                highlighted: openSubmenu == .model || openSubmenu == .otherModels
            ) {
                openSubmenu = (openSubmenu == .model || openSubmenu == .otherModels) ? .none : .model
            }
            .onHover { hovering in
                if hovering, openSubmenu != .otherModels { openSubmenu = .model }
            }
            .anchorPreference(key: ModelChevronAnchorsKey.self, value: .bounds) { [.gpt: $0] }

            ModelMenuChevronRow(
                label: L10n.t("Speed"),
                highlighted: openSubmenu == .speed
            ) {
                openSubmenu = openSubmenu == .speed ? .none : .speed
            }
            .onHover { hovering in
                if hovering { openSubmenu = .speed }
            }
            .anchorPreference(key: ModelChevronAnchorsKey.self, value: .bounds) { [.velocidad: $0] }

            // Local models live inline in the main column (NOT inside a
            // submenu) so their click hit area is covered by the same
            // `MenuOutsideClickWatcher` that wraps `mainColumn`.
            // Submenu overlays sit outside the watcher's bounds; the
            // watcher consumes mouseDown there as an "outside click",
            // which would close the popup before SwiftUI's button could
            // fire and the selection would silently no-op.
            if !localModels.isEmpty {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                ModelMenuHeader(L10n.t("Local models"))
                ForEach(localModels, id: \.self) { m in
                    ModelMenuCheckRow(
                        label: m,
                        isSelected: model == "ollama:\(m)"
                    ) {
                        model = "ollama:\(m)"
                        isPresented = false
                    }
                    .onHover { hovering in
                        if hovering { openSubmenu = .none }
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.mainColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    @ViewBuilder
    private func modelSubmenuTree(parentPlacedRight: Bool) -> some View {
        modelColumn
            .background(popupFrameReader)
            .overlayPreferenceValue(ModelChevronAnchorsKey.self) { anchors in
                GeometryReader { proxy in
                    let parentGlobalMinX = proxy.frame(in: .global).minX
                    if openSubmenu == .otherModels, let anchor = anchors[.otrosModelos] {
                        let row = proxy[anchor]
                        // If the modelColumn itself was forced to flip left,
                        // keep cascading to the left so the chain stays inside
                        // the window. Otherwise prefer right and only flip
                        // when it overflows.
                        let placement: (offset: CGFloat, placedRight: Bool) = {
                            if parentPlacedRight {
                                return submenuLeadingPlacement(
                                    parentGlobalMinX: parentGlobalMinX,
                                    row: row,
                                    submenuWidth: Self.otherModelsColumnWidth,
                                    gap: Self.columnGap
                                )
                            }
                            return (-(row.minX - Self.columnGap - Self.otherModelsColumnWidth), false)
                        }()
                        otherModelsColumn
                            .background(popupFrameReader)
                            .alignmentGuide(.leading) { _ in placement.offset }
                            .alignmentGuide(.top) { _ in -row.minY }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: openSubmenu)
            }
    }

    private var modelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Model"))

            if flags.isVisible(.openCode), runtime == .opencode {
                ModelMenuCheckRow(
                    label: AgentRuntimeChoice.defaultOpenCodeModel,
                    isSelected: model == AgentRuntimeChoice.defaultOpenCodeModel
                ) {
                    model = AgentRuntimeChoice.defaultOpenCodeModel
                    isPresented = false
                }
                Text("Images use a visible fallback when the model cannot read them.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(primaryModels, id: \.self) { m in
                    ModelMenuCheckRow(
                        label: "GPT-\(m)",
                        isSelected: model == m
                    ) {
                        model = m
                        isPresented = false
                    }
                    .onHover { hovering in
                        if hovering { openSubmenu = .model }
                    }
                }

                ModelMenuChevronRow(
                    label: L10n.t("Other models"),
                    highlighted: openSubmenu == .otherModels
                ) {
                    openSubmenu = openSubmenu == .otherModels ? .model : .otherModels
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .otherModels }
                }
                .anchorPreference(key: ModelChevronAnchorsKey.self, value: .bounds) { [.otrosModelos: $0] }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.modelColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    private var otherModelsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Other models"))

            ForEach(otherModels, id: \.self) { m in
                ModelMenuCheckRow(
                    label: "GPT-\(m)",
                    isSelected: model == m
                ) {
                    model = m
                    isPresented = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.otherModelsColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    private var speedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Speed"))

            ForEach(SpeedLevel.allCases) { s in
                ModelMenuDescriptionRow(
                    label: s.label,
                    description: s.description,
                    isSelected: speed == s
                ) {
                    speed = s
                    isPresented = false
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.speedColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    /// Top section of the model menu: lets the user pick which Agent
    /// the next composer send routes to. Selecting an agent also writes
    /// the resolved runtime + model so existing code paths that read
    /// `selectedAgentRuntime` / `selectedModel` keep working without a
    /// migration. The built-in Codex agent sits at the top of the list.
    private var agentSection: some View {
        let agents = flags.isVisible(.openCode)
            ? agentStore.agents
            : agentStore.agents.filter { $0.runtime == .codex }
        return VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(L10n.t("Agent"))
            ForEach(agents) { agent in
                ModelMenuCheckRow(
                    label: agent.name,
                    isSelected: appState.selectedAgentId == agent.id
                ) {
                    appState.selectedAgentId = agent.id
                    if let mappedRuntime = AgentRuntimeChoice(rawValue: agent.runtime == .codex ? "codex" : "opencode") {
                        appState.selectedAgentRuntime = mappedRuntime
                    }
                    if !agent.model.isEmpty {
                        appState.selectedModel = agent.model
                    }
                    isPresented = false
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .none }
                }
            }
        }
    }
}

struct ModelMenuHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11))
            .foregroundColor(MenuStyle.headerText)
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }
}

struct ModelMenuCheckRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 13)
                        .foregroundColor(MenuStyle.rowText)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct ModelMenuChevronRow: View {
    let label: String
    let highlighted: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                LucideIcon(.chevronRight, size: 13)
                    .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                    .foregroundColor(MenuStyle.rowSubtle)
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding + MenuStyle.rowTrailingIconExtra)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(
                active: highlighted || hovered,
                intensity: highlighted ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            ))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct ModelMenuDescriptionRow: View {
    let label: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(MenuStyle.rowText)
                    Text(description)
                        .font(BodyFont.system(size: 10))
                        .foregroundColor(MenuStyle.rowSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if isSelected {
                    CheckIcon(size: 13)
                        .foregroundColor(MenuStyle.rowText)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Add menu popup

struct AddMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var planMode: Bool
    let plugins: [Plugin]
    let onPickFiles: () -> Void

    @State private var showComplementos = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            mainColumn
            if showComplementos {
                pluginsColumn
                    .transition(.softNudge(x: -4))
            }
        }
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddMenuRow(
                icon: "paperclip",
                label: L10n.t("Add photos and files"),
                trailing: nil,
                highlighted: false
            ) {
                isPresented = false
                // Defer so the menu finishes dismissing before the
                // modal NSOpenPanel takes over the run loop.
                DispatchQueue.main.async { onPickFiles() }
            }
            .onHover { hovering in
                if hovering { withAnimation(.easeOut(duration: 0.20)) { showComplementos = false } }
            }

            MenuStandardDivider()
                .padding(.vertical, 3)

            AddMenuToggleRow(icon: "checklist", label: L10n.t("Plan mode"), isOn: $planMode)
                .onHover { hovering in
                    if hovering { withAnimation(.easeOut(duration: 0.20)) { showComplementos = false } }
                }

            /*
            MenuStandardDivider()
                .padding(.vertical, 3)

            AddMenuRow(
                icon: "square.grid.2x2",
                label: "Plugins",
                trailing: "chevron.right",
                highlighted: showComplementos
            ) {
                withAnimation(.easeOut(duration: 0.20)) { showComplementos.toggle() }
            }
            .onHover { hovering in
                if hovering { withAnimation(.easeOut(duration: 0.20)) { showComplementos = true } }
            }
            */
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 186, alignment: .leading)
        .menuStandardBackground()
    }

    private var pluginsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader(headerText)

            ForEach(plugins) { plugin in
                PluginRow(plugin: plugin) { isPresented = false }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: 176, alignment: .leading)
        .menuStandardBackground()
    }

    private var headerText: String {
        L10n.installedPlugins(plugins.count)
    }
}

struct AddMenuRow: View {
    let icon: String
    let label: String
    let trailing: String?
    let highlighted: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                LucideIcon.auto(icon, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if let trailing {
                    LucideIcon.auto(trailing, size: 11)
                        .font(BodyFont.system(size: MenuStyle.rowTrailingIconSize, weight: .semibold))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
            }
            .padding(.leading, MenuStyle.rowHorizontalPadding)
            .padding(.trailing, MenuStyle.rowHorizontalPadding
                                + (trailing != nil ? MenuStyle.rowTrailingIconExtra : 0))
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(
                active: highlighted || hovered,
                intensity: highlighted ? MenuStyle.rowHoverIntensityStrong : MenuStyle.rowHoverIntensity
            ))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct AddMenuToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    @State private var hovered = false

    var body: some View {
        HStack(spacing: MenuStyle.rowIconLabelSpacing) {
            LucideIcon.auto(icon, size: 11)
                .foregroundColor(MenuStyle.rowIcon)
                .frame(width: 18, alignment: .center)
            Text(label)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(MenuStyle.rowText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            CompactMenuToggle(isOn: $isOn)
        }
        .padding(.horizontal, MenuStyle.rowHorizontalPadding)
        .padding(.vertical, MenuStyle.rowVerticalPadding)
        .contentShape(Rectangle())
        .background(MenuRowHover(active: hovered))
        .onHover { hovered = $0 }
        .onTapGesture { withAnimation(.easeOut(duration: 0.14)) { isOn.toggle() } }
    }
}

private struct PluginRow: View {
    let plugin: Plugin
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                LucideIcon.auto(plugin.iconName, size: 11)
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(plugin.name)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }
            .padding(.horizontal, MenuStyle.rowHorizontalPadding)
            .padding(.vertical, MenuStyle.rowVerticalPadding)
            .contentShape(Rectangle())
            .background(MenuRowHover(active: hovered))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Compact menu toggle. A small dark capsule with a white knob that slides
/// from left (off) to right (on). Used inside dropdown rows where the native
/// `.switch` style would feel too tall and chunky.
struct CompactMenuToggle: View {
    @Binding var isOn: Bool

    private let trackWidth: CGFloat = 24
    private let trackHeight: CGFloat = 14
    private let knobSize: CGFloat = 10
    private let knobInset: CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? Color(white: 0.92) : Color(white: 0.30))
            Circle()
                .fill(isOn ? Color(white: 0.18) : Color(white: 0.96))
                .frame(width: knobSize, height: knobSize)
                .offset(x: isOn ? trackWidth - knobSize - knobInset : knobInset)
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.72)) { isOn.toggle() }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}
