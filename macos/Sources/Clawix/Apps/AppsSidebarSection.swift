import SwiftUI

/// Top-level "Apps" section in the sidebar. Peer of Pinned/Projects/
/// Tools/Archived. Shows up to N pinned + recently-used app rows; the
/// header has an `All apps` button that opens the home grid.
///
/// Lives outside `SidebarView.swift` so the sidebar file (~5k lines)
/// doesn't grow another section worth of state. Glues into the
/// existing `SidebarPrefs` `UserDefaults` suite for the expansion flag.
struct AppsSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var appsStore: AppsStore = .shared

    @AppStorage("SidebarAppsExpanded", store: SidebarPrefs.store)
    private var expanded: Bool = true
    @State private var pendingDelete: AppRecord?

    /// Cap visible rows in the sidebar. The header's "All apps" entry
    /// surfaces the full catalog when the user has more than this.
    private static let visibleLimit = 8

    private var visibleApps: [AppRecord] {
        Array(appsStore.sortedApps.prefix(Self.visibleLimit))
    }

    private var hasOverflow: Bool {
        appsStore.apps.count > Self.visibleLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    if visibleApps.isEmpty {
                        emptyHint
                    } else {
                        ForEach(visibleApps) { record in
                            AppsSidebarRow(
                                record: record,
                                isSelected: isSelected(record),
                                onOpen: { appState.currentRoute = .app(record.id) },
                                onTogglePin: { appsStore.togglePinned(record) },
                                onDelete: { pendingDelete = record }
                            )
                        }
                        if hasOverflow {
                            allAppsButton
                        }
                    }
                    // Match the trailing gap every other section uses
                    // (`SidebarRowMetrics.sectionEdgePadding`, 9.75).
                    Color.clear.frame(height: 9.75)
                }
                .padding(.leading, 8)
            }
        }
        .alert(item: $pendingDelete) { record in
            Alert(
                title: Text("Delete \"\(record.name)\"?"),
                message: Text("The app folder will be removed from disk. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    try? appsStore.delete(record)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var sectionHeader: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 16, height: 16, alignment: .center)
                Text("Apps")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                Button {
                    appState.currentRoute = .appsHome
                } label: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.55)
                }
                .buttonStyle(.plain)
                .help("All apps")
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

    private var emptyHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(white: 0.45))
            Text("Ask the agent to build one")
                .font(BodyFont.system(size: 12.5, wght: 400))
                .foregroundColor(Color(white: 0.50))
        }
        .padding(.leading, 26)
        .padding(.vertical, 4)
    }

    private var allAppsButton: some View {
        Button {
            appState.currentRoute = .appsHome
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 18)
                Text("All apps (\(appsStore.apps.count))")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.70))
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ record: AppRecord) -> Bool {
        if case let .app(id) = appState.currentRoute, id == record.id { return true }
        return false
    }
}

/// One row inside the sidebar Apps section. Visually consistent with
/// the existing tool rows (Tasks/Notes/Drive) but adds a colored chip
/// derived from the app's slug + pin/delete context menu.
private struct AppsSidebarRow: View {
    let record: AppRecord
    let isSelected: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                iconChip
                Text(record.name)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.92))
                    .lineLimit(1)
                Spacer()
                if record.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
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
        .contextMenu {
            Button(record.pinned ? "Unpin from sidebar" : "Pin to sidebar", action: onTogglePin)
            Divider()
            Button("Delete app", role: .destructive, action: onDelete)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.07) }
        if hovered    { return Color.white.opacity(0.035) }
        return .clear
    }

    private var iconChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(chipColor)
            if !record.icon.isEmpty {
                Text(record.icon)
                    .font(.system(size: 12))
            } else {
                Text(initials)
                    .font(BodyFont.system(size: 9.5, wght: 700))
                    .foregroundColor(.white.opacity(0.92))
            }
        }
        .frame(width: 18, height: 18)
    }

    private var initials: String {
        let parts = record.name.split(separator: " ", maxSplits: 1)
        if parts.count == 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(record.name.prefix(2)).uppercased()
    }

    private var chipColor: Color {
        if let parsed = Color(appsHex: record.accentColor) {
            return parsed
        }
        var hash: UInt64 = 0
        for byte in record.slug.utf8 { hash = hash &* 131 &+ UInt64(byte) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.55)
    }
}
