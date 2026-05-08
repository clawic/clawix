import SwiftUI

/// Modal popup used to add or edit a single `[mcp_servers.<name>]`
/// entry. Visually aligned with `ChatRenameSheet` (same chrome, same
/// button styles), but the body is a multi-section form because MCP
/// configs have notably more fields than a single string.
struct MCPEditorSheet: View {
    @ObservedObject var store: MCPServersStore
    /// The server we're editing. For "add new" callers pass a freshly
    /// constructed `MCPServerConfig`; the sheet owns its own working
    /// copy so cancelling discards changes.
    let initial: MCPServerConfig
    /// `true` when the entry already exists in the store. Drives the
    /// header title and the visibility of the Uninstall button.
    let isExisting: Bool
    let onClose: () -> Void

    @State private var draft: MCPServerConfig
    @State private var confirmingUninstall: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name }

    init(store: MCPServersStore,
         initial: MCPServerConfig,
         isExisting: Bool,
         onClose: @escaping () -> Void) {
        self.store = store
        self.initial = initial
        self.isExisting = isExisting
        self.onClose = onClose
        _draft = State(initialValue: initial)
    }

    private var canSave: Bool {
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        switch draft.transport {
        case .stdio:
            return !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .http:
            return !draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var headerTitle: LocalizedStringKey {
        isExisting ? "Update \(draft.displayName) MCP" : "Connect to a custom MCP"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isExisting {
                        Text("If you would like to switch MCP server type, please uninstall first.")
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.bottom, 2)
                    }

                    nameAndTransportCard
                    transportSpecificCards
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }
            .thinScrollers()
            .frame(maxHeight: 560)

            footer
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
        .frame(width: 560)
        .sheetStandardBackground()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if !isExisting { focusedField = .name }
            }
        }
        .alert("Uninstall this MCP server?",
               isPresented: $confirmingUninstall) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                store.delete(initial)
                onClose()
            }
        } message: {
            Text("It will be removed from ~/.codex/config.toml. Codex sessions started afterwards won't see it.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headerTitle)
                    .font(BodyFont.system(size: 20, weight: .medium))
                    .foregroundColor(Color(white: 0.97))
                Button {
                    if let url = URL(string: "https://github.com/openai/codex/blob/main/docs/mcp.md") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Docs")
                            .font(BodyFont.system(size: 12, wght: 500))
                        LucideIcon(.squareArrowOutUpRight, size: 10)
                    }
                    .foregroundColor(Palette.pastelBlue)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if isExisting {
                Button {
                    confirmingUninstall = true
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.trash2, size: 11)
                        Text("Uninstall")
                            .font(BodyFont.system(size: 12, wght: 600))
                    }
                    .foregroundColor(Color(red: 0.95, green: 0.42, blue: 0.42))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.95, green: 0.42, blue: 0.42).opacity(0.10))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color(red: 0.95, green: 0.42, blue: 0.42).opacity(0.40),
                                            lineWidth: 0.6)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                LucideIcon(.x, size: 12)
                    .foregroundColor(Color(white: 0.65))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Name + transport

    private var nameAndTransportCard: some View {
        MCPSheetCard {
            MCPSheetFieldLabel("Name")
            MCPSheetTextField(placeholder: "MCP server name",
                              text: $draft.name,
                              isDisabled: isExisting)
                .focused($focusedField, equals: .name)

            SlidingSegmented(
                selection: $draft.transport,
                options: [(MCPTransportKind.stdio, "STDIO"),
                          (MCPTransportKind.http,  "Streamable HTTP")],
                height: 34,
                fontSize: 12.5
            )
            .opacity(isExisting ? 0.55 : 1.0)
            .allowsHitTesting(!isExisting)
        }
    }

    // MARK: - Transport-specific

    @ViewBuilder
    private var transportSpecificCards: some View {
        switch draft.transport {
        case .stdio: stdioFields
        case .http:  httpFields
        }
    }

    private var stdioFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            MCPSheetCard {
                MCPSheetFieldLabel("Command to launch")
                MCPSheetTextField(placeholder: "openai-dev-mcp serve-sqlite",
                                  text: $draft.command)
            }

            MCPSheetCard {
                MCPSheetFieldLabel("Arguments")
                MCPSingleEntryList(entries: $draft.arguments,
                                   placeholder: "",
                                   addLabel: "Add argument")

                MCPSheetFieldLabel("Environment variables")
                    .padding(.top, 6)
                MCPKeyValueEntryList(entries: $draft.env,
                                     keyPlaceholder: "Key",
                                     valuePlaceholder: "Value",
                                     addLabel: "Add environment variable")

                MCPSheetFieldLabel("Environment variable passthrough")
                    .padding(.top, 6)
                MCPSingleEntryList(entries: $draft.envPassthrough,
                                   placeholder: "",
                                   addLabel: "Add variable")

                MCPSheetFieldLabel("Working directory")
                    .padding(.top, 6)
                MCPSheetTextField(placeholder: "~/code",
                                  text: $draft.workingDirectory)
            }
        }
    }

    private var httpFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            MCPSheetCard {
                MCPSheetFieldLabel("URL")
                MCPSheetTextField(placeholder: "https://mcp.example.com/mcp",
                                  text: $draft.url)
            }

            MCPSheetCard {
                MCPSheetFieldLabel("Bearer token env var")
                MCPSheetTextField(placeholder: "MCP_BEARER_TOKEN",
                                  text: $draft.bearerTokenEnvVar)
            }

            MCPSheetCard {
                MCPSheetFieldLabel("Headers")
                MCPKeyValueEntryList(entries: $draft.headers,
                                     keyPlaceholder: "Key",
                                     valuePlaceholder: "Value",
                                     addLabel: "Add header")
            }

            MCPSheetCard {
                MCPSheetFieldLabel("Headers from environment variables")
                MCPKeyValueEntryList(entries: $draft.headersFromEnv,
                                     keyPlaceholder: "Key",
                                     valuePlaceholder: "Value",
                                     addLabel: "Add variable")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let err = store.lastError {
                Text(err)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.45))
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SheetCancelButtonStyle())
            Button("Save") {
                store.upsert(draft)
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
            .buttonStyle(SheetPrimaryButtonStyle(enabled: canSave))
        }
    }
}

