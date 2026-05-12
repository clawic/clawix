import SwiftUI

/// Settings screen for the Life surface. Lets the user show, hide and
/// reorder the verticals that appear in the sidebar's Life section.
struct LifeSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var manager = LifeManager.shared

    @State private var enabledOrder: [String] = []
    @State private var search: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Life · Configure")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("Back to Life") {
                    appState.navigate(to: .lifeHome)
                }
                .buttonStyle(.plain)
                .foregroundColor(Palette.textSecondary)
            }

            TextField("Search verticals…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(LifeCategory.allCases, id: \.self) { category in
                        let entries = filteredEntries(in: category)
                        if !entries.isEmpty {
                            Text(category.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Palette.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            ForEach(entries) { entry in
                                row(for: entry)
                            }
                        }
                    }
                }
            }
            .thinScrollers()
        }
        .padding(24)
        .background(Palette.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            enabledOrder = manager.enabledVerticalIds
        }
    }

    private func filteredEntries(in category: LifeCategory) -> [LifeRegistryEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = LifeRegistry.entries(in: category)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.label.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func row(for entry: LifeRegistryEntry) -> some View {
        let isEnabled = manager.enabledVerticalIds.contains(entry.id)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    var next = manager.enabledVerticalIds
                    if newValue {
                        if !next.contains(entry.id) { next.append(entry.id) }
                    } else {
                        next.removeAll { $0 == entry.id }
                    }
                    manager.setEnabled(next)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            statusBadge(entry.status)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private func statusBadge(_ status: LifeVerticalStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .planned:
            text = "PLANNED"; color = Color.white.opacity(0.30)
        case .alpha:
            text = "ALPHA"; color = Color.white.opacity(0.55)
        case .stable:
            text = "STABLE"; color = Color.white.opacity(0.80)
        case .deprecated:
            text = "DEPRECATED"; color = Color.red.opacity(0.55)
        }
        return Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.5), lineWidth: 0.5)
            )
    }
}
