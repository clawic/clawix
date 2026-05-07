import SwiftUI

struct LocalModelsPage: View {

    @StateObject var service = LocalModelsService.shared

    @State var pullField: String = ""
    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            runtimeSection
                .padding(.top, 18)

            if case .running = service.daemonState {
                modelsSection
                    .padding(.top, 28)
            }

            diagnosticsSection
                .padding(.top, 28)
        }
        .onAppear { service.cancelInstall() /* clear stale state */ }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local models")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Run language models on your Mac. No cloud, no tokens.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Runtime section

    private var runtimeSection: some View {
        SectionCard(title: "Runtime") {
            VStack(alignment: .leading, spacing: 12) {
                runtimeStateRow

                if shouldShowDaemonToggle {
                    Divider().background(Color.white.opacity(0.07))
                    daemonToggleRow
                }

                if case .installed = service.runtimeState, !service.daemonState.isStarting {
                    Divider().background(Color.white.opacity(0.07))
                    HStack(spacing: 10) {
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
                try? LocalModelsRuntimeInstaller.shared.uninstall()
            }
        } message: {
            Text("Downloaded models stay on disk. You can reinstall the runtime any time.")
        }
    }

    @ViewBuilder
    private var runtimeStateRow: some View {
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
                    Text(progressLabel(downloaded: downloaded, total: LocalModelsRuntimeInstaller.pinnedSizeBytes))
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
                Image(systemName: "checkmark.circle.fill")
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

    private var shouldShowDaemonToggle: Bool {
        if case .installed = service.runtimeState { return true }
        return false
    }

    private var daemonToggleRow: some View {
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

    private var daemonStatusLabel: String {
        switch service.daemonState {
        case .stopped:        return "Stopped"
        case .starting:       return "Starting…"
        case .running:        return "Running on 127.0.0.1:\(LocalModelsDaemon.port) · \(service.loadedModels.count) loaded"
        case .missingRuntime: return "Runtime binary missing"
        case .crashed(let m): return m
        }
    }
}
