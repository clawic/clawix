import SwiftUI

struct ConfigurationPage: View {
    @EnvironmentObject var appState: AppState
    @State private var depsEnabled: Bool = true
    @State private var configScope: String = "User settings"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Settings",
                subtitle: "Configure the approval policy and sandbox settings. Learn more"
            )

            Text("Custom config.toml settings")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            DeprecationBanner()
                .padding(.bottom, 14)

            HStack {
                SettingsDropdown(
                    options: [
                        ("User settings", "User settings"),
                        ("Project settings", "Project settings")
                    ],
                    selection: $configScope,
                    minWidth: 230
                )
                Spacer()
                Button {
                    Task {
                        await SettingsUtilities.openConfigToml(scope: configScope, selectedProject: appState.selectedProject)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Open config.toml")
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        LucideIcon(.arrowUpRight, size: 10)
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            .liftWhenSettingsDropdownOpen()

            SectionLabel(title: "Permissions")
            SettingsCard {
                PermissionToggleRow(
                    mode: .defaultPermissions,
                    title: "Default permissions",
                    detail: "By default, Clawix can read and edit files in your workspace. It can request additional access when needed."
                )
                CardDivider()
                PermissionToggleRow(
                    mode: .autoReview,
                    title: "Automatic review",
                    detail: "Clawix can read and edit files in your workspace. Clawix automatically reviews requests for additional access. Auto-review may make mistakes. Learn more about the elevated risks."
                )
                CardDivider()
                PermissionToggleRow(
                    mode: .fullAccess,
                    title: "Full access",
                    detail: "When Clawix runs with full access, it can edit any file on your computer and run commands over the network without your authorization. This significantly increases the risk of data loss, leaks, or unexpected behavior. Learn more about the elevated risks."
                )
            }

            SectionLabel(title: "Workspace dependencies")
            SettingsCard {
                HStack {
                    Text("Current version")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Text(AppVersion.displayString)
                        .font(BodyFont.system(size: 12, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                CardDivider()
                ToggleRow(
                    title: "Clawix dependencies",
                    detail: "Allow Clawix to install and expose the bundled Node.js and Python tools",
                    isOn: $depsEnabled
                )
                CardDivider()
                ActionPillRow(
                    title: "Diagnose Clawix Workspace issues",
                    detail: "Check the current bundle and save diagnostic logs",
                    primaryLabel: "Diagnose",
                    onPrimary: { SettingsUtilities.revealDiagnosticsFolder() }
                )
                CardDivider()
                ReinstallRow()
            }
        }
    }
}

struct PermissionToggleRow: View {
    @EnvironmentObject var appState: AppState
    let mode: PermissionMode
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        let binding = Binding<Bool>(
            get: { appState.permissionMode == mode },
            set: { newValue in
                guard newValue else { return }
                appState.permissionMode = mode
            }
        )
        ToggleRow(title: title, detail: detail, isOn: binding)
    }
}

struct DeprecationBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(.circleAlert, size: 13)
                .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.30))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    InlineCode("[features].collab")
                    Text(" is deprecated. Use ")
                        .foregroundColor(Color(white: 0.85))
                    InlineCode("[features].multi_agent")
                    Text(" instead.")
                        .foregroundColor(Color(white: 0.85))
                }
                .font(BodyFont.system(size: 12, wght: 500))
                HStack(spacing: 0) {
                    Text("Enable it with ").foregroundColor(Color(white: 0.75))
                    InlineCode("--enable multi_agent")
                    Text(" or ").foregroundColor(Color(white: 0.75))
                    InlineCode("[features].multi_agent")
                    Text(" in config.toml. See").foregroundColor(Color(white: 0.75))
                }
                .font(BodyFont.system(size: 11.5, wght: 500))
                HStack(spacing: 4) {
                    LucideIcon(.globe, size: 11)
                        .foregroundColor(Palette.pastelBlue)
                    Text("Toggle developer-only surfaces by editing the configuration file.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.pastelBlue)
                    Text("for details.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Color(white: 0.75))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.18, green: 0.10, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(red: 0.55, green: 0.30, blue: 0.10), lineWidth: 0.7)
                )
        )
    }
}

struct InlineCode: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11.5, design: .monospaced))
            .foregroundColor(Color(white: 0.95))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

struct ReinstallRow: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reset and install workspace")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Removes the local package, fetches it fresh, and reloads the tools")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
