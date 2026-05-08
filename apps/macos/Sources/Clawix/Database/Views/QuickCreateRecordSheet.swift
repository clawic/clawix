import SwiftUI

/// Compact sheet to create a record with the minimum required fields.
/// Built-in collections all have at least one required field; this
/// sheet renders a form for those plus an optional title/name.
struct QuickCreateRecordSheet: View {
    let collection: DBCollection
    let onCreated: (String?) -> Void

    @EnvironmentObject private var manager: DatabaseManager
    @State private var draft: [String: DBJSON] = [:]
    @State private var saving: Bool = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New \(collection.displayName.lowercased().trimmingCharacters(in: .whitespaces))")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("Cancel") { onCreated(nil); dismiss() }
                    .buttonStyle(.borderless)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleFields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(field.name)
                                    .font(BodyFont.system(size: 11.5, wght: 600))
                                    .foregroundColor(Palette.textSecondary)
                                if field.isRequired {
                                    Text("required")
                                        .font(BodyFont.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                            }
                            FieldForm.render(
                                field: field,
                                value: binding(for: field.name),
                                record: stub
                            )
                        }
                    }
                }
            }
            if let error {
                Text(error)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
            }
            HStack {
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving || !isValid)
                .keyboardShortcut(.defaultAction)
                if saving { ProgressView().controlSize(.small) }
            }
        }
        .padding(20)
    }

    private var visibleFields: [DBFieldDefinition] {
        // Required fields first, then a title-ish field if not already
        // required. Cap at 8 to keep the sheet compact.
        var seen = Set<String>()
        var result: [DBFieldDefinition] = []
        for f in collection.fields where f.isRequired {
            if !seen.contains(f.name) { result.append(f); seen.insert(f.name) }
        }
        if let title = collection.titleField, !seen.contains(title.name) {
            result.append(title)
            seen.insert(title.name)
        }
        return Array(result.prefix(8))
    }

    private var stub: DBRecord {
        DBRecord(id: "", createdAt: "", updatedAt: "", data: draft)
    }

    private func binding(for name: String) -> Binding<DBJSON> {
        Binding(
            get: { draft[name] ?? .null },
            set: { draft[name] = $0 }
        )
    }

    private var isValid: Bool {
        for field in collection.fields where field.isRequired {
            let value = draft[field.name] ?? .null
            if value.isNull { return false }
            if case .string(let s) = value, s.isEmpty { return false }
        }
        return true
    }

    private func create() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            let record = try await manager.createRecord(collection: collection.name, data: draft)
            onCreated(record.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
