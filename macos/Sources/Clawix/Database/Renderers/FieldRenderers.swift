import SwiftUI
import AppKit

/// Field renderers translate a `DBJSON` value + `DBFieldDefinition` into
/// either a compact table cell or an editable form field. There's one
/// renderer per `DBFieldType`. The table cell version is read-only or
/// supports inline editing for primitives; the form field version is
/// always editable.

// MARK: - Cell rendering (table cells)

@MainActor
enum FieldCell {

    @ViewBuilder
    static func render(
        field: DBFieldDefinition,
        value: DBJSON,
        record: DBRecord,
        onCommit: @escaping (DBJSON) -> Void
    ) -> some View {
        switch field.type {
        case .text, .currency, .address, .phone, .markdown, .colorHex, .barcode:
            TextCell(field: field, value: value, onCommit: onCommit)
        case .number, .money, .rating, .duration, .percent:
            NumberCell(field: field, value: value, onCommit: onCommit)
        case .boolean:
            BooleanCell(value: value, onCommit: onCommit)
        case .date:
            DateCell(value: value)
        case .select:
            SelectCell(field: field, value: value, onCommit: onCommit)
        case .json:
            JSONCell(value: value)
        case .geoPoint:
            JSONCell(value: value)
        case .relation:
            RelationCell(field: field, value: value)
        case .file:
            FileCell(value: value)
        case .email:
            EmailCell(value: value)
        case .url:
            URLCell(value: value)
        }
    }
}

private struct TextCell: View {
    let field: DBFieldDefinition
    let value: DBJSON
    let onCommit: (DBJSON) -> Void
    @State private var draft: String = ""
    @State private var editing: Bool = false

    var body: some View {
        let text = value.stringValue ?? ""
        Group {
            if field.prefersLongText {
                Text(text.isEmpty ? "—" : text)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(text.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                    .lineLimit(2)
            } else {
                if editing {
                    TextField("", text: $draft, onCommit: {
                        onCommit(.string(draft))
                        editing = false
                    })
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(Palette.textPrimary)
                    .onAppear { draft = text }
                } else {
                    Text(text.isEmpty ? "—" : text)
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(text.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            draft = text
                            editing = true
                        }
                }
            }
        }
    }
}

private struct NumberCell: View {
    let field: DBFieldDefinition
    let value: DBJSON
    let onCommit: (DBJSON) -> Void
    @State private var draft: String = ""
    @State private var editing: Bool = false

    var body: some View {
        let display: String = {
            if let v = value.doubleValue {
                if v.truncatingRemainder(dividingBy: 1) == 0 {
                    return String(Int64(v))
                }
                return String(v)
            }
            return ""
        }()
        Group {
            if editing {
                TextField("", text: $draft, onCommit: {
                    if let v = Double(draft) {
                        onCommit(.number(v))
                    }
                    editing = false
                })
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
                .monospacedDigit()
                .onAppear { draft = display }
            } else {
                Text(display.isEmpty ? "—" : display)
                    .font(BodyFont.system(size: 12))
                    .foregroundColor(display.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        draft = display
                        editing = true
                    }
            }
        }
    }
}

private struct BooleanCell: View {
    let value: DBJSON
    let onCommit: (DBJSON) -> Void
    var body: some View {
        let isOn = value.boolValue ?? false
        Toggle("", isOn: Binding(
            get: { isOn },
            set: { onCommit(.bool($0)) }
        ))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
    }
}

private struct DateCell: View {
    let value: DBJSON
    var body: some View {
        Text(formatRelative(value.stringValue))
            .font(BodyFont.system(size: 12))
            .foregroundColor(Palette.textSecondary)
            .lineLimit(1)
    }

