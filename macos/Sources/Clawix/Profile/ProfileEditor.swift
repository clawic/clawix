import SwiftUI

struct ProfileEditor: View {
    @ObservedObject var manager: ProfileManager
    @State private var selectedTab: Tab = .identity
    @State private var mnemonicShown: String?
    @State private var actionError: String?

    enum Tab: String, CaseIterable {
        case identity, handle, groups, blocks, audience, custom, recovery

        var label: String {
            switch self {
            case .identity: return "Identity"
            case .handle: return "Handle"
            case .groups: return "Groups"
            case .blocks: return "Blocks"
            case .audience: return "Audience"
            case .custom: return "Custom verticals"
            case .recovery: return "Recovery"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            tabs
            Divider().background(Color.white.opacity(0.06))
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .task { await manager.bootstrap() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Profile").font(.system(size: 18, weight: .semibold)).kerning(-0.4)
            if let me = manager.me {
                Text("@\(me.handle.alias).\(me.handle.fingerprint)")
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                let isSelected = tab == selectedTab
                Button(action: { selectedTab = tab }) {
                    Text(tab.label).font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .kerning(-0.2)
                        .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.07) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .identity: identityTab
        case .handle: handleTab
        case .groups: groupsTab
        case .blocks: blocksTab
        case .audience: audienceTab
        case .custom: customVerticalsTab
        case .recovery: recoveryTab
        }
    }

    // MARK: - Identity

    @State private var newAlias: String = ""

    private var identityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let me = manager.me {
                    InfoRow(label: "Alias", value: "@" + me.handle.alias)
                    InfoRow(label: "Fingerprint", value: me.handle.fingerprint)
                    InfoRow(label: "Root pubkey", value: me.handle.rootPubkey, monospace: true)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No profile yet").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        HStack(spacing: 8) {
                            TextField("Choose an alias (a-z, 0-9, _)", text: $newAlias)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                            Button("Generate profile") {
                                Task {
                                    await runAction {
                                        let response = try await manager.initProfile(alias: newAlias, mnemonic: nil)
                                        mnemonicShown = response.mnemonic
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if let actionError {
                    Text(actionError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                if let mnemonic = mnemonicShown {
                    MnemonicCard(mnemonic: mnemonic)
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    // MARK: - Handle

    private var handleTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename handle").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
                HStack(spacing: 8) {
                    TextField("New alias", text: $newAlias)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    Button("Apply") {
                        Task {
                            await runAction {
                                try await manager.renameHandle(to: newAlias)
                            }
                        }
                    }
                        .buttonStyle(.borderedProminent)
                }
                if let actionError {
                    Text(actionError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                Text("Your fingerprint stays the same. Anyone who paired with you keeps the binding regardless of alias.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            }
            .padding(18)
        }
        .thinScrollers()
    }

    // MARK: - Groups

    @State private var newGroupId: String = ""

    private var groupsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("custom-<slug>", text: $newGroupId)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    Button("Create group") {
                        Task {
                            await runAction {
                                try await manager.createGroup(id: newGroupId)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let actionError {
                    Text(actionError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                ForEach(manager.groups) { g in
                    GroupRow(group: g)
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    // MARK: - Blocks

    private var blocksTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(manager.ownBlocks) { block in
                    BlockRow(block: block, onDelete: {
                        Task {
                            await runAction {
                                try await manager.deleteBlock(block.blockId)
                            }
                        }
                    })
                }
                if let actionError {
                    Text(actionError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                if manager.ownBlocks.isEmpty {
                    Text("No blocks yet.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    // MARK: - Audience

    private var audienceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Audience tiers").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
                ForEach(["public", "audience", "friends", "family", "inner-circle"], id: \.self) { tier in
                    Text("· " + tier).font(.system(size: 12.5))
                }
                Text("Each block declares which tiers can see each field. Capabilities can grant access without adding the peer to a tier.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            }
            .padding(18)
        }
        .thinScrollers()
    }

    // MARK: - Custom verticals

    private var customVerticalsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom verticals").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
                Text("Declare a vertical with a JSON schema. The daemon validates content and feeds the discoveryKey.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            }
            .padding(18)
        }
        .thinScrollers()
    }

    // MARK: - Recovery

    private var recoveryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery phrase").font(.system(size: 13, weight: .semibold)).kerning(-0.2)
                Text("Your recovery phrase is shown when the identity is created. Keep it offline; Clawix does not reveal it again from the running profile.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                if let mnemonic = mnemonicShown {
                    MnemonicCard(mnemonic: mnemonic)
                } else {
                    Text("To restore this identity on another device, use the recovery phrase saved during creation.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(18)
        }
        .thinScrollers()
    }

    @MainActor
    private func runAction(_ action: @escaping () async throws -> Void) async {
        actionError = nil
        do {
            try await action()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var monospace: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: monospace ? .monospaced : .default))
                .textSelection(.enabled)
            Spacer()
        }
    }
}

private struct MnemonicCard: View {
    let mnemonic: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Write this down").font(.system(size: 12, weight: .semibold)).kerning(-0.2)
            Text(mnemonic).font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
    }
}

private struct GroupRow: View {
    let group: ClawJSProfileClient.Group

    var body: some View {
        HStack {
            Text(group.label ?? group.id).font(.system(size: 13, weight: .medium)).kerning(-0.2)
            Text("\(group.members.count) members").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct BlockRow: View {
    let block: ClawJSProfileClient.Block
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.vertical).font(.system(size: 12.5, weight: .medium)).kerning(-0.2)
                Text(block.blockId).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button(action: onDelete) {
                LucideIcon(.trash, size: 13).foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
