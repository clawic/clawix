import SwiftUI

/// Top-level container for the Memory tab. Owns a `MemoryManager` for
/// the current navigation lifetime and routes between the home view (3-pane
/// browser), the captures view, and the settings view.
struct MemoryScreen: View {

    enum Section: Equatable {
        case home
        case captures
        case settings
    }

    @StateObject private var manager = MemoryManager()
    @State private var section: Section = .home

    var body: some View {
        VStack(spacing: 0) {
            MemoryScreenHeader(
                section: $section,
                state: manager.state,
                statsTotal: manager.stats?.total ?? manager.notes.count,
                onCreate: { showCreateSheet = true },
                onRefresh: { Task { await manager.refresh() } }
            )
            CardDivider()
            Group {
                if case .error(let message) = manager.state {
                    ContentUnavailableView(
                        "Memory unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                } else {
                    switch section {
                    case .home:
                        MemoryHomeView(manager: manager, onSelectSection: { section = $0 })
                    case .captures:
                        MemoryCapturesView(manager: manager, onClose: { section = .home })
                    case .settings:
                        MemorySettingsView(manager: manager, onClose: { section = .home })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if manager.state == .idle { await manager.refresh() }
        }
        .sheet(isPresented: $showCreateSheet) {
            MemoryEditSheet(
                manager: manager,
                mode: .create,
                onDismiss: { showCreateSheet = false }
            )
        }
    }

    @State private var showCreateSheet = false
}

/// Header strip with a status pill, the active section selector,
/// "+ New" and "Refresh" actions. Mirrors the look of `SecretsHomeView`
/// header so the Memory tab visually fits with the rest of the app.
private struct MemoryScreenHeader: View {
    @Binding var section: MemoryScreen.Section
    let state: MemoryManager.State
    let statsTotal: Int
    let onCreate: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("Memory")
                    .font(BodyFont.system(size: 17, wght: 600))
                    .foregroundColor(.white)
                statusPill
            }
            Spacer()
            HStack(spacing: 6) {
                MemorySectionButton(
                    title: "Notes",
                    isSelected: section == .home,
                    action: { section = .home }
                )
                MemorySectionButton(
                    title: "Captures",
                    isSelected: section == .captures,
                    action: { section = .captures }
                )
                MemorySectionButton(
                    title: "Settings",
                    isSelected: section == .settings,
                    action: { section = .settings }
                )
            }
            HStack(spacing: 6) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 24, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")

                Button(action: onCreate) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New")
                            .font(BodyFont.system(size: 12.5, wght: 600))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New memory")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var statusPill: some View {
        let label: String
        let color: Color
        switch state {
        case .idle:
            label = "—"; color = .gray
        case .loading:
            label = "Loading…"; color = .yellow
        case .ready:
            label = "\(statsTotal)"; color = .green
        case .error:
            label = "Offline"; color = .red
        }
        return Text(label)
            .font(BodyFont.system(size: 11, wght: 600))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.22))
            )
            .overlay(
                Capsule().stroke(color.opacity(0.5), lineWidth: 0.6)
            )
    }
}

private struct MemorySectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(isSelected ? .white : Color(white: hovered ? 0.92 : 0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.08) : (hovered ? Color.white.opacity(0.04) : .clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
