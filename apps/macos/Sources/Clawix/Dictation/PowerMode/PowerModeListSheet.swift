import SwiftUI

struct PowerModeListSheet: View {
    @ObservedObject var manager: PowerModeManager
    @Binding var isPresented: Bool
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            content
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            footer
        }
        .frame(width: 760, height: 540)
        .background(Color(white: 0.10))
        .onAppear {
            if selection == nil {
                selection = manager.configs.first?.id
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Power Mode profiles")
                .font(BodyFont.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            Button {
                let id = manager.addBlank()
                selection = id
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color(white: 0.165)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var content: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(manager.configs) { config in
                        PowerModeListRow(
                            config: config,
                            selected: selection == config.id,
                            isActive: manager.activeConfig?.id == config.id
                        ) {
                            selection = config.id
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 16)
                    }
                }
            }
            .frame(width: 220)

            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 0.5)

            if let id = selection, let binding = bindingFor(id: id) {
                PowerModeEditor(
                    config: binding,
                    onDelete: {
                        selection = manager.configs.first { $0.id != id }?.id
                        manager.delete(id)
                    }
                )
            } else {
                VStack {
                    Spacer()
                    Text("Pick a profile from the list, or create a new one.")
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to presets") {
                manager.resetToPresets()
                selection = manager.configs.first?.id
            }
            Spacer()
            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func bindingFor(id: UUID) -> Binding<PowerModeConfig>? {
        guard let idx = manager.configs.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { manager.configs[idx] },
            set: { manager.update($0) }
        )
    }
}

private struct PowerModeListRow: View {
    let config: PowerModeConfig
    let selected: Bool
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(config.emoji.isEmpty ? "✨" : config.emoji)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    badges
                    Text(triggers)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if !config.enabled {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Rectangle().fill(selected ? Color.white.opacity(0.06) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var badges: some View {
        HStack(spacing: 6) {
            Text(config.name)
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
            if config.isDefault {
                PowerModeBadge(label: "DEFAULT", color: Color(white: 0.30))
            }
            if isActive {
                PowerModeBadge(label: "ACTIVE", color: Color(red: 0.16, green: 0.46, blue: 0.98))
            }
        }
    }

    private var triggers: String {
        var parts: [String] = []
        if !config.triggerBundleIds.isEmpty {
            parts.append("\(config.triggerBundleIds.count) app\(config.triggerBundleIds.count == 1 ? "" : "s")")
        }
        if !config.triggerURLHosts.isEmpty {
            parts.append("\(config.triggerURLHosts.count) URL\(config.triggerURLHosts.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "no triggers yet" : parts.joined(separator: " · ")
    }
}

private struct PowerModeBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(BodyFont.system(size: 9, wght: 700))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule(style: .continuous).fill(color))
    }
}