// MARK: - Sheet building blocks (private to the editor)

private struct MCPSheetCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}

private struct MCPSheetFieldLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 13, wght: 600))
            .foregroundColor(Palette.textPrimary)
    }
}

private struct MCPSheetTextField: View {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 13, wght: 500))
            .foregroundColor(isDisabled ? Palette.textSecondary : Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(isDisabled ? 0.20 : 0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .disabled(isDisabled)
    }
}

private struct MCPSingleEntryList: View {
    @Binding var entries: [MCPSingleEntry]
    let placeholder: String
    let addLabel: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($entries) { $entry in
                HStack(spacing: 10) {
                    MCPSheetTextField(placeholder: placeholder, text: $entry.value)
                    MCPSheetTrashButton {
                        entries.removeAll { $0.id == entry.id }
                    }
                }
            }
            MCPSheetAddRow(label: addLabel) {
                entries.append(MCPSingleEntry())
            }
        }
    }
}

private struct MCPKeyValueEntryList: View {
    @Binding var entries: [MCPKeyValueEntry]
    let keyPlaceholder: String
    let valuePlaceholder: String
    let addLabel: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($entries) { $entry in
                HStack(spacing: 10) {
                    MCPSheetTextField(placeholder: keyPlaceholder, text: $entry.key)
                    MCPSheetTextField(placeholder: valuePlaceholder, text: $entry.value)
                    MCPSheetTrashButton {
                        entries.removeAll { $0.id == entry.id }
                    }
                }
            }
            MCPSheetAddRow(label: addLabel) {
                entries.append(MCPKeyValueEntry())
            }
        }
    }
}

private struct MCPSheetAddRow: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIcon(.plus, size: 11)
                Text(label)
                    .font(BodyFont.system(size: 12.5))
            }
            .foregroundColor(Color(white: hovered ? 0.94 : 0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(hovered ? 0.36 : 0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct MCPSheetTrashButton: View {
    let action: () -> Void
    @State private var hovered: Bool = false

    var body: some View {
        Button(action: action) {
            LucideIcon(.trash2, size: 11)
                .foregroundColor(Color(white: hovered ? 0.94 : 0.55))
                .frame(width: 30, height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(hovered ? 0.06 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
