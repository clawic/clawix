import SwiftUI

/// Wide adaptive table that renders any `DBCollection`. Columns come
/// from the collection's `essentialFields` (with the user's optional
/// expansions). Inline edit on simple fields commits immediately via
/// `DatabaseManager.updateRecord`.
struct RecordsTableView: View {
    let collection: DBCollection
    let records: [DBRecord]
    @Binding var selectedIds: Set<String>
    @Binding var focusedId: String?

    @EnvironmentObject private var manager: DatabaseManager

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.07))
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        rowView(for: record)
                        Divider().background(Color.white.opacity(0.04))
                    }
                }
            }
        }
    }

    private var visibleFields: [DBFieldDefinition] {
        collection.essentialFields
    }

    private var header: some View {
        HStack(spacing: 0) {
            // Selection checkbox column
            Toggle("", isOn: Binding(
                get: { selectedIds.count == records.count && !records.isEmpty },
                set: { all in
                    selectedIds = all ? Set(records.map { $0.id }) : []
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 28)
            .padding(.horizontal, 6)

            ForEach(visibleFields, id: \.name) { field in
                Text(field.name)
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                    .frame(width: columnWidth(for: field), alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .onTapGesture {
                        toggleSort(on: field.name)
                    }
            }
            Spacer(minLength: 0)
        }
        .background(Color.white.opacity(0.03))
    }

    private func rowView(for record: DBRecord) -> some View {
        let isSelected = selectedIds.contains(record.id)
        let isFocused = focusedId == record.id
        return HStack(spacing: 0) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { isOn in
                    if isOn { selectedIds.insert(record.id) }
                    else { selectedIds.remove(record.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 28)
            .padding(.horizontal, 6)

            ForEach(visibleFields, id: \.name) { field in
                FieldCell.render(
                    field: field,
                    value: record.data[field.name] ?? .null,
                    record: record,
                    onCommit: { newValue in
                        commit(field: field, newValue: newValue, record: record)
                    }
                )
                .frame(width: columnWidth(for: field), alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .background(rowBackground(isSelected: isSelected, isFocused: isFocused))
        .onTapGesture {
            focusedId = record.id
        }
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool, isFocused: Bool) -> some View {
        if isSelected {
            Color.accentColor.opacity(0.12)
        } else if isFocused {
            Color.white.opacity(0.04)
        } else {
            Color.clear
        }
    }

    private func columnWidth(for field: DBFieldDefinition) -> CGFloat {
        switch field.type {
        case .text, .address, .markdown: return field.prefersLongText ? 280 : 200
        case .number, .money, .rating, .duration, .percent: return 100
        case .boolean: return 60
        case .date:    return 130
        case .select:  return 120
        case .json, .geoPoint: return 180
        case .relation: return 160
        case .file:    return 80
        case .email, .currency, .phone, .colorHex, .barcode: return 220
        case .url: return 240
        }
    }

    private func toggleSort(on field: String) {
        var current = manager.filterState(for: collection.name)
        if current.sort?.field == field {
            current.sort = DBFilterState.Sort(field: field, descending: !(current.sort?.descending ?? false))
        } else {
            current.sort = DBFilterState.Sort(field: field, descending: false)
        }
        manager.setFilterState(current, for: collection.name)
    }

    private func commit(field: DBFieldDefinition, newValue: DBJSON, record: DBRecord) {
        Task {
            try? await manager.updateRecord(
                collection: collection.name,
                id: record.id,
                data: [field.name: newValue]
            )
        }
    }
}
