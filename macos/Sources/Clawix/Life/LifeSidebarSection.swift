import SwiftUI

/// Sidebar section that exposes the user-enabled Life verticals. Peer
/// of `DesignSidebarSection` / `AppsSidebarSection`; rendering follows
/// the same compact row style as `SidebarToolsCatalog`.
struct LifeSidebarSection: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var manager = LifeManager.shared

    @AppStorage("SidebarLifeExpanded", store: SidebarPrefs.store)
    private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                content
            }
        }
        .padding(.bottom, 6)
    }

    private var header: some View {
        Button(action: { expanded.toggle() }) {
            HStack(spacing: 6) {
                LucideIcon.auto(expanded ? "chevron.down" : "chevron.right", size: 9)
                    .foregroundColor(Color.white.opacity(0.45))
                    .frame(width: 14)
                Text("Life")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.55))
                Spacer()
                Button(action: { appState.navigate(to: .lifeSettings) }) {
                    LucideIcon.auto("list.bullet", size: 11)
                        .foregroundColor(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Configure Life verticals")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Button(action: { appState.navigate(to: .lifeHome) }) {
                HStack(spacing: 8) {
                    LucideIcon.auto("circle", size: 11)
                        .foregroundColor(Color.white.opacity(0.55))
                        .frame(width: 16)
                    Text("All verticals")
                        .font(.system(size: 12))
                        .foregroundColor(isRouteSelected(.lifeHome)
                                         ? Palette.textPrimary
                                         : Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    isRouteSelected(.lifeHome) ? Color.white.opacity(0.05) : Color.clear
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(visibleVerticals, id: \.id) { entry in
                row(for: entry)
            }
        }
    }

    private func row(for entry: LifeRegistryEntry) -> some View {
        let route = SidebarRoute.lifeVertical(id: entry.id)
        let selected = isRouteSelected(route)
        return Button(action: { appState.navigate(to: route) }) {
            HStack(spacing: 8) {
                LucideIcon.auto(iconName(for: entry), size: 11)
                    .foregroundColor(Color.white.opacity(selected ? 0.85 : 0.55))
                    .frame(width: 16)
                Text(entry.label)
                    .font(.system(size: 12))
                    .foregroundColor(selected ? Palette.textPrimary : Palette.textSecondary)
                Spacer()
                if entry.status == .planned {
                    Text("PLAN")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(selected ? Color.white.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var visibleVerticals: [LifeRegistryEntry] {
        let ids = manager.enabledVerticalIds
        let hidden = manager.hiddenVerticalIds
        return ids.compactMap { id in
            guard !hidden.contains(id) else { return nil }
            return LifeRegistry.entry(byId: id)
        }
    }

    private func isRouteSelected(_ route: SidebarRoute) -> Bool {
        appState.currentRoute == route
    }

    private func iconName(for entry: LifeRegistryEntry) -> String {
        switch entry.iconHint {
        case "heart": return "circle"
        case "moon": return "moon"
        case "dumbbell": return "circle"
        case "smile": return "circle"
        case "book": return "doc.text"
        case "check": return "checkmark.circle"
        case "timer": return "timer"
        case "flag": return "flag"
        case "wallet": return "cylinder.split.1x2"
        case "apple": return "circle"
        case "droplet": return "circle"
        case "scale": return "circle"
        case "screen": return "app"
        case "scissors": return "crop"
        case "cycle": return "clock.arrow.circlepath"
        case "pill": return "circle"
        case "cloud-moon": return "cloud.moon"
        case "spark": return "star"
        case "stars": return "star"
        case "repeat": return "arrow.clockwise"
        case "bolt": return "bolt"
        case "x": return "xmark.circle"
        case "speech": return "bubble.left"
        case "users": return "circle"
        case "pen": return "pencil"
        case "camera": return "camera"
        case "chef": return "circle"
        case "target": return "viewfinder"
        case "book-open": return "doc.text"
        case "music": return "waveform"
        case "gamepad": return "app"
        case "bookmark": return "bookmark"
        case "fork": return "circle"
        case "calendar-event": return "clock"
        case "people": return "circle"
        case "gift": return "archivebox"
        case "swords": return "shield"
        case "link": return "link"
        case "academic": return "doc.text"
        case "hand-coins": return "cylinder.split.1x2"
        case "hands": return "circle"
        case "phone": return "app"
        case "plane": return "arrow.up.right"
        case "location": return "globe"
        case "cloud": return "globe"
        case "leaf": return "circle"
        case "shirt": return "circle"
        case "box": return "archivebox"
        case "credit": return "cylinder.split.1x2"
        case "paw": return "circle"
        case "house": return "folder"
        case "plant": return "circle"
        case "car": return "app"
        case "briefcase": return "folder"
        case "trending-up": return "arrow.up.right"
        case "brain": return "brain"
        case "star": return "star.circle"
        case "trophy": return "badge.check"
        case "lightbulb": return "lightbulb"
        case "puzzle": return "app.dashed"
        case "fingerprint": return "person.crop.circle"
        case "thought": return "bubble.middle.bottom"
        case "compass": return "safari"
        case "flame": return "flame"
        case "handshake": return "circle"
        case "chart": return "arrow.up.right"
        case "split": return "arrow.triangle.branch"
        case "quote": return "quote.bubble"
        case "lotus": return "circle"
        case "graduation": return "doc.text"
        case "calendar-year": return "clock"
        case "heart-hand": return "circle"
        case "stretch": return "circle"
        case "body": return "circle"
        case "heart-private": return "eye.slash"
        case "flask": return "circle"
        case "ruler": return "viewfinder"
        default: return "circle"
        }
    }
}
