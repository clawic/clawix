import SwiftUI
import SecretsModels
import SecretsVault

/// Editor for the per-secret governance fields. Lives inside
/// `SecretDetailPane` as the "Permissions" tab. Edits a local copy of
/// the governance struct and pushes it back via
/// `SecretsStore.updateGovernance(secretId:to:)` on Save.
struct PermissionsTab: View {
    @EnvironmentObject private var vault: VaultManager
    let secret: SecretRecord
    let onChanged: () -> Void

    @State private var governance: Governance
    @State private var hostsCSV: String
    @State private var headersCSV: String
    @State private var allowedAgentsCSV: String
    @State private var ttlEnabled: Bool
    @State private var ttlDate: Date
    @State private var maxUsesText: String
    @State private var rotationDaysText: String
    @State private var clipboardClearText: String
    @State private var redactionLabel: String
    @State private var approvalWindowText: String
    @State private var error: String?
    @State private var saved: String?

    init(secret: SecretRecord, onChanged: @escaping () -> Void) {
        self.secret = secret
        self.onChanged = onChanged
        let g = secret.governance
        _governance = State(initialValue: g)
        _hostsCSV = State(initialValue: g.allowedHosts.joined(separator: ", "))
        _headersCSV = State(initialValue: g.allowedHeaders.joined(separator: ", "))
        _allowedAgentsCSV = State(initialValue: g.allowedAgents?.joined(separator: ", ") ?? "")
        _ttlEnabled = State(initialValue: g.ttlExpiresAt != nil)
        _ttlDate = State(initialValue: g.ttlExpiresAt.map { $0.asDate } ?? Date().addingTimeInterval(7 * 24 * 60 * 60))
        _maxUsesText = State(initialValue: g.maxUses.map(String.init) ?? "")
        _rotationDaysText = State(initialValue: g.rotationReminderDays.map(String.init) ?? "")
        _clipboardClearText = State(initialValue: String(g.clipboardClearSeconds))
        _redactionLabel = State(initialValue: g.redactionLabel ?? "")
        _approvalWindowText = State(initialValue: g.approvalWindowMinutes.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VaultCard {
                VStack(alignment: .leading, spacing: 12) {
                    section("Hosts and headers") {
                        labeledField("Allowed hosts", subtitle: "Comma-separated. `*.subdomain.com` allows wildcards on the leftmost label.") {
                            TextField("api.openai.com, *.github.com", text: $hostsCSV)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        labeledField("Allowed headers", subtitle: "Comma-separated. The proxy refuses if the request uses a header outside this list.") {
                            TextField("Authorization, X-API-Key", text: $headersCSV)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    Divider().background(Color.white.opacity(0.05))
                    section("Placement") {
                        toggle("Allow in URL query string", $governance.allowInUrl, detail: "Off by default. Tokens in URLs end up in server logs.")
                        toggle("Allow in request body", $governance.allowInBody)
                        toggle("Allow in environment variable", $governance.allowInEnv, detail: "Required for the `exec` subcommand to inject env vars.")
                        toggle("Allow plaintext http://", $governance.allowInsecureTransport, detail: "Only enable for dev / staging endpoints.")
                        toggle("Allow local-network targets", $governance.allowLocalNetwork, detail: "Allows 127.0.0.1, RFC1918 ranges, and *.local hosts.")
                    }
                    Divider().background(Color.white.opacity(0.05))
                    section("Lifecycle") {
                        labeledField("TTL expiry", subtitle: "Disable the secret automatically after this date.") {
                            HStack {
                                Toggle("Enabled", isOn: $ttlEnabled).labelsHidden()
                                if ttlEnabled {
                                    DatePicker("", selection: $ttlDate, displayedComponents: [.date])
                                        .labelsHidden()
                                }
                                Spacer()
                            }
                        }
                        labeledField("Maximum uses", subtitle: "Empty = unlimited.") {
                            TextField("e.g. 100", text: $maxUsesText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        labeledField("Rotation reminder", subtitle: "Days since last rotation before a notification fires. Empty disables.") {
                            TextField("e.g. 90", text: $rotationDaysText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }
                    Divider().background(Color.white.opacity(0.05))
                    section("Approval") {
                        labeledField("Approval mode", subtitle: nil) {
                            Picker("", selection: $governance.approvalMode) {
                                Text("Auto").tag(ApprovalMode.auto)
                                Text("Per use").tag(ApprovalMode.everyUse)
                                Text("Window").tag(ApprovalMode.window)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 280)
                        }
                        if governance.approvalMode == .window {
                            labeledField("Window length (minutes)", subtitle: "After a single approval, subsequent uses pass without prompting until this window elapses.") {
                                TextField("e.g. 10", text: $approvalWindowText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                        }
                        labeledField("Allowed agents", subtitle: "Comma-separated agent names. Empty = any agent allowed.") {
                            TextField("codex, claude-code", text: $allowedAgentsCSV)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    Divider().background(Color.white.opacity(0.05))
                    section("Output and UX") {
                        labeledField("Custom redaction label", subtitle: "Empty = `[REDACTED:internal_name]`. Useful when the agent expects a stable token like `[GH_TOKEN]`.") {
                            TextField("[GH_TOKEN]", text: $redactionLabel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        labeledField("Clipboard auto-clear (seconds)", subtitle: "0 disables auto-clear.") {
                            TextField("30", text: $clipboardClearText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                    }
                }
            }

            if let error { VaultErrorLine(text: error) }
            if let saved {
                Text(saved)
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Color.green.opacity(0.78))
            }
            HStack(spacing: 10) {
                Spacer()
                Button { save() } label: {
                    Text("Save permissions")
                        .font(BodyFont.system(size: 12, wght: 700))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.black.opacity(0.92))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func section<Inner: View>(_ title: String, @ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BodyFont.system(size: 11.5, wght: 700))
                .foregroundColor(Palette.textSecondary)
                .textCase(.uppercase)
            inner()
        }
    }

    @ViewBuilder
    private func labeledField<Field: View>(_ label: String, subtitle: String?, @ViewBuilder _ field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            field()
        }
    }

    @ViewBuilder
    private func toggle(_ label: String, _ value: Binding<Bool>, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: value).toggleStyle(.switch).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer()
        }
    }

    private func save() {
        guard let store = vault.store else { return }
        var newGovernance = governance
        newGovernance.allowedHosts = parseCSV(hostsCSV)
        newGovernance.allowedHeaders = parseCSV(headersCSV)
        let agents = parseCSV(allowedAgentsCSV)
        newGovernance.allowedAgents = agents.isEmpty ? nil : agents
        newGovernance.ttlExpiresAt = ttlEnabled ? Timestamp(ttlDate.timeIntervalSince1970 * 1000) : nil
        newGovernance.maxUses = Int(maxUsesText)
        newGovernance.rotationReminderDays = Int(rotationDaysText)
        newGovernance.clipboardClearSeconds = Int(clipboardClearText) ?? 30
        newGovernance.redactionLabel = redactionLabel.isEmpty ? nil : redactionLabel
        newGovernance.approvalWindowMinutes = newGovernance.approvalMode == .window ? Int(approvalWindowText) : nil

        do {
            _ = try store.updateGovernance(secretId: secret.id, to: newGovernance)
            vault.reload()
            saved = "Permissions saved at \(Date().formatted(date: .omitted, time: .shortened))"
            error = nil
            onChanged()
        } catch {
            self.error = String(describing: error)
            saved = nil
        }
    }

    private func parseCSV(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
