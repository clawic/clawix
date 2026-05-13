import SwiftUI
import UniformTypeIdentifiers

struct PinnedFilterSource: Identifiable, Equatable {
    let token: String
    let label: String
    let isNoProject: Bool
    var id: String { token }
}

struct PinnedFilterAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct PinnedFilterPopup: View {
    @Binding var isPresented: Bool
    let sources: [PinnedFilterSource]
    let disabled: Set<String>
    let toggle: (String) -> Void
    let showAll: () -> Void
    let hideAll: () -> Void

    /// Cap so the popup never occupies the entire window when the user
    /// has dozens of projects with pinned chats; rows beyond the cap
    /// scroll inside.
    private static let maxListHeight: CGFloat = 260
    /// Below this row count we render the project list inline so the
    /// popup hugs the rows; above it we wrap in a capped ScrollView so
    /// the popup doesn't dominate the window.
    private static let inlineThreshold = 8

    private var allHidden: Bool {
        !sources.isEmpty && disabled.count >= sources.count
    }

    private var hasFooter: Bool { !disabled.isEmpty || !allHidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Filter by project")
            list
            if hasFooter {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                if !disabled.isEmpty {
                    PinnedFilterBulkRow(icon: "eye", label: "Show all") {
                        showAll()
                    }
                }
                if !allHidden {
                    PinnedFilterBulkRow(icon: "eye.slash", label: "Hide all") {
                        hideAll()
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }

    @ViewBuilder
    private var list: some View {
        if sources.count > Self.inlineThreshold {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sources) { source in
                        PinnedFilterRow(
                            label: source.label,
                            isNoProject: source.isNoProject,
                            isActive: !disabled.contains(source.token),
                            action: { toggle(source.token) }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sources) { source in
                    PinnedFilterRow(
                        label: source.label,
                        isNoProject: source.isNoProject,
                        isActive: !disabled.contains(source.token),
                        action: { toggle(source.token) }
                    )
                }
            }
        }
    }
}

struct PinnedFilterRow: View {
    let label: String
    let isNoProject: Bool
    let isActive: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Group {
                    if isNoProject {
                        Image(systemName: "tray")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
                    } else {
                        FolderOpenIcon(size: 11.5)
                            .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
                    }
                }
                .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(isActive ? MenuStyle.rowText : MenuStyle.rowSubtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 9.5, weight: .semibold))
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

struct PinnedFilterBulkRow: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Image(systemName: icon)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
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

struct ToolsFilterAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ToolsFilterPopup: View {
    @Binding var isPresented: Bool
    let entries: [SidebarToolEntry]
    let hidden: Set<String>
    let toggle: (String) -> Void
    let showAll: () -> Void
    let hideAll: () -> Void

    private static let maxListHeight: CGFloat = 280
    private static let inlineThreshold = 8

    private var allHidden: Bool {
        !entries.isEmpty && hidden.count >= entries.count
    }

    private var hasFooter: Bool { !hidden.isEmpty || !allHidden }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelMenuHeader("Show or hide tools")
            list
            if hasFooter {
                MenuStandardDivider()
                    .padding(.vertical, 5)
                if !hidden.isEmpty {
                    ToolsFilterBulkRow(icon: "eye", label: "Show all") {
                        showAll()
                    }
                }
                if !allHidden {
                    ToolsFilterBulkRow(icon: "eye.slash", label: "Hide all") {
                        hideAll()
                    }
                }
            }
        }
        .padding(.vertical, MenuStyle.menuVerticalPadding)
        .menuStandardBackground()
        .background(MenuOutsideClickWatcher(isPresented: $isPresented))
    }

    @ViewBuilder
    private var list: some View {
        if entries.count > Self.inlineThreshold {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        ToolsFilterRow(
                            entry: entry,
                            isActive: !hidden.contains(entry.id),
                            action: { toggle(entry.id) }
                        )
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    ToolsFilterRow(
                        entry: entry,
                        isActive: !hidden.contains(entry.id),
                        action: { toggle(entry.id) }
                    )
                }
            }
        }
    }
}

struct ToolsFilterRow: View {
    let entry: SidebarToolEntry
    let isActive: Bool
    let action: () -> Void

    @State private var hovered = false
    @EnvironmentObject private var vault: SecretsManager

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                iconView
                    .frame(width: 18, alignment: .center)
                Text(entry.title)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(isActive ? MenuStyle.rowText : MenuStyle.rowSubtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(BodyFont.system(size: 9.5, weight: .semibold))
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

    @ViewBuilder
    private var iconView: some View {
        switch entry.icon {
        case .system(let name):
            Image(systemName: name)
                .font(BodyFont.system(size: 11))
                .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
        case .secrets:
            SecretsIcon(
                size: 11.5,
                lineWidth: 1.28,
                color: isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle,
                isLocked: vault.state == .locked || vault.state == .unlocking
            )
        case .clawixLogo:
            ClawixLogoIcon(size: 12)
                .foregroundColor(isActive ? MenuStyle.rowIcon : MenuStyle.rowSubtle)
        }
    }
}

struct ToolsFilterBulkRow: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuStyle.rowIconLabelSpacing) {
                Image(systemName: icon)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(MenuStyle.rowIcon)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(MenuStyle.rowText)
                Spacer(minLength: 8)
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
