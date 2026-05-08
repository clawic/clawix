import SwiftUI
import LucideIcon

/// Settings page for the local LLM runtime. Single sidebar entry, with
/// the visible flow on top (install → daemon toggle → models) and a
/// collapsed `Advanced` disclosure at the bottom.
///
/// View extensions split across files:
/// - `LocalModelsModelsSection.swift` owns the Models card.
/// - `LocalModelsDiagnosticsSection.swift` owns shared row helpers and `SectionCard`.
/// - `LocalModelsAdvancedSection.swift` owns the collapsed Advanced bloc.
/// State and the published-binding wiring live here.
struct LocalModelsPage: View {

    @StateObject var service = LocalModelsService.shared
    @StateObject var launchAgent = LocalModelsLaunchAgent.shared

    @State var pullField: String = ""
    @State var showCatalog = false
    @State var showUninstallConfirm = false
    @State var advancedExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            runtimeSection
                .padding(.top, 18)

            if case .running = service.daemonState {
                modelsSection
                    .padding(.top, 22)
            }

            advancedSection
                .padding(.top, 22)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showCatalog) {
            LocalModelsCatalogSheet(
                installedModelNames: Set(service.installedModels.map { $0.name }),
                onPick: { name in
                    showCatalog = false
                    Task { await service.pull(model: name) }
                },
                onClose: { showCatalog = false }
            )
        }
        .onAppear {
            launchAgent.refresh()
            LocalModelsRuntimeInstaller.shared.refresh()
        }
    }

    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local models")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Run language models on your Mac. No cloud, no tokens.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Runtime card

    var runtimeSection: some View {
        SectionCard(title: "Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                runtimeStateRow

                if shouldShowDaemonControls {
                    Divider().background(Color.white.opacity(0.07))
                    daemonToggleRow
                    Divider().background(Color.white.opacity(0.07))
                    startAtLoginRow
                }

                if case .installed = service.runtimeState {
                    Divider().background(Color.white.opacity(0.07))
                    HStack {
                        Spacer()
                        Button("Uninstall runtime") {
                            showUninstallConfirm = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                        .font(BodyFont.system(size: 11.5, wght: 500))
                    }
                }
            }
        }
        .alert("Remove the local runtime?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                service.disable()
                launchAgent.disable()
                try? LocalModelsRuntimeInstaller.shared.uninstall()
            }
        } message: {
            Text("Downloaded models stay on disk. You can reinstall the runtime any time.")
        }
    }

    @ViewBuilder
    var runtimeStateRow: some View {
        switch service.runtimeState {
        case .notInstalled:
            actionRow(
                title: "Set up local runtime",
                detail: "Downloads ~133 MB the first time, then runs entirely on this Mac.",
                buttonLabel: "Set up",
                action: { Task { await service.enable() } }
            )
        case .installing(let progress, let downloaded):
            VStack(alignment: .leading, spacing: 6) {
                Text("Setting up local runtime…")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(progressLabel(
                        downloaded: downloaded,
                        total: LocalModelsRuntimeInstaller.pinnedSizeBytes
                    ))
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    Spacer()
                    Button("Cancel") { service.cancelInstall() }
                        .buttonStyle(.borderless)
                }
            }
        case .extracting:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Unpacking runtime…")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
            }
        case .installed(let v):
            HStack {
                Image(lucide: .circle_check)
                    .foregroundColor(Color(red: 0.40, green: 0.78, blue: 0.55))
                Text("Runtime ready · \(v)")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
            }
        case .updateAvailable(let installed):
            actionRow(
                title: "Update available",
                detail: "Installed \(installed). New: \(LocalModelsRuntimeInstaller.pinnedVersion).",
                buttonLabel: "Update",
                action: { Task { await service.enable() } }
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup failed")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                Text(message)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(4)
                Button("Retry") { Task { await service.enable() } }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var shouldShowDaemonControls: Bool {
        if case .installed = service.runtimeState { return true }
        return false
    }

    var daemonToggleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Run local runtime")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(daemonStatusLabel)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { service.daemonState.isRunning },
                set: { on in
                    Task {
                        if on { await service.enable() } else { service.disable() }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    var startAtLoginRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Start at login")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(launchAgent.statusLabel)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { launchAgent.isEnabled },
                set: { launchAgent.toggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    var daemonStatusLabel: String {
        switch service.daemonState {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting…"
        case .running:
            let loaded = service.loadedModels.count
            return loaded == 0
                ? "Running on 127.0.0.1:\(LocalModelsDaemon.port) · idle"
                : "Running on 127.0.0.1:\(LocalModelsDaemon.port) · \(loaded) loaded"
        case .missingRuntime:
            return "Runtime binary missing"
        case .crashed(let m):
            return m
        }
    }
}
