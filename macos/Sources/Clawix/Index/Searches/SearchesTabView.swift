import SwiftUI

struct SearchesTabView: View {
    @ObservedObject var manager: IndexManager
    let onCreate: () -> Void
    @State private var selectedSearchId: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchListHeader
                CardDivider()
                searchList
            }
            .frame(maxWidth: .infinity)
            CardDivider()
            SearchDetailPane(
                manager: manager,
                searchId: selectedSearchId
            )
            .frame(width: 360)
            .background(Color.black.opacity(0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchListHeader: some View {
        HStack {
            Text("\(manager.searches.count) saved searches")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Button(action: onCreate) {
                HStack(spacing: 6) {
                    LucideIcon.auto("plus", size: 11)
                    Text("New search")
                        .font(BodyFont.system(size: 12, wght: 500))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var searchList: some View {
        Group {
            if manager.searches.isEmpty {
                IndexEmptyState(
                    title: "No saved searches",
                    systemImage: "magnifyingglass",
                    description: "Create one with a target type, criteria and a prompt template. Then run it."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.searches) { search in
                            SearchRow(
                                search: search,
                                isSelected: selectedSearchId == search.id,
                                onSelect: { selectedSearchId = search.id },
                                onRun: {
                                    Task { _ = try? await manager.runSearch(id: search.id) }
                                },
                                onDelete: {
                                    Task { await manager.deleteSearch(id: search.id) }
                                }
                            )
                            CardDivider()
                        }
                    }
                }
                .thinScrollers()
            }
        }
    }
}

private struct SearchRow: View {
    let search: ClawJSIndexClient.Search
    let isSelected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                LucideIcon.auto("magnifyingglass", size: 13)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(search.name)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(.white.opacity(0.92))
                    if let prompt = search.promptTemplate {
                        Text(prompt)
                            .font(BodyFont.system(size: 11, wght: 400))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button(action: onRun) {
                    HStack(spacing: 5) {
                        LucideIcon.auto("play", size: 11)
                        Text("Run now")
                            .font(BodyFont.system(size: 11.5, wght: 600))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    LucideIcon.auto("trash", size: 11)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(7)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isSelected ? Color.white.opacity(0.06) : (hovered ? Color.white.opacity(0.03) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct SearchDetailPane: View {
    @ObservedObject var manager: IndexManager
    let searchId: String?

    private var search: ClawJSIndexClient.Search? {
        guard let id = searchId else { return nil }
        return manager.searches.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let search {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(text: "Criteria")
                        if search.criteria.isEmpty {
                            Text("(no criteria)")
                                .font(BodyFont.system(size: 12, wght: 400))
                                .foregroundColor(.white.opacity(0.45))
                        } else {
                            ForEach(Array(search.criteria.keys.sorted()), id: \.self) { key in
                                CriterionRow(key: key, value: search.criteria[key] ?? .null)
                            }
                        }
                        if let prompt = search.promptTemplate {
                            SectionTitle(text: "Prompt template")
                            Text(prompt)
                                .font(BodyFont.system(size: 12, wght: 400))
                                .foregroundColor(.white.opacity(0.82))
                                .lineSpacing(2)
                        }
                        SectionTitle(text: "Recent runs")
                        let runs = manager.runs.filter { $0.searchId == search.id }
                        if runs.isEmpty {
                            Text("No runs yet.")
                                .font(BodyFont.system(size: 12, wght: 400))
                                .foregroundColor(.white.opacity(0.45))
                        } else {
                            ForEach(runs) { run in
                                RunSummaryRow(run: run)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .thinScrollers()
            } else {
                Text("Select a search.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(.white.opacity(0.40))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(BodyFont.system(size: 10.5, wght: 700))
            .kerning(0.5)
            .foregroundColor(.white.opacity(0.50))
    }
}

private struct CriterionRow: View {
    let key: String
    let value: AnyJSON
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(.white.opacity(0.72))
                .frame(width: 110, alignment: .leading)
            Text(stringify(value))
                .font(BodyFont.system(size: 11.5, wght: 400))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func stringify(_ value: AnyJSON) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return String(n)
        case .string(let s): return s
        case .array(let entries):
            return entries.compactMap { entry -> String? in
                if let s = entry.asString { return s }
                if let n = entry.asNumber { return String(n) }
                return nil
            }.joined(separator: ", ")
        case .object: return "{…}"
        }
    }
}

struct RunSummaryRow: View {
    let run: ClawJSIndexClient.Run
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.status.capitalized)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white.opacity(0.85))
                Text("\(run.entitiesSeen) entities · \(run.observationsCount) obs · \(run.alertsFired) alerts")
                    .font(BodyFont.system(size: 10.5, wght: 400))
                    .foregroundColor(.white.opacity(0.50))
            }
            Spacer()
            if let started = run.startedAt {
                Text(started.prefix(16))
                    .font(BodyFont.system(size: 10.5, wght: 400))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.03)))
    }
    private var statusColor: Color {
        switch run.status {
        case "running": return .orange
        case "succeeded": return .green
        case "failed", "timeout": return .red
        default: return .gray
        }
    }
}

struct SearchEditorSheet: View {
    @ObservedObject var manager: IndexManager
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var typeName: String = "product"
    @State private var promptTemplate: String = ""
    @State private var criteriaText: String = "{\n  \"vendor_includes\": []\n}"
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New search")
                .font(BodyFont.system(size: 17, wght: 700))
                .foregroundColor(.white)
            FormField(label: "Name") {
                TextField("", text: $name, prompt: Text("Leather shoes size 47").foregroundColor(.white.opacity(0.4)))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
                    .foregroundColor(.white)
            }
            FormField(label: "Target type") {
                Picker("", selection: $typeName) {
                    ForEach(IndexTypeCatalog.canonicalOrder, id: \.self) { name in
                        Text(IndexTypeCatalog.meta(for: name).displayName).tag(name)
                    }
                    ForEach(manager.types.filter { !$0.canonical }, id: \.id) { type in
                        Text(type.name.capitalized).tag(type.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            FormField(label: "Criteria (JSON)") {
                TextEditor(text: $criteriaText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 88)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
            }
            FormField(label: "Prompt template") {
                TextEditor(text: $promptTemplate)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 90)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
            }
            if let error {
                Text(error).font(BodyFont.system(size: 11.5, wght: 500)).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onDismiss).buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.7))
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Saving…" : "Save")
                        .font(BodyFont.system(size: 12.5, wght: 600))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(white: 0.135))
    }

    private func save() async {
        saving = true
        defer { saving = false }
        guard let data = criteriaText.data(using: .utf8) else {
            error = "Criteria is not valid UTF-8"
            return
        }
        let parsed: [String: AnyJSON]
        do {
            let raw = try JSONDecoder().decode(AnyJSON.self, from: data)
            guard case .object(let dict) = raw else {
                error = "Criteria must be a JSON object"
                return
            }
            parsed = dict
        } catch {
            self.error = "Criteria is not valid JSON: \(error.localizedDescription)"
            return
        }
        do {
            _ = try await manager.createSearch(
                name: name,
                type: typeName,
                criteria: parsed,
                prompt: promptTemplate.isEmpty ? nil : promptTemplate
            )
            onDismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(BodyFont.system(size: 10, wght: 600))
                .kerning(0.4)
                .foregroundColor(.white.opacity(0.5))
            content
        }
    }
}
