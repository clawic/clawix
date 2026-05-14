import SwiftUI

/// Catalog of third-party connections (Telegram bot, Slack workspace,
/// etc.). The auth material (bot token, OAuth refresh token) is stored
/// in the encrypted Secrets vault; the editor here lets the user
/// paste/replace it. Agent-level routing happens via
/// `AgentIntegrationBinding` on the agent record.
struct ConnectionsHomeView: View {
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var editor: Connection?

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editor) { draft in
            ConnectionEditorSheet(initial: draft, isPresented: Binding(
                get: { editor != nil },
                set: { if !$0 { editor = nil } }
            )) { saved, secret in
                store.upsertConnection(saved)
                if let secret, !secret.isEmpty {
                    store.writeConnectionAuth(connectionId: saved.id, secret: secret)
                }
                editor = nil
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Connections")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(store.connections.count) connection\(store.connections.count == 1 ? "" : "s") · ~/.claw/connections/")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Menu {
                ForEach(ConnectionService.allCases) { service in
                    Button(service.label) {
                        editor = Connection.newDraft(service: service)
                    }
                }
            } label: {
                Label("New connection", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if store.connections.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "link.circle")
                    .font(BodyFont.system(size: 28, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                Text("No connections yet")
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Connections are auth handles (bot tokens, OAuth sessions). Agents bind to a connection's channels via Integrations.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Menu {
                    ForEach(ConnectionService.allCases) { service in
                        Button(service.label) {
                            editor = Connection.newDraft(service: service)
                        }
                    }
                } label: {
                    Label("Add your first connection", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.connections) { c in
                        Button {
                            appState.navigate(to: .connectionDetail(id: c.id))
                        } label: {
                            ConnectionRow(connection: c)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
        }
    }
}

private struct ConnectionRow: View {
    let connection: Connection
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.service.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.label)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(connection.service.label) · \(connection.id)")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            if let last = connection.lastSyncAt {
                Text("Synced \(last, style: .relative)")
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.04 : 0.025))
        )
        .onHover { hovered = $0 }
    }
}

// MARK: - Detail

struct ConnectionDetailView: View {
    let connectionId: String
    @EnvironmentObject private var store: AgentStore
    @EnvironmentObject private var appState: AppState
    @State private var showEditor: Bool = false
    @State private var deleteConfirm: Bool = false

    private var connection: Connection? { store.connection(id: connectionId) }

