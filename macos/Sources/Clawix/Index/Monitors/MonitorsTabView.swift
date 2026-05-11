import SwiftUI

struct MonitorsTabView: View {
    @ObservedObject var manager: IndexManager
    @State private var selectedMonitorId: String?
    @State private var showCreateSheet = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                CardDivider()
                list
            }
            .frame(maxWidth: .infinity)
            CardDivider()
            MonitorDetailPane(manager: manager, monitorId: selectedMonitorId)
                .frame(width: 380)
                .background(Color.black.opacity(0.14))
        }
        .sheet(isPresented: $showCreateSheet) {
            MonitorEditorSheet(manager: manager, onDismiss: { showCreateSheet = false })
        }
    }

    private var header: some View {
        HStack {
            Text("\(manager.monitors.count) monitors")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Button(action: { showCreateSheet = true }) {
                HStack(spacing: 6) {
                    LucideIcon.auto("plus", size: 11)
                    Text("New monitor")
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

    private var list: some View {
        Group {
            if manager.monitors.isEmpty {
                ContentUnavailableView(
                    "No monitors yet",
                    systemImage: "clock.arrow.2.circlepath",
                    description: Text("Promote any saved Search into a recurring Monitor with cron + alert rules.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.monitors) { monitor in
                            MonitorRow(
                                monitor: monitor,
                                searchName: manager.searches.first { $0.id == monitor.searchId }?.name ?? monitor.searchId,
                                isSelected: selectedMonitorId == monitor.id,
                                onSelect: { selectedMonitorId = monitor.id },
                                onFire: { Task { _ = try? await manager.fireMonitor(id: monitor.id) } }
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

private struct MonitorRow: View {
    let monitor: ClawJSIndexClient.Monitor
    let searchName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onFire: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(monitor.enabled ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.name ?? searchName)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(.white.opacity(0.92))
                    HStack(spacing: 8) {
                        Text(monitor.cronHuman ?? monitor.cronExpr)
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(.white.opacity(0.65))
                        if let next = monitor.nextFireAt {
                            Text("· next \(next.prefix(16))")
                                .font(BodyFont.system(size: 11, wght: 400))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                }
                Spacer()
                Button(action: onFire) {
                    HStack(spacing: 4) {
                        LucideIcon.auto("play", size: 10)
                        Text("Fire now")
                    }
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.10)))
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

private struct MonitorDetailPane: View {
    @ObservedObject var manager: IndexManager
    let monitorId: String?

    private var monitor: ClawJSIndexClient.Monitor? {
        guard let id = monitorId else { return nil }
        return manager.monitors.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let monitor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(text: "Schedule")
                        Text(monitor.cronHuman ?? monitor.cronExpr)
                            .font(BodyFont.system(size: 13, wght: 500))
                            .foregroundColor(.white.opacity(0.85))
                        if let next = monitor.nextFireAt {
                            Text("Next fire \(next)")
                                .font(BodyFont.system(size: 11, wght: 400))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        SectionTitle(text: "Alert rules")
                        if monitor.alertRules.isEmpty {
                            Text("No rules defined.")
                                .font(BodyFont.system(size: 12, wght: 400))
                                .foregroundColor(.white.opacity(0.45))
                        } else {
                            ForEach(Array(monitor.alertRules.enumerated()), id: \.offset) { _, rule in
                                AlertRuleRow(rule: rule)
                            }
                        }
                        SectionTitle(text: "Recent runs")
                        let runs = manager.runs.filter { $0.monitorId == monitor.id }
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
                Text("Select a monitor.")
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

private struct AlertRuleRow: View {
    let rule: ClawJSIndexClient.AlertRule
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(humanRule)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white.opacity(0.85))
            Text(rule.id)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
    }
    private var humanRule: String {
        switch rule.when {
        case "field_decrease":
            let pct = rule.thresholdPct.map { String(format: "≥%.0f%%", $0) } ?? "any"
            return "When `\(rule.field ?? "?")` drops \(pct)"
        case "field_increase":
            let pct = rule.thresholdPct.map { String(format: "≥%.0f%%", $0) } ?? "any"
            return "When `\(rule.field ?? "?")` rises \(pct)"
        case "new_entity":
            return "When a new entity is captured"
        case "rating_drop":
            return "When `rating` drops"
        case "field_match":
            return "When `\(rule.field ?? "?")` matches a value"
        case "absence":
            return "When `\(rule.field ?? "?")` is missing"
        default:
            return rule.when
        }
    }
}

private struct MonitorEditorSheet: View {
    @ObservedObject var manager: IndexManager
    let onDismiss: () -> Void

    @State private var searchId: String = ""
    @State private var name: String = ""
    @State private var cron: String = "0 9 * * *"
    @State private var alertRulesJSON: String = """
[
  {
    "id": "price-drop-10pct",
    "when": "field_decrease",
    "field": "price",
    "thresholdPct": 10
  }
]
"""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New monitor")
                .font(BodyFont.system(size: 17, wght: 700))
                .foregroundColor(.white)
            FormField(label: "Source search") {
                Picker("", selection: $searchId) {
                    Text("Pick a saved search").tag("")
                    ForEach(manager.searches) { search in
                        Text(search.name).tag(search.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            FormField(label: "Name (optional)") {
                TextField("", text: $name, prompt: Text("Daily wishlist price tracker").foregroundColor(.white.opacity(0.4)))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
                    .foregroundColor(.white)
            }
            FormField(label: "Cron expression") {
                TextField("", text: $cron, prompt: Text("0 9 * * *").foregroundColor(.white.opacity(0.4)))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .font(.system(size: 12, design: .monospaced))
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
                    .foregroundColor(.white)
            }
            FormField(label: "Alert rules (JSON array)") {
                TextEditor(text: $alertRulesJSON)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 120)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
            }
            if let error {
                Text(error).font(BodyFont.system(size: 11.5, wght: 500)).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onDismiss).buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
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
                .disabled(saving || searchId.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color(white: 0.135))
    }

    private func save() async {
        saving = true
        defer { saving = false }
        guard let data = alertRulesJSON.data(using: .utf8) else {
            error = "Alert rules JSON is not valid UTF-8"
            return
        }
        let rules: [ClawJSIndexClient.AlertRule]
        do {
            rules = try JSONDecoder().decode([ClawJSIndexClient.AlertRule].self, from: data)
        } catch {
            self.error = "Alert rules JSON invalid: \(error.localizedDescription)"
            return
        }
        do {
            _ = try await manager.createMonitor(
                searchId: searchId,
                cron: cron,
                name: name.isEmpty ? nil : name,
                alertRules: rules
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
