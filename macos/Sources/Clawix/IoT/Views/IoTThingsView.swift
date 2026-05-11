import SwiftUI

/// Devices tab inside `IoTScreen`. Renders the things grouped by area
/// (rooms / zones). Each section is a `AreaSection`; each card is a
/// `ThingCard`. Filterable by text search.
struct IoTThingsView: View {
    @EnvironmentObject private var manager: IoTManager
    @EnvironmentObject private var appState: AppState
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if filteredThings.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    } else {
                        ForEach(grouped, id: \.0) { section in
                            AreaSection(label: section.0, things: section.1) { thing in
                                appState.currentRoute = .iotThingDetail(id: thing.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .thinScrollers()
        }
    }

    private var filteredThings: [ThingRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return manager.things }
        return manager.things.filter { thing in
            thing.label.lowercased().contains(trimmed)
                || thing.aliases.contains(where: { $0.lowercased().contains(trimmed) })
                || thing.kind.rawValue.lowercased().contains(trimmed)
        }
    }

    /// Returns `(label, things)` pairs ordered so the user's home areas
    /// appear in alphabetic order and any thing without an area lands
    /// at the bottom under "Unassigned".
    private var grouped: [(String, [ThingRecord])] {
        var byArea: [String: [ThingRecord]] = [:]
        for thing in filteredThings {
            let label = manager.areaLabel(forId: thing.areaId) ?? "Unassigned"
            byArea[label, default: []].append(thing)
        }
        let ordered = byArea
            .map { ($0.key, $0.value.sorted { $0.label < $1.label }) }
            .sorted { lhs, rhs in
                if lhs.0 == "Unassigned" { return false }
                if rhs.0 == "Unassigned" { return true }
                return lhs.0 < rhs.0
            }
        return ordered
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
            TextField("Filter devices", text: $query)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "house.lodge")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Palette.textTertiary)
            Text(verbatim: "No devices yet")
                .font(BodyFont.system(size: 14, weight: .medium))
                .foregroundColor(Palette.textSecondary)
            Text(verbatim: "Switch to the Add device tab to discover or register a thing.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
