import SwiftUI
import ClawixCore

// "Run on:" selector that lives in the composer. Three jobs:
//
//   1. Show where the next prompt is going to run (Local or a paired
//      peer's display name).
//   2. Open a popup with the full list of paired Macs so the user can
//      switch destinations without leaving the composer.
//   3. Reflect peer health: revoked peers are disabled, unreachable
//      peers (no recent `lastSeenAt`) get a muted style. The user can
//      still click them to retry; we surface daemon-side errors when
//      the prompt actually fails.
//
// Renders identical chrome to the existing project picker so home and
// chat composers feel like the same toolbar.

struct MeshTargetPill: View {

    enum Style {
        case projectRow      // home screen, sits beside the "Work on a project" pill
        case toolbarCompact  // chat composer toolbar, smaller chevron

        var fontSize: CGFloat {
            switch self {
            case .projectRow: return 11.5
            case .toolbarCompact: return 11.5
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .projectRow: return 11
            case .toolbarCompact: return 11
            }
        }
    }

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: MeshStore
    let style: Style
    @Binding var menuOpen: Bool

    var body: some View {
        Button {
            // Refresh peers on open so a freshly paired Mac shows up
            // without forcing the user to round-trip through Settings.
            Task { await store.refreshPeers() }
            menuOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                LucideIcon(.laptop, size: style.iconSize)
                Text(label)
                    .font(BodyFont.system(size: style.fontSize, wght: 500))
                    .lineLimit(1)
                LucideIcon(.chevronDown, size: 8)
            }
            .foregroundColor(Color(white: 0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Run on")
        .accessibilityValue(label)
        .anchorPreference(key: MeshTargetAnchorKey.self, value: .bounds) { $0 }
    }

    private var label: String {
        switch appState.selectedMeshTarget {
        case .local:
            return String(localized: "On this Mac", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .peer(let nodeId):
            if let peer = store.peers.first(where: { $0.nodeId == nodeId }) {
                return peer.displayName
            }
            return String(localized: "Unknown Mac", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
}

struct MeshTargetAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Popup

struct MeshTargetPopup: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: MeshStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(
                label: String(localized: "On this Mac", bundle: AppLocale.bundle, locale: AppLocale.current),
                detail: String(localized: "Run with the local Codex backend", bundle: AppLocale.bundle, locale: AppLocale.current),
                isSelected: appState.selectedMeshTarget.isLocal,
                isDisabled: false,
                isAvailable: true
            ) {
                appState.selectedMeshTarget = .local
                isPresented = false
            }

            if !store.peers.isEmpty {
                divider
            }

            ForEach(store.peers, id: \.nodeId) { peer in
                let detail: String = {
                    if peer.revokedAt != nil { return "Revoked" }
                    if let last = peer.lastSeenAt {
                        return "Last seen \(Self.relative.localizedString(for: last, relativeTo: Date()))"
                    }
                    return "No recent activity"
                }()
                row(
                    label: peer.displayName,
                    detail: detail,
                    isSelected: appState.selectedMeshTarget.peerNodeId == peer.nodeId,
                    isDisabled: !peer.isAvailable,
                    isAvailable: peer.isAvailable
                ) {
                    guard peer.isAvailable else { return }
                    appState.selectedMeshTarget = .peer(nodeId: peer.nodeId)
                    isPresented = false
                }
            }

            if store.peers.isEmpty {
                divider
                emptyHint
            } else {
                divider
                manageRow
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: MenuStyle.cornerRadius, style: .continuous)
                .fill(MenuStyle.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: MenuStyle.cornerRadius, style: .continuous)
                        .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
        )
        .shadow(color: MenuStyle.shadowColor, radius: MenuStyle.shadowRadius, x: 0, y: MenuStyle.shadowOffsetY)
    }

    @ViewBuilder
    private func row(label: String, detail: String, isSelected: Bool, isDisabled: Bool, isAvailable: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LucideIcon(.laptop, size: 14)
                    .foregroundColor(isAvailable ? Palette.textPrimary : Palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(BodyFont.system(size: 12.5, weight: .medium))
                        .foregroundColor(isAvailable ? Palette.textPrimary : Palette.textTertiary)
                        .lineLimit(1)
                    Text(detail)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if isSelected {
                    LucideIcon(.check, size: 11)
                        .foregroundColor(Palette.textPrimary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No paired Macs yet")
                .font(BodyFont.system(size: 11.5, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            Text("Open Settings → Machines to link another Mac.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private var manageRow: some View {
        Button {
            appState.currentRoute = .settings
            appState.settingsCategory = .machines
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                LucideIcon(.arrowRight, size: 11)
                Text("Manage paired Macs…")
                    .font(BodyFont.system(size: 11.5, weight: .medium))
                Spacer()
            }
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
