import SwiftUI

/// Top-level "Design" section in the sidebar. Peer of Apps / Pinned /
/// Projects / Tools / Archived. Exposes three entry points: Styles
/// (saved design recipes), Templates (parametrised pieces by category)
/// and References (inspiration library).
struct DesignSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: DesignStore = .shared

    @AppStorage("SidebarDesignExpanded", store: SidebarPrefs.store)
    private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    DesignSidebarRow(
                        title: "Styles",
                        icon: "paintpalette",
                        count: store.styles.count,
                        isSelected: isSelected(.designStylesHome),
                        onOpen: { appState.currentRoute = .designStylesHome }
                    )
                    DesignSidebarRow(
                        title: "Templates",
                        icon: "rectangle.grid.2x2",
                        count: store.templates.count,
                        isSelected: isSelected(.designTemplatesHome),
                        onOpen: { appState.currentRoute = .designTemplatesHome }
                    )
                    DesignSidebarRow(
                        title: "References",
                        icon: "books.vertical",
                        count: store.references.count,
                        isSelected: isSelected(.designReferencesHome),
                        onOpen: { appState.currentRoute = .designReferencesHome }
                    )
                    Color.clear.frame(height: 9.75)
                }
                .padding(.leading, 8)
            }
        }
    }

    private var sectionHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paintbrush")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 16, height: 16, alignment: .center)
                Text("Design")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.45)
            }
            .foregroundColor(Color(white: 0.65))
            .padding(.leading, 16)
            .padding(.trailing, 9)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ route: SidebarRoute) -> Bool {
        appState.currentRoute == route
    }
}

private struct DesignSidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let onOpen: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.78))
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.92))
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color(white: 0.48))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.07) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }
}
