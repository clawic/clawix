import SwiftUI

/// Cross-collection search overlay. Activated by ⌘⇧F (or wired by the
/// app's existing command palette). Searches `title`/`name`/`searchText`
/// across the four curated collections plus `decisions` and
/// `inbox_messages`. Selecting a result navigates to that collection.
struct DatabaseSearchOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var manager: DatabaseManager
    @EnvironmentObject private var appState: AppState

    @State private var query: String = ""
    @State private var results: [Result] = []
    @State private var debounce: Task<Void, Never>?

    struct Result: Identifiable, Equatable {
        let id: String
        let collection: String
        let collectionLabel: String
        let title: String
        let snippet: String
        let recordId: String
    }

    private let searchableCollections: [String] = [
        "tasks", "goals", "notes", "projects", "decisions", "inbox_messages",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Palette.textSecondary)
                TextField("Search across collections…", text: $query)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 14))
                    .onChange(of: query) { _ in scheduleSearch() }
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider().background(Color.white.opacity(0.07))
            if query.isEmpty {
                placeholder
            } else if results.isEmpty {
                Text("No matches.")
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick actions")
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Palette.textTertiary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            actionRow(label: "New task", systemIcon: "checkmark.circle") {
                appState.currentRoute = .databaseCollection("tasks")
                isPresented = false
            }
            actionRow(label: "New note", systemIcon: "note.text") {
                appState.currentRoute = .databaseCollection("notes")
                isPresented = false
            }
            actionRow(label: "Open Database admin", systemIcon: "cylinder.split.1x2") {
                appState.currentRoute = .databaseHome
                isPresented = false
            }
        }
        .padding(.vertical, 6)
    }

    private func actionRow(label: String, systemIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemIcon)
                    .frame(width: 18)
                    .foregroundColor(Palette.textSecondary)
                Text(label)
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func resultRow(_ result: Result) -> some View {
        Button {
            appState.currentRoute = .databaseCollection(result.collection)
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(result.collectionLabel.uppercased())
                    .font(BodyFont.system(size: 9.5, wght: 700))
                    .foregroundColor(Palette.textTertiary)
                    .frame(width: 90, alignment: .leading)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    if !result.snippet.isEmpty {
                        Text(result.snippet)
                            .font(BodyFont.system(size: 11.5))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleSearch() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        var found: [Result] = []
        for collection in searchableCollections {
            guard let collectionDef = manager.collection(named: collection) else { continue }
            // Use the cached records when the collection has been loaded;
            // otherwise fetch a fresh list.
            var records = manager.records(for: collection)
            if records.isEmpty {
                await manager.refreshRecords(collection: collection)
                records = manager.records(for: collection)
            }
            for record in records {
                let titleHit = record.titleString.lowercased().contains(q)
                let textHit = record.data.values.contains { $0.stringValue?.lowercased().contains(q) == true }
                guard titleHit || textHit else { continue }
                let snippet = record.data.values.compactMap { $0.stringValue }.first { $0.lowercased().contains(q) } ?? ""
                found.append(Result(
                    id: "\(collection):\(record.id)",
                    collection: collection,
                    collectionLabel: collectionDef.displayName,
                    title: record.titleString,
                    snippet: snippet == record.titleString ? "" : String(snippet.prefix(120)),
                    recordId: record.id
                ))
                if found.count >= 60 { break }
            }
            if found.count >= 60 { break }
        }
        results = found
    }
}
