import SwiftUI
import AppKit

/// Collapsed "Advanced" disclosure for the Local models page. Holds the
/// tuning knobs that most users never touch: context window, keep-alive,
/// storage location, hardware diagnostics. Hidden by default; `LocalModelsPage`
/// tracks the expanded/collapsed state via `advancedExpanded`.
extension LocalModelsPage {

    var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon.auto(advancedExpanded ? "chevron.down" : "chevron.right", size: 9)
                        .foregroundColor(Palette.textSecondary)
                    Text("Advanced")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    SectionCard(title: "Performance") {
                        VStack(alignment: .leading, spacing: 14) {
                            contextWindowRow
                            Divider().background(Color.white.opacity(0.07))
                            keepAliveRow
                        }
                    }
                    SectionCard(title: "Storage") {
                        VStack(alignment: .leading, spacing: 12) {
                            storageLocationRow
                            Divider().background(Color.white.opacity(0.07))
                            revealRow
                        }
                    }
                    SectionCard(title: "Diagnostics") {
                        VStack(alignment: .leading, spacing: 8) {
                            infoRow("Acceleration", accelerationLabel)
                            infoRow("Runtime version", service.runtimeVersion ?? "unknown")
                            infoRow("Loaded models", "\(service.loadedModels.count)")
                            infoRow("Endpoint", "http://127.0.0.1:\(LocalModelsDaemon.port)")
                            infoRow("Models folder", LocalModelsDaemon.modelsDirectory.path)
                            infoRow("Logs", LocalModelsDaemon.logFileURL.path)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    var contextWindowRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Context window")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Text("\(service.contextLength) tokens")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(service.contextLength) },
                    set: { service.contextLength = Int($0) }
                ),
                in: 1024...32768,
                step: 1024
            )
            Text("Bigger contexts use more memory and slow first-token latency. Applies on next runtime restart.")
                .font(BodyFont.system(size: 10.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    var keepAliveRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep model in memory")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("How long to keep a model loaded after the last request.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { service.keepAlive },
                set: { service.keepAlive = $0 }
            )) {
                Text("Immediate").tag("0")
                Text("5 minutes").tag("5m")
                Text("1 hour").tag("1h")
                Text("Until quit").tag("24h")
                Text("Forever").tag("-1")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)
        }
    }

    var storageLocationRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Models folder")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(LocalModelsDaemon.modelsDirectory.path)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(humanSize(totalModelsSize))
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .monospacedDigit()
        }
    }

    var revealRow: some View {
        HStack(alignment: .center) {
            Text("Reveal in Finder")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            Button("Open") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [LocalModelsDaemon.modelsDirectory]
                )
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 11.5, wght: 500))
        }
    }

    var accelerationLabel: String {
        #if arch(arm64)
        return "Metal · Apple Silicon"
        #else
        return "CPU"
        #endif
    }

    var totalModelsSize: Int64 {
        service.installedModels.reduce(0) { $0 + $1.size }
    }
}
