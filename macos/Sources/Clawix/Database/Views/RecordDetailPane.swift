import SwiftUI

/// Side pane that shows the full schema of a focused record. Edits flow
/// through `DatabaseManager.updateRecord` after a 600ms debounce so we
/// don't fire one PATCH per keystroke. The pane is collapsible (a
/// toolbar button on the parent CollectionView toggles its visibility).
struct RecordDetailPane: View {
    let collection: DBCollection
    let record: DBRecord

    @EnvironmentObject private var manager: DatabaseManager
    @State private var draft: [String: DBJSON] = [:]
    @State private var debounce: Task<Void, Never>?
    @State private var savedAt: Date?
    @State private var saving: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.07))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(collection.fields) { field in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(field.name)
                                    .font(BodyFont.system(size: 11.5, wght: 600))
                                    .foregroundColor(Palette.textSecondary)
                                Text(field.type.rawValue)
                                    .font(BodyFont.system(size: 10))
                                    .foregroundColor(Palette.textTertiary)
                                if field.isRequired {
                                    Text("required")
                                        .font(BodyFont.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                            }
                            FieldForm.render(
                                field: field,
                                value: binding(for: field.name),
                                record: record
                            )
                        }
                    }
                    metaSection
                }
                .padding(16)
            }
        }
        .background(Color.white.opacity(0.02))
        .onAppear { hydrateDraft() }
        .onChange(of: record.id) { _, _ in
            hydrateDraft()
        }
        .onChange(of: record) { _, _ in
            hydrateDraft()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(record.titleString)
                .font(BodyFont.system(size: 14, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
            Spacer()
            if saving {
                ProgressView().controlSize(.small)
            } else if let savedAt {
                Text("Saved \(savedAt.formatted(.relative(presentation: .numeric)))")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Menu {
                Button("Archive") {
                    Task { try? await manager.archiveRecord(collection: collection.name, id: record.id) }
                }
                Button("Restore") {
                    Task { try? await manager.restoreRecord(collection: collection.name, id: record.id) }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    Task { try? await manager.deleteRecord(collection: collection.name, id: record.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(Palette.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ID")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                Text(record.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text("Created")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                Text(record.createdAt)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }
            HStack {
                Text("Updated")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                Text(record.updatedAt)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }
        }
        .padding(.top, 12)
    }

    private func binding(for name: String) -> Binding<DBJSON> {
        Binding(
            get: { draft[name] ?? record.data[name] ?? .null },
            set: { newValue in
                draft[name] = newValue
                scheduleSave(name: name, value: newValue)
            }
        )
    }

    private func hydrateDraft() {
        draft = record.data
    }

    private func scheduleSave(name: String, value: DBJSON) {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saving = true
            do {
                _ = try await manager.updateRecord(
                    collection: collection.name,
                    id: record.id,
                    data: [name: value]
                )
                savedAt = Date()
            } catch {
                // surfaced via manager.lastError
            }
            saving = false
        }
    }
}
