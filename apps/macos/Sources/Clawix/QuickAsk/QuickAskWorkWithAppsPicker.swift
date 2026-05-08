import SwiftUI
import AppKit

/// Popover that mirrors ChatGPT's "Work with Apps" picker (the macOS
/// Chat Bar feature where the user nominates an app to provide
/// context). Lists apps with `activationPolicy == .regular` that the
/// user is most likely to be working in. We don't actually read their
/// content yet (Accessibility integration is a Fase D follow-up); for
/// now picking an app stamps the bundle id on `controller.workWithBundleId`
/// and the controller prefixes "Working with: <AppName>" to the next
/// prompt so the agent knows the focal app.
struct QuickAskWorkWithAppsPicker: View {
    @ObservedObject var controller: QuickAskController
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var apps: [WorkAppEntry] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                LucideIcon(.search, size: 11)
                    .foregroundColor(.white.opacity(0.55))
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search")
                        .foregroundColor(.white.opacity(0.45))
                )
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white)
                .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .padding(8)

            Divider()
                .background(Color.white.opacity(0.10))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if controller.workWithBundleId != nil {
                        Button {
                            controller.workWithBundleId = nil
                            isPresented = false
                        } label: {
                            HStack(spacing: 8) {
                                LucideIcon(.circleX, size: 14)
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 18, height: 18)
                                Text("Stop working with app")
                                    .font(BodyFont.system(size: 12, wght: 600))
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().background(Color.white.opacity(0.08))
                    }
                    ForEach(filteredApps) { entry in
                        QuickAskWorkRow(
                            entry: entry,
                            isActive: entry.bundleId == controller.workWithBundleId
                        ) {
                            controller.workWithBundleId = entry.bundleId
                            isPresented = false
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 320)
        .background(VisualEffectBlur(material: .menu, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
        )
        .onAppear {
            apps = WorkAppEntry.snapshot()
            searchFocused = true
        }
    }

    private var filteredApps: [WorkAppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(q) }
    }
}

private struct QuickAskWorkRow: View {
    let entry: WorkAppEntry
    let isActive: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if let icon = entry.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                } else {
                    LucideIcon(.appWindow, size: 14)
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                }
                Text(entry.name)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                if !entry.isRunning {
                    Text("·  Not running")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                if isActive {
                    LucideIcon(.check, size: 11)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.white.opacity(hovered ? 0.06 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct WorkAppEntry: Identifiable {
    let id = UUID()
    let bundleId: String
    let name: String
    let icon: NSImage?
    let isRunning: Bool

    /// Inventory of apps to surface in the picker. For MVP: every
    /// running regular app, plus a curated list of editors / apps the
    /// "Work with Apps" feature in ChatGPT supports (so they show even
    /// when not currently running, matching the screenshots).
    static func snapshot() -> [WorkAppEntry] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        var byBundle: [String: WorkAppEntry] = [:]
        for app in running {
            guard let bid = app.bundleIdentifier else { continue }
            byBundle[bid] = WorkAppEntry(
                bundleId: bid,
                name: app.localizedName ?? bid,
                icon: app.icon,
                isRunning: true
            )
        }
        let curated = curatedTargets
        for target in curated where byBundle[target.bundleId] == nil {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                byBundle[target.bundleId] = WorkAppEntry(
                    bundleId: target.bundleId,
                    name: target.name,
                    icon: icon,
                    isRunning: false
                )
            }
        }
        // Stable order: running first, then curated, alphabetically.
        return byBundle.values.sorted { a, b in
            if a.isRunning != b.isRunning { return a.isRunning && !b.isRunning }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static let curatedTargets: [(bundleId: String, name: String)] = [
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("com.google.android.studio", "Android Studio"),
        ("com.apple.Terminal", "Terminal"),
        ("com.apple.Notes", "Notes"),
        ("com.apple.TextEdit", "TextEdit"),
        ("com.apple.ScriptEditor2", "Script Editor")
    ]
}
