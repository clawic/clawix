import SwiftUI

/// Settings page for the mp/1.0.0 multi-key identity. Mirrors the
/// terminology rules in the protocol spec: never expose the words
/// "RootKey", "DeviceKey", "RoleKey" or "mnemonic" in the default copy.
struct IdentitySettingsPage: View {
    @StateObject private var manager = MarketplaceManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                rootSection
                devicesSection
                rolesSection
                recoverySection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .thinScrollers()
        .task {
            if manager.state == .idle {
                await manager.refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                LucideIcon.auto("user", size: 18)
                    .foregroundColor(.white.opacity(0.90))
                Text("Identity")
                    .font(BodyFont.system(size: 17, wght: 600))
                    .foregroundColor(.white)
            }
            Text("Your protocol identity, the devices you trust, and the roles you publish under.")
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private var rootSection: some View {
        Section(title: "Your identity") {
            if manager.roots.isEmpty {
                EmptyRow(
                    icon: "key",
                    title: "No identity yet",
                    description: "Create your identity to publish offers, search, and sign matches. Backed by a recovery phrase you keep offline."
                )
            } else {
                ForEach(manager.roots) { root in
                    IdentityCard(
                        title: root.label ?? "Default",
                        subtitle: short(root.pubkey),
                        meta: "Created " + root.createdAt.prefix(10)
                    )
                }
            }
        }
    }

    private var devicesSection: some View {
        Section(title: "Trusted devices") {
            if manager.devices.isEmpty {
                EmptyRow(
                    icon: "monitor",
                    title: "No devices yet",
                    description: "The Mac you are using is automatically registered as a device when you create your identity."
                )
            } else {
                ForEach(manager.devices) { device in
                    IdentityCard(
                        title: device.deviceName,
                        subtitle: short(device.pubkey),
                        meta: device.revokedAt == nil ? "Active" : "Revoked"
                    )
                }
            }
        }
    }

    private var rolesSection: some View {
        Section(title: "Your roles") {
            if manager.roles.isEmpty {
                EmptyRow(
                    icon: "tag",
                    title: "No roles yet",
                    description: "Create a role per area where you want to publish: real-estate seller, freelancer, dating, etc. Roles do not share reputation by default."
                )
            } else {
                ForEach(manager.roles) { role in
                    IdentityCard(
                        title: role.roleName,
                        subtitle: role.vertical,
                        meta: short(role.pubkey)
                    )
                }
            }
        }
    }

    private var recoverySection: some View {
        Section(title: "Recovery") {
            EmptyRow(
                icon: "shield",
                title: "Recovery phrase",
                description: "Your recovery phrase restores your identity on another Mac, iPhone or Android device. Keep it offline."
            )
        }
    }

    private func short(_ value: String) -> String {
        String(value.prefix(20)) + "…"
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(.white.opacity(0.50))
                .textCase(nil)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IdentityCard: View {
    let title: String
    let subtitle: String
    let meta: String
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(.white.opacity(0.90))
                Text(subtitle)
                    .font(BodyFont.system(size: 11.5, wght: 400))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text(meta)
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(.white.opacity(0.50))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct EmptyRow: View {
    let icon: String
    let title: String
    let description: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon.auto(icon, size: 14)
                .foregroundColor(.white.opacity(0.45))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(.white.opacity(0.78))
                Text(description)
                    .font(BodyFont.system(size: 11.5, wght: 400))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}
