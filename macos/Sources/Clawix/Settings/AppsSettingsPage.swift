import AppKit
import SwiftUI

/// Settings page for the Apps surface. Mirrors the master/detail look
/// of the other settings pages: master toggle on top, then an inline
/// table listing every installed app with size + permissions and
/// per-row actions (open, pin, delete, toggle internet access).
struct AppsSettingsPage: View {
    @ObservedObject private var appsStore: AppsStore = .shared
    @EnvironmentObject var appState: AppState

    @AppStorage(ClawixPersistentSurfaceKeys.appsFeatureEnabled, store: SidebarPrefs.store)
    private var appsFeatureEnabled: Bool = true
    @AppStorage(ClawixPersistentSurfaceKeys.appsDefaultInternetAllowed, store: SidebarPrefs.store)
    private var defaultInternetAllowed: Bool = false
    @AppStorage(ClawixPersistentSurfaceKeys.appsDefaultCallAgent, store: SidebarPrefs.store)
    private var defaultCallAgent: Bool = true

    @State private var pendingDelete: AppRecord?

    private var totalSizeBytes: Int {
        appsStore.apps.reduce(0) { partial, record in
            partial + appSizeOnDisk(record)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $appsFeatureEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Apps")
                            .font(BodyFont.system(size: 14, wght: 600))
                        Text("Show the Apps section in the sidebar and let the agent create new ones.")
                            .font(BodyFont.system(size: 12.5, wght: 400))
                            .foregroundColor(Color(white: 0.6))
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(16)
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 0) {
                tableHeader
                Divider().opacity(0.18)
                if appsStore.apps.isEmpty {
                    emptyTable
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appsStore.sortedApps) { record in
                            AppsSettingsRow(
                                record: record,
                                onOpen: { appState.currentRoute = .app(record.id) },
                                onTogglePin: { appsStore.togglePinned(record) },
                                onToggleInternet: { toggleInternet(record) },
                                onDelete: { pendingDelete = record },
                                sizeOnDisk: appSizeOnDisk(record)
                            )
                            Divider().opacity(0.10)
                        }
                    }
                }
            }
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 12) {
                Text("Defaults for new apps")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Color(white: 0.85))
                Toggle(isOn: $defaultInternetAllowed) {
                    Text("Internet access")
                        .font(BodyFont.system(size: 13, wght: 500))
                }
                .toggleStyle(.switch)
                Toggle(isOn: $defaultCallAgent) {
                    Text("Allow apps to send messages to the agent")
                        .font(BodyFont.system(size: 13, wght: 500))
                }
                .toggleStyle(.switch)
            }
            .padding(16)
            .background(cardBackground)

            HStack {
                Text("Storage used: \(formatBytes(totalSizeBytes))")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Button("Open Apps folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppsStore.defaultRootURL()])
                }
                .buttonStyle(.link)
            }
        }
        .alert(item: $pendingDelete) { record in
            Alert(
                title: Text("Delete \"\(record.name)\"?"),
                message: Text("The app folder will be removed from disk. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    try? appsStore.delete(record)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps")
                .font(BodyFont.system(size: 20, wght: 700))
                .foregroundColor(Palette.textPrimary)
            Text("Mini web apps your agent has built. They live under \(AppsStore.defaultRootURL().path) and you can sync that folder with anything that knows about file paths.")
                .font(BodyFont.system(size: 13, wght: 400))
                .foregroundColor(Color(white: 0.62))
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Project")
                .frame(width: 130, alignment: .leading)
            Text("Last opened")
                .frame(width: 130, alignment: .leading)
            Text("Size")
                .frame(width: 80, alignment: .trailing)
            Text("Net")
                .frame(width: 50, alignment: .center)
            Text("")
                .frame(width: 96)
        }
        .font(BodyFont.system(size: 11.5, wght: 600))
        .foregroundColor(Color(white: 0.5))
        .textCase(.uppercase)
        .tracking(0.4)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyTable: some View {
        HStack {
            Spacer()
            Text("No apps yet")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.55))
            Spacer()
        }
        .padding(.vertical, 32)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
            )
    }

    private func toggleInternet(_ record: AppRecord) {
        var updated = record
        if !updated.permissions.internet {
            // Going from offline → online: ask the user explicitly. We
            // already gate by file path so a JSON edit on disk would
            // not trigger this dialog, but the Settings UI funnel
            // should always pause.
            AppPermissionPrompt.shared.requestInternetApproval(appName: record.name) { allowed in
                guard allowed else { return }
                var copy = record
                copy.permissions.internet = true
                try? appsStore.update(copy)
            }
            return
        }
        updated.permissions.internet = false
        try? appsStore.update(updated)
    }

    private func appSizeOnDisk(_ record: AppRecord) -> Int {
        let dir = appsStore.directory(forSlug: record.slug)
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += size
            }
        }
        return total
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct AppsSettingsRow: View {
    let record: AppRecord
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onToggleInternet: () -> Void
    let onDelete: () -> Void
    let sizeOnDisk: Int

    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(record.icon.isEmpty ? "🪟" : record.icon)
                    .font(.system(size: 16))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(BodyFont.system(size: 13.5, wght: 600))
                        .foregroundColor(Color(white: 0.92))
                        .lineLimit(1)
                    Text(record.slug)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Color(white: 0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(projectName)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.62))
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(lastOpenedText)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.62))
                .frame(width: 130, alignment: .leading)

            Text(formatBytes(sizeOnDisk))
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.62))
                .frame(width: 80, alignment: .trailing)

            Button(action: onToggleInternet) {
                Image(systemName: record.permissions.internet ? "globe" : "globe.badge.chevron.backward")
                    .foregroundColor(record.permissions.internet ? .green.opacity(0.8) : Color(white: 0.4))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 50, alignment: .center)
            .help(record.permissions.internet ? "Internet access enabled. Click to revoke." : "Offline. Click to allow internet.")

            HStack(spacing: 4) {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open")

                Button(action: onTogglePin) {
                    Image(systemName: record.pinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help(record.pinned ? "Unpin" : "Pin")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
                .foregroundColor(.red.opacity(0.8))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(white: 0.7))
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var projectName: String {
        guard let pid = record.projectId,
              let project = appState.projects.first(where: { $0.id == pid }) else {
            return "—"
        }
        return project.name
    }

    private var lastOpenedText: String {
        guard let date = record.lastOpenedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