    private func formatRelative(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct SelectCell: View {
    let field: DBFieldDefinition
    let value: DBJSON
    let onCommit: (DBJSON) -> Void
    var body: some View {
        let current = value.stringValue ?? ""
        Menu {
            ForEach(field.options ?? [], id: \.self) { option in
                Button(option) { onCommit(.string(option)) }
            }
        } label: {
            Text(current.isEmpty ? "—" : current)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(SelectColor.color(for: current).opacity(0.18))
                .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct JSONCell: View {
    let value: DBJSON
    var body: some View {
        Text(preview(value))
            .font(BodyFont.system(size: 11.5))
            .foregroundColor(Palette.textSecondary)
            .lineLimit(1)
            .monospaced()
    }

    private func preview(_ value: DBJSON) -> String {
        switch value {
        case .null: return "—"
        case .array(let arr): return "[\(arr.count) items]"
        case .object(let obj): return "{\(obj.count) keys}"
        case .string(let s): return s
        case .number(let n): return String(n)
        case .integer(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        }
    }
}

private struct RelationCell: View {
    let field: DBFieldDefinition
    let value: DBJSON
    @EnvironmentObject private var manager: DatabaseManager

    var body: some View {
        let id = value.stringValue ?? ""
        Text(label(for: id))
            .font(BodyFont.system(size: 12))
            .foregroundColor(id.isEmpty ? Palette.textTertiary : Palette.textPrimary)
            .lineLimit(1)
    }

    private func label(for id: String) -> String {
        guard !id.isEmpty else { return "—" }
        guard let collectionName = field.relation?.collectionName else { return id }
        let records = manager.records(for: collectionName)
        if let record = records.first(where: { $0.id == id }) {
            return record.titleString
        }
        return String(id.prefix(8))
    }
}

private struct FileCell: View {
    let value: DBJSON
    var body: some View {
        if let id = value.stringValue, !id.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "paperclip")
                    .font(.system(size: 10))
                Text("file")
                    .font(BodyFont.system(size: 11.5))
            }
            .foregroundColor(Palette.textSecondary)
        } else {
            Text("—")
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textTertiary)
        }
    }
}

private struct EmailCell: View {
    let value: DBJSON
    var body: some View {
        let s = value.stringValue ?? ""
        Text(s.isEmpty ? "—" : s)
            .font(BodyFont.system(size: 12))
            .foregroundColor(s.isEmpty ? Palette.textTertiary : Palette.textPrimary)
            .lineLimit(1)
            .onTapGesture {
                if !s.isEmpty, let url = URL(string: "mailto:\(s)") {
                    NSWorkspace.shared.open(url)
                }
            }
    }
}

private struct URLCell: View {
    let value: DBJSON
    var body: some View {
        let s = value.stringValue ?? ""
        Text(s.isEmpty ? "—" : s)
            .font(BodyFont.system(size: 12))
            .foregroundColor(s.isEmpty ? Palette.textTertiary : Color.accentColor)
            .lineLimit(1)
            .underline(!s.isEmpty)
            .onTapGesture {
                if !s.isEmpty, let url = URL(string: s) {
                    NSWorkspace.shared.open(url)
                }
            }
    }
}

// MARK: - Form fields (detail pane)

@MainActor
enum FieldForm {

    @ViewBuilder
    static func render(
        field: DBFieldDefinition,
        value: Binding<DBJSON>,
        record: DBRecord
    ) -> some View {
        switch field.type {
        case .text, .currency, .address, .phone, .markdown, .colorHex, .barcode:
            TextForm(field: field, value: value)
        case .number, .money, .rating, .duration, .percent:
            NumberForm(value: value)
        case .boolean:  BooleanForm(value: value)
        case .date:     DateForm(value: value)
        case .select:   SelectForm(field: field, value: value)
        case .json, .geoPoint: JSONForm(value: value)
        case .relation: RelationForm(field: field, value: value)
        case .file:     FileForm(field: field, value: value, record: record)
        case .email:    EmailForm(value: value)
        case .url:      URLForm(value: value)
        }
    }
}

private struct TextForm: View {
    let field: DBFieldDefinition
    @Binding var value: DBJSON
    var body: some View {
        if field.prefersLongText {
            TextEditor(text: Binding(
                get: { value.stringValue ?? "" },
                set: { value = $0.isEmpty ? .null : .string($0) }
            ))
            .font(BodyFont.system(size: 13))
            .foregroundColor(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(minHeight: 110)
        } else {
            TextField("", text: Binding(
                get: { value.stringValue ?? "" },
                set: { value = $0.isEmpty ? .null : .string($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(BodyFont.system(size: 13))
        }
    }
}

private struct NumberForm: View {
    @Binding var value: DBJSON
    @State private var draft: String = ""
    var body: some View {
        TextField("", text: Binding(
            get: { draft.isEmpty ? (value.doubleValue.map { fmt($0) } ?? "") : draft },
            set: { newValue in
                draft = newValue
                if newValue.isEmpty {
                    value = .null
                } else if let v = Double(newValue) {
                    value = .number(v)
                }
            }
        ))
        .textFieldStyle(.roundedBorder)
        .font(BodyFont.system(size: 13))
        .monospacedDigit()
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(v)) : String(v)
    }
}

private struct BooleanForm: View {
    @Binding var value: DBJSON
    var body: some View {
        Toggle("", isOn: Binding(
            get: { value.boolValue ?? false },
            set: { value = .bool($0) }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
    }
}

private struct DateForm: View {
    @Binding var value: DBJSON
    var body: some View {
        let date = parsed
        DatePicker(
            "",
            selection: Binding(
                get: { date ?? Date() },
                set: { value = .string(ISO8601DateFormatter().string(from: $0)) }
            ),
            displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
    }

    private var parsed: Date? {
        guard let s = value.stringValue else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
}

private struct SelectForm: View {
    let field: DBFieldDefinition
    @Binding var value: DBJSON
    var body: some View {
        Picker("", selection: Binding(
            get: { value.stringValue ?? "" },
            set: { value = .string($0) }
        )) {
            Text("—").tag("")
            ForEach(field.options ?? [], id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

private struct JSONForm: View {
    @Binding var value: DBJSON
    @State private var text: String = ""
    @State private var isValid: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: Binding(
                get: { text.isEmpty ? format(value) : text },
                set: { newValue in
                    text = newValue
                    if let data = newValue.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) {
                        value = DBJSON.wrap(json)
                        isValid = true
                    } else if newValue.isEmpty {
                        value = .null
                        isValid = true
                    } else {
                        isValid = false
                    }
                }
            ))
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(minHeight: 100)
            if !isValid {
                Text("Invalid JSON")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
    }
    private func format(_ value: DBJSON) -> String {
        switch value {
        case .null: return ""
        case .object, .array:
            if let data = try? JSONSerialization.data(withJSONObject: value.foundationValue, options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return ""
        default: return value.stringValue ?? ""
        }
    }
}

private struct RelationForm: View {
    let field: DBFieldDefinition
    @Binding var value: DBJSON
    @EnvironmentObject private var manager: DatabaseManager

    var body: some View {
        let collectionName = field.relation?.collectionName ?? ""
        let records = manager.records(for: collectionName)
        Picker("", selection: Binding(
            get: { value.stringValue ?? "" },
            set: { value = $0.isEmpty ? .null : .string($0) }
        )) {
            Text("—").tag("")
            ForEach(records) { record in
                Text(record.titleString).tag(record.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .task {
            if records.isEmpty, !collectionName.isEmpty {
                await manager.refreshRecords(collection: collectionName)
            }
        }
    }
}

private struct FileForm: View {
    let field: DBFieldDefinition
    @Binding var value: DBJSON
    let record: DBRecord
    @EnvironmentObject private var manager: DatabaseManager
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let id = value.stringValue, !id.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text(String(id.prefix(8)))
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Button("Open") {
                        Task { await openFile(id: id) }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5))
                    Button("Remove") {
                        value = .null
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                }
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(height: 64)
                .overlay(
                    Text(isTargeted ? "Drop file…" : "Drag & drop a file here")
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(Palette.textSecondary)
                )
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
        }
    }

    private func openFile(id: String) async {
        do {
            let data = try await manager.client.downloadFile(fileId: id)
            let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(id)-preview")
            try data.write(to: temp)
            NSWorkspace.shared.open(temp)
        } catch {
            // ignore
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    do {
                        let data = try Data(contentsOf: url)
                        let asset = try await manager.client.uploadFile(
                            namespaceId: manager.currentNamespace,
                            collectionName: nil,
                            recordId: record.id,
                            filename: url.lastPathComponent,
                            contentType: contentType(for: url),
                            data: data
                        )
                        value = .string(asset.id)
                    } catch {
                        // surface error via manager.lastError later
                    }
                }
            }
        }
    }

    private func contentType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        default: return "application/octet-stream"
        }
    }
}

private struct EmailForm: View {
    @Binding var value: DBJSON
    var body: some View {
        TextField("name@example.com", text: Binding(
            get: { value.stringValue ?? "" },
            set: { value = $0.isEmpty ? .null : .string($0) }
        ))
        .textFieldStyle(.roundedBorder)
        .font(BodyFont.system(size: 13))
    }
}

private struct URLForm: View {
    @Binding var value: DBJSON
    var body: some View {
        TextField("https://", text: Binding(
            get: { value.stringValue ?? "" },
            set: { value = $0.isEmpty ? .null : .string($0) }
        ))
        .textFieldStyle(.roundedBorder)
        .font(BodyFont.system(size: 13))
    }
}

// MARK: - Select pill colors

@MainActor
enum SelectColor {
    static func color(for option: String) -> Color {
        let lower = option.lowercased()
        if lower.contains("done") || lower == "ok" || lower == "active" || lower == "released" || lower == "succeeded" || lower == "approved" {
            return .green
        }
        if lower.contains("progress") || lower == "running" || lower == "investigating" || lower == "in_review" {
            return .blue
        }
        if lower.contains("blocked") || lower == "failed" || lower == "rejected" || lower == "fired" || lower == "red" || lower == "urgent" {
            return .red
        }
        if lower.contains("paused") || lower == "degraded" || lower == "yellow" || lower == "high" || lower == "warning" {
            return .yellow
        }
        if lower.contains("archived") || lower == "cancelled" || lower == "ignored" {
            return .gray
        }
        return .accentColor
    }
}
