import SwiftUI

struct MCPPage: View {
    @StateObject private var store: MCPServersStore = .shared
    @State private var sheet: MCPSheetItem? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MCP servers")
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                (
                    Text("Connect external tools and data sources.")
                        .foregroundColor(Palette.textSecondary)
                    + Text(" ")
                    + Text("Learn more.")
                        .foregroundColor(Palette.pastelBlue)
                )
                .font(BodyFont.system(size: 12.5))
            }
            .padding(.bottom, 26)

            HStack {
                Text("Servers")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {
                    sheet = .init(
                        server: MCPServerConfig(),
                        isExisting: false
                    )
                } label: {
                    HStack(spacing: 5) {
                        LucideIcon(.plus, size: 11)
                        Text("Add server")
                            .font(BodyFont.system(size: 12, wght: 600))
                    }
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            if store.servers.isEmpty {
                MCPEmptyState(onAdd: {
                    sheet = .init(
                        server: MCPServerConfig(),
                        isExisting: false
                    )
                })
            } else {
                VStack(spacing: 7) {
                    ForEach(store.servers) { server in
                        MCPServerRow(
                            server: server,
                            isOn: Binding(
                                get: { server.enabled },
                                set: { store.toggleEnabled(server, isOn: $0) }
                            ),
                            onConfigure: {
                                sheet = .init(server: server, isExisting: true)
                            }
                        )
                    }
                }
            }

            if let err = store.lastError {
                Text(err)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.45))
                    .padding(.top, 12)
            }
        }
        .sheet(item: $sheet) { item in
            MCPEditorSheet(
                store: store,
                initial: item.server,
                isExisting: item.isExisting,
                onClose: { sheet = nil }
            )
        }
    }
}

struct MCPSheetItem: Identifiable {
    let id = UUID()
    let server: MCPServerConfig
    let isExisting: Bool
}

struct MCPServerRow: View {
    let server: MCPServerConfig
    @Binding var isOn: Bool
    let onConfigure: () -> Void

    @State private var configHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(transportSummary)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onConfigure) {
                SettingsIcon(size: 18)
                    .foregroundColor(Color(white: configHovered ? 0.94 : 0.62))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { configHovered = $0 }
            .hoverHint(L10n.t("Configure"))
            PillToggle(isOn: $isOn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private var transportSummary: String {
        switch server.transport {
        case .http:
            let u = server.url
            return u.isEmpty ? "Streamable HTTP" : "HTTP · \(u)"
        case .stdio:
            let c = server.command
            return c.isEmpty ? "STDIO" : "STDIO · \(c)"
        }
    }
}

struct MCPEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("No MCP servers connected yet.")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Button(action: onAdd) {
                HStack(spacing: 5) {
                    LucideIcon(.plus, size: 11)
                    Text("Add server")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.085))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
}
