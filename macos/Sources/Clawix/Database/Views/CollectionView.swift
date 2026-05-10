import SwiftUI

/// Orchestrates the table + filter bar + curated tabs + detail pane for
/// a single collection. Used both inside the curated sidebar entries
/// (Tasks/Goals/Notes/Projects) and inside the database admin 3-pane.
struct CollectionView: View {
    let collection: DBCollection
    let showsCuratedTabs: Bool

    @EnvironmentObject private var manager: DatabaseManager
    @State private var selectedIds: Set<String> = []
    @State private var focusedId: String?
    @State private var detailVisible: Bool = true
    @State private var showCreate: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.white.opacity(0.07))
            if showsCuratedTabs {
                CuratedTabsView(collection: collection, state: filterBinding)
                Divider().background(Color.white.opacity(0.04))
            }
            FilterBar(collection: collection, state: filterBinding)
            Divider().background(Color.white.opacity(0.07))
            HStack(spacing: 0) {
                tableArea
                if detailVisible, let focused = focusedRecord {
                    Divider().background(Color.white.opacity(0.07))
                    RecordDetailPane(collection: collection, record: focused)
                        .id("\(focused.id)-\(focused.updatedAt)")
                        .frame(width: 380)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !selectedIds.isEmpty {
                BulkToolbar(collection: collection, selectedIds: $selectedIds)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedIds.isEmpty)
        .task(id: collection.id) {
            manager.subscribeRealtime(collection: collection.name)
            await manager.refreshRecords(collection: collection.name)
        }
        .onChange(of: filterState) { _, _ in
            // refresh handled by setFilterState; keep here as a safety net
        }
        .sheet(isPresented: $showCreate) {
            QuickCreateRecordSheet(collection: collection) { newId in
                showCreate = false
                if let id = newId { focusedId = id }
            }
            .frame(minWidth: 440, minHeight: 320)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(collection.displayName)
                .font(BodyFont.system(size: 16, wght: 600))
                .foregroundColor(Palette.textPrimary)
            if collection.builtin {
                Text("built-in")
                    .font(BodyFont.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .foregroundColor(Palette.textSecondary)
            }
            Text("\(records.count)")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)

            Spacer()

            Button {
                detailVisible.toggle()
            } label: {
                Image(systemName: detailVisible ? "sidebar.right" : "sidebar.right")
                    .foregroundColor(Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Toggle detail pane")

            Button {
                showCreate = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New")
                }
                .font(BodyFont.system(size: 12, wght: 600))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.85))
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var tableArea: some View {
        ZStack {
            if records.isEmpty {
                emptyState
            } else {
                RecordsTableView(
                    collection: collection,
                    records: records,
                    selectedIds: $selectedIds,
                    focusedId: $focusedId
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(Palette.textTertiary)
            Text("No records yet")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text("Create one with the New button or the CLI.")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textTertiary)
            Button("Create record") { showCreate = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    private var records: [DBRecord] {
        manager.records(for: collection.name)
    }

    private var focusedRecord: DBRecord? {
        if let id = focusedId, let record = records.first(where: { $0.id == id }) {
            return record
        }
        return records.first
    }

    private var filterState: DBFilterState {
        manager.filterState(for: collection.name)
    }

    private var filterBinding: Binding<DBFilterState> {
        Binding(
            get: { manager.filterState(for: collection.name) },
            set: { manager.setFilterState($0, for: collection.name) }
        )
    }
}
