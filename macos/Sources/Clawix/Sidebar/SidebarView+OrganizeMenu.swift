import SwiftUI
import UniformTypeIdentifiers

struct OrganizeMenuAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

enum OrganizeSubmenu { case none, byProject }

enum OrganizeChevronRow: Hashable { case byProject }

struct OrganizeChevronAnchorsKey: PreferenceKey {
    static var defaultValue: [OrganizeChevronRow: Anchor<CGRect>] = [:]
    static func reduce(value: inout [OrganizeChevronRow: Anchor<CGRect>],
                       nextValue: () -> [OrganizeChevronRow: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct OrganizeMenuPopup: View {
    @Binding var isPresented: Bool
    @Binding var viewModeRaw: String
    @Binding var projectSortModeRaw: String

    /// Distinct project buckets across the chronological list. Empty if
    /// the chrono list contains zero chats. Provided by the caller so the
    /// popup stays stateless.
    let chronoFilterSources: [PinnedFilterSource]
    let chronoFilterDisabled: Set<String>
    let toggleChronoFilter: (String) -> Void
    let showAllChronoFilter: () -> Void
    let hideAllChronoFilter: () -> Void

    static let mainColumnWidth: CGFloat = 232
    private static let byProjectColumnWidth: CGFloat = 244
    private static let columnGap: CGFloat = 6
    private static let byProjectMaxListHeight: CGFloat = 260
    /// Below this row count we render the project list inline so the
    /// popup hugs the rows; above it we wrap in a capped ScrollView so
    /// the popup doesn't dominate the window.
    private static let byProjectInlineThreshold = 8

    @State private var openSubmenu: OrganizeSubmenu = .none

    private var isGrouped: Bool {
        viewModeRaw == SidebarViewMode.grouped.rawValue
    }

    /// Hide the filter affordance when there's nothing meaningful to
    /// filter by: zero buckets, or a single bucket (typically just the
    /// implicit "Without project" entry when the user hasn't created any
    /// projects yet). Mirrors the `>= 2` rule the Pinned section uses.
    private var canFilterByProject: Bool {
        !isGrouped && chronoFilterSources.count >= 2
    }

    private var allChronoHidden: Bool {
        !chronoFilterSources.isEmpty
            && chronoFilterDisabled.count >= chronoFilterSources.count
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainColumn
        }
        .overlayPreferenceValue(OrganizeChevronAnchorsKey.self) { anchors in
            GeometryReader { proxy in
                let parentGlobalMinX = proxy.frame(in: .global).minX
                if openSubmenu == .byProject,
                   canFilterByProject,
                   let anchor = anchors[.byProject] {
                    let row = proxy[anchor]
                    let placement = submenuLeadingPlacement(
                        parentGlobalMinX: parentGlobalMinX,
                        row: row,
                        submenuWidth: Self.byProjectColumnWidth,
                        gap: Self.columnGap
                    )
                    byProjectColumn
                        .alignmentGuide(.leading) { _ in placement.offset }
                        .alignmentGuide(.top) { _ in -row.minY }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.softNudge(x: placement.placedRight ? -4 : 4))
                }
            }
            .animation(.easeOut(duration: 0.18), value: openSubmenu)
        }
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
        .animation(.easeOut(duration: 0.18), value: isGrouped)
        .animation(.easeOut(duration: 0.18), value: canFilterByProject)
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Organize")
            OrganizeMenuRow(
                icon: .folderOpen,
                label: "Grouped by project",
                isSelected: viewModeRaw == SidebarViewMode.grouped.rawValue
            ) {
                viewModeRaw = SidebarViewMode.grouped.rawValue
                isPresented = false
            }
            .onHover { hovering in
                if hovering { openSubmenu = .none }
            }
            OrganizeMenuRow(
                icon: .system("clock"),
                label: "Chronological list",
                isSelected: viewModeRaw == SidebarViewMode.chronological.rawValue
            ) {
                viewModeRaw = SidebarViewMode.chronological.rawValue
                isPresented = false
            }
            .onHover { hovering in
                if hovering { openSubmenu = .none }
            }

            if isGrouped {
                MenuStandardDivider()
                    .padding(.vertical, 5)

                ModelMenuHeader("Sort projects by")
                OrganizeMenuRow(
                    icon: .system("clock.arrow.circlepath"),
                    label: "Recent",
                    isSelected: projectSortModeRaw == ProjectSortMode.recent.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.recent.rawValue
                    isPresented = false
                }
                OrganizeMenuRow(
                    icon: .system("plus.circle"),
                    label: "Created",
                    isSelected: projectSortModeRaw == ProjectSortMode.creation.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.creation.rawValue
                    isPresented = false
                }
                OrganizeMenuRow(
                    icon: .system("textformat"),
                    label: "Name",
                    isSelected: projectSortModeRaw == ProjectSortMode.name.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.name.rawValue
                    isPresented = false
                }
                OrganizeMenuRow(
                    icon: .system("line.3.horizontal"),
                    label: "Custom",
                    isSelected: projectSortModeRaw == ProjectSortMode.custom.rawValue
                ) {
                    projectSortModeRaw = ProjectSortMode.custom.rawValue
                    isPresented = false
                }
            }

            if canFilterByProject {
                MenuStandardDivider()
                    .padding(.vertical, 5)

                ModelMenuHeader("Filter")
                OrganizeMenuChevronRow(
                    icon: .system("folder"),
                    label: "By project",
                    badge: chronoFilterDisabled.isEmpty ? nil : "\(chronoFilterDisabled.count)",
                    highlighted: openSubmenu == .byProject
                ) {
                    openSubmenu = (openSubmenu == .byProject) ? .none : .byProject
                }
                .onHover { hovering in
                    if hovering { openSubmenu = .byProject }
                }
                .anchorPreference(key: OrganizeChevronAnchorsKey.self, value: .bounds) {
                    [.byProject: $0]
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.mainColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    private var byProjectColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Filter by project")
            byProjectList

            let hasFooter = !chronoFilterDisabled.isEmpty || !allChronoHidden
            if hasFooter {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                if !chronoFilterDisabled.isEmpty {
                    PinnedFilterBulkRow(icon: "eye", label: "Show all") {
                        showAllChronoFilter()
                    }
                }
                if !allChronoHidden {
                    PinnedFilterBulkRow(icon: "eye.slash", label: "Hide all") {
                        hideAllChronoFilter()
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .frame(width: Self.byProjectColumnWidth, alignment: .leading)
        .menuStandardBackground()
    }

    @ViewBuilder
    private var byProjectList: some View {
        if chronoFilterSources.count > Self.byProjectInlineThreshold {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chronoFilterSources) { source in
                        PinnedFilterRow(
                            label: source.label,
                            isNoProject: source.isNoProject,
                            isActive: !chronoFilterDisabled.contains(source.token),
                            action: { toggleChronoFilter(source.token) }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.byProjectMaxListHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(chronoFilterSources) { source in
                    PinnedFilterRow(
                        label: source.label,
                        isNoProject: source.isNoProject,
                        isActive: !chronoFilterDisabled.contains(source.token),
                        action: { toggleChronoFilter(source.token) }
                    )
                }
            }
        }
    }
}

enum OrganizeMenuIcon {
    case folderOpen
    case system(String)
}

struct OrganizeMenuRow: View {
    let icon: OrganizeMenuIcon
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    switch icon {
                    case .folderOpen:
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(MenuStyle.rowIcon)
                    case .system(let name):
                        LucideIcon.auto(name, size: 12)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
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
        .sidebarHover { hovered = $0 }
    }
}

struct OrganizeMenuChevronRow: View {
    let icon: OrganizeMenuIcon
    let label: String
    let badge: String?
    let highlighted: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    switch icon {
                    case .folderOpen:
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(MenuStyle.rowIcon)
                    case .system(let name):
                        LucideIcon.auto(name, size: 12)
                            .foregroundColor(MenuStyle.rowIcon)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(MenuStyle.rowSubtle)
                }
                LucideIcon(.chevronRight, size: 11)
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
        .sidebarHover { hovered = $0 }
    }
}