    var body: some View {
        if let connection {
            VStack(spacing: 0) {
                header(for: connection)
                CardDivider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BOUND AGENTS")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            let users = store.agents.filter { agent in
                                agent.integrationBindings.contains { $0.connectionId == connection.id }
                            }
                            if users.isEmpty {
                                Text("No agents bind to this connection yet.")
                                    .font(BodyFont.system(size: 12, wght: 500))
                                    .foregroundColor(Palette.textSecondary)
                            } else {
                                FlowChips(items: users.map(\.name))
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SCOPES")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            if connection.scopes.isEmpty {
                                Text("None declared.")
                                    .font(BodyFont.system(size: 12, wght: 500))
                                    .foregroundColor(Palette.textSecondary)
                            } else {
                                FlowChips(items: connection.scopes)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AUTH")
                                .font(BodyFont.system(size: 10.5, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                            let hasSecret = store.hasConnectionAuth(connectionId: connection.id)
                            HStack(spacing: 8) {
                                Image(systemName: hasSecret ? "lock.fill" : "lock.open")
                                    .foregroundColor(hasSecret ?
                                                     Color(red: 0.34, green: 0.78, blue: 0.55) :
                                                     Color(red: 1.0, green: 0.78, blue: 0.34))
                                Text(hasSecret ?
                                     "Encrypted token in Secrets." :
                                     "No token stored. Edit the connection to add one.")
                                    .font(BodyFont.system(size: 12, wght: 500))
                                    .foregroundColor(Palette.textPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .thinScrollers()
            }
            .sheet(isPresented: $showEditor) {
                ConnectionEditorSheet(initial: connection, isPresented: $showEditor) { saved, secret in
                    store.upsertConnection(saved)
                    if let secret, !secret.isEmpty {
                        store.writeConnectionAuth(connectionId: saved.id, secret: secret)
                    }
                    showEditor = false
                }
            }
            .alert("Delete \(connection.label)?",
                   isPresented: $deleteConfirm) {
                Button("Delete", role: .destructive) {
                    store.deleteConnection(id: connection.id)
                    appState.navigate(to: .connectionsHome)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the connection and unbinds every agent referencing it.")
            }
        } else {
            VStack(spacing: 10) {
                Text("Connection not found")
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                IconChipButton(symbol: "arrow.left", label: "Back") {
                    appState.navigate(to: .connectionsHome)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for c: Connection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.service.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(c.label)
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("\(c.service.label) · \(c.id)")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconChipButton(symbol: "pencil", label: "Edit") { showEditor = true }
            IconChipButton(symbol: "trash") { deleteConfirm = true }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}

// MARK: - Editor

struct ConnectionEditorSheet: View {
    let initial: Connection
    @Binding var isPresented: Bool
    /// `(savedConnection, secretMaterial?)` — the secret is nil when
    /// the user did not type a new token, so the caller keeps the
    /// existing vault credential untouched.
    let onSave: (Connection, String?) -> Void

    @State private var draft: Connection
    @State private var secretField: String = ""
    @State private var newScope: String = ""

    init(initial: Connection,
         isPresented: Binding<Bool>,
         onSave: @escaping (Connection, String?) -> Void) {
        self.initial = initial
        self._isPresented = isPresented
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(initial.createdAt == initial.updatedAt ? "New connection" : "Edit connection")
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                IconCircleButton(symbol: "xmark") { isPresented = false }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            CardDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Service") {
                        Picker("", selection: $draft.service) {
                            ForEach(ConnectionService.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    field("Label") {
                        TextField("My personal bot", text: $draft.label)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(fieldBg)
                    }
                    field(secretLabel) {
                        SecureField(secretPlaceholder, text: $secretField)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(fieldBg)
                        Text("Stored in encrypted Secrets. Replace anytime.")
                            .font(BodyFont.system(size: 10.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    field("Scopes") {
                        if draft.scopes.isEmpty {
                            Text("No scopes yet.")
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(Palette.textSecondary)
                        } else {
                            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                ForEach(draft.scopes, id: \.self) { scope in
                                    HStack(spacing: 4) {
                                        Text(scope)
                                            .font(BodyFont.system(size: 11, wght: 600))
                                            .foregroundColor(Palette.textPrimary)
                                        Button {
                                            draft.scopes.removeAll { $0 == scope }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(BodyFont.system(size: 9, wght: 600))
                                                .foregroundColor(Palette.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            TextField("scope", text: $newScope)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(fieldBg)
                                .onSubmit { commitScope() }
                            IconChipButton(symbol: "plus") { commitScope() }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .thinScrollers()
            CardDivider()
            HStack {
                Spacer()
                IconChipButton(symbol: "xmark", label: "Cancel") { isPresented = false }
                IconChipButton(symbol: "checkmark", label: "Save", isPrimary: true) {
                    onSave(draft, secretField.isEmpty ? nil : secretField)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 620, height: 580)
    }

    private var secretLabel: String {
        switch draft.service {
        case .telegram: return "Bot token"
        case .slack, .discord: return "OAuth token"
        case .email: return "App password"
        case .sms: return "API key"
        case .webhook: return "Signing secret"
        case .custom: return "Secret"
        }
    }

    private var secretPlaceholder: String {
        switch draft.service {
        case .telegram: return "1234567890:ABC…"
        case .slack: return "xoxb-…"
        case .discord: return "Bot …"
        case .email: return "app password"
        case .sms: return "API key"
        case .webhook: return "signing secret"
        case .custom: return "secret"
        }
    }

    private func commitScope() {
        let value = newScope.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !draft.scopes.contains(value) else { return }
        draft.scopes.append(value)
        newScope = ""
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
            content()
        }
    }

    private var fieldBg: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }
}
