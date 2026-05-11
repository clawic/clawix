import SwiftUI

/// Above-the-table chip-driven filter UI. Each chip is a (field, op,
/// value) triple combined with AND. Adding a chip opens a popover with
/// field picker + value input.
struct FilterBar: View {
    let collection: DBCollection
    @Binding var state: DBFilterState
    @State private var addingChip: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Palette.textSecondary)
                    .font(.system(size: 11))
                TextField("Search", text: $state.search)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12))
                    .frame(maxWidth: 220)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(Capsule())

            ForEach(state.chips) { chip in
                ChipView(chip: chip, collection: collection) { updated in
                    if let idx = state.chips.firstIndex(where: { $0.id == chip.id }) {
                        if let updated {
                            state.chips[idx] = updated
                        } else {
                            state.chips.remove(at: idx)
                        }
                    }
                }
            }

            Button {
                addingChip = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("Filter")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                }
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.03))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $addingChip) {
                AddChipPopover(collection: collection) { chip in
                    state.chips.append(chip)
                    addingChip = false
                }
                .padding(12)
                .frame(minWidth: 240)
            }

            Spacer()

            if let sort = state.sort {
                HStack(spacing: 4) {
                    Image(systemName: sort.descending ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10))
                    Text(sort.field)
                        .font(BodyFont.system(size: 11.5))
                }
                .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ChipView: View {
    let chip: DBFilterState.Chip
    let collection: DBCollection
    let onChange: (DBFilterState.Chip?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(chip.field)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(opLabel(chip.op))
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary)
            Text(valueLabel(chip.value))
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
            Button {
                onChange(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.18))
        .clipShape(Capsule())
    }

    private func opLabel(_ op: DBFilterState.Op) -> String {
        switch op {
        case .eq: return "="
        case .neq: return "≠"
        case .isNull: return "is empty"
        case .notNull: return "is not empty"
        }
    }
    private func valueLabel(_ value: DBJSON) -> String {
        value.stringValue ?? ""
    }
}

private struct AddChipPopover: View {
    let collection: DBCollection
    let onAdd: (DBFilterState.Chip) -> Void

    @State private var fieldName: String = ""
    @State private var op: DBFilterState.Op = .eq
    @State private var stringValue: String = ""
    @State private var selectValue: String = ""

    private var selectedField: DBFieldDefinition? {
        collection.fields.first(where: { $0.name == fieldName })
    }

    private var parsedValue: DBJSON? {
        if op == .isNull || op == .notNull { return .null }
        guard let field = selectedField else { return nil }
        if field.type == .select {
            return selectValue.isEmpty ? nil : .string(selectValue)
        }
        return Self.parseValue(stringValue, for: field.type)
    }

    private var canAdd: Bool {
        !fieldName.isEmpty && parsedValue != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add filter")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Picker("Field", selection: $fieldName) {
                Text("Select…").tag("")
                ForEach(collection.fields) { field in
                    Text(field.name).tag(field.name)
                }
            }
            .pickerStyle(.menu)
            Picker("Operator", selection: $op) {
                Text("equals").tag(DBFilterState.Op.eq)
                Text("not equals").tag(DBFilterState.Op.neq)
                Text("is empty").tag(DBFilterState.Op.isNull)
                Text("is not empty").tag(DBFilterState.Op.notNull)
            }
            .pickerStyle(.menu)
            if op == .eq || op == .neq {
                if let field = selectedField, field.type == .select {
                    Picker("Value", selection: $selectValue) {
                        Text("…").tag("")
                        ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                } else {
                    TextField("value", text: $stringValue)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Button("Add") {
                guard let value = parsedValue else { return }
                onAdd(DBFilterState.Chip(field: fieldName, op: op, value: value))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdd)
        }
    }

    private static func parseValue(_ rawValue: String, for type: DBFieldType) -> DBJSON? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch type {
        case .number, .money, .rating, .duration, .percent:
            if let integer = Int64(trimmed), String(integer) == trimmed {
                return .integer(integer)
            }
            return Double(trimmed).map(DBJSON.number)
        case .boolean:
            switch trimmed.lowercased() {
            case "true", "yes", "1", "on": return .bool(true)
            case "false", "no", "0", "off": return .bool(false)
            default: return nil
            }
        case .json, .geoPoint:
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return DBJSON.wrap(object)
        default:
            return .string(trimmed)
        }
    }
}
