import SwiftUI

/// Top tabs that apply pre-baked filter chips on top of the user's
/// current state. Available for built-in productivity collections;
/// non-curated collections fall back to All / Archived.
struct CuratedTabsView: View {
    let collection: DBCollection
    @Binding var state: DBFilterState
    @State private var activeTabId: String

    init(collection: DBCollection, state: Binding<DBFilterState>) {
        self.collection = collection
        self._state = state
        let tabs = CuratedFilterRegistry.tabs(for: collection.name)
        self._activeTabId = State(initialValue: tabs.first?.id ?? "all")
    }

    var body: some View {
        let tabs = CuratedFilterRegistry.tabs(for: collection.name)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    Button {
                        applyTab(tab)
                    } label: {
                        Text(tab.label)
                            .font(BodyFont.system(size: 12, wght: activeTabId == tab.id ? 600 : 500))
                            .foregroundColor(activeTabId == tab.id ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(activeTabId == tab.id ? Color.white.opacity(0.08) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .onAppear {
            // Apply default tab on first appear if state is empty.
            if state.chips.isEmpty {
                if let tab = tabs.first { applyTab(tab) }
            } else {
                syncActiveTab(tabs)
            }
        }
        .onChange(of: state) { _, _ in
            syncActiveTab(tabs)
        }
    }

    private func applyTab(_ tab: CuratedFilterRegistry.Tab) {
        activeTabId = tab.id
        // Replace the fields controlled by curated tabs so switching
        // from Done back to Anytime cannot keep a stale status chip.
        let curatedFields = Set(CuratedFilterRegistry.tabs(for: collection.name).flatMap { tab in
            tab.chips.map(\.field)
        })
        let userChips = state.chips.filter { !curatedFields.contains($0.field) }
        state.chips = tab.chips + userChips
        if let sort = tab.sort {
            state.sort = sort
        }
    }

    private func syncActiveTab(_ tabs: [CuratedFilterRegistry.Tab]) {
        let curatedFields = Set(tabs.flatMap { tab in tab.chips.map(\.field) })
        let current = state.chips.filter { curatedFields.contains($0.field) }
        if let match = tabs.first(where: { tabMatches($0, currentChips: current) }) {
            activeTabId = match.id
        }
    }

    private func tabMatches(_ tab: CuratedFilterRegistry.Tab, currentChips: [DBFilterState.Chip]) -> Bool {
        guard tab.sort == nil || state.sort == tab.sort else { return false }
        guard tab.chips.count == currentChips.count else { return false }
        return tab.chips.allSatisfy { expected in
            currentChips.contains { current in
                current.field == expected.field
                    && current.op == expected.op
                    && current.value == expected.value
            }
        }
    }
}
