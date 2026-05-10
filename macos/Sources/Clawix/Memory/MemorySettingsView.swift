import SwiftUI
import AppKit

/// Settings panel for the Memory tab. Hosts the Codex injection card,
/// a doctor block, and a couple of utility links (data folder, daemon
/// graph view).
struct MemorySettingsView: View {

    @ObservedObject var manager: MemoryManager
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CardDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MemoryCodexInjectionCard()
                        .padding(.bottom, 4)
                    doctorCard
                    utilitiesCard
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Memory settings")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var doctorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Doctor")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { Task { await manager.runDoctor() } }) {
                    Text("Refresh")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            doctorRow(label: "Notes", value: manager.doctor?.notes.map { String($0) } ?? "—")
            doctorRow(label: "Captures pending", value: manager.doctor?.captures.map { String($0) } ?? "—")
            doctorRow(label: "Index valid", value: manager.doctor?.valid.map { $0 ? "yes" : "no" } ?? "—")
            doctorRow(label: "Workspace", value: manager.doctor?.workspace ?? "—", monospaced: true)
            if let warnings = manager.doctor?.warnings, !warnings.isEmpty {
                Text("Warnings:")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(.yellow.opacity(0.85))
                    .padding(.top, 4)
                ForEach(warnings, id: \.self) { warning in
                    Text("· " + warning)
                        .font(BodyFont.system(size: 11, wght: 400))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .task {
            if manager.doctor == nil { await manager.runDoctor() }
        }
    }

    private func doctorRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(monospaced
                      ? BodyFont.system(size: 11.5, design: .monospaced)
                      : BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var utilitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Utilities")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(.white)
            Button(action: openDataFolder) {
                Text("Reveal data folder in Finder")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            Button(action: openGraphView) {
                Text("Open graph view in browser")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            Text("The Memory daemon serves a D3 force-directed graph view at http://127.0.0.1:7791/. The macOS app keeps the simpler list browser; the graph stays one click away when you want it.")
                .font(BodyFont.system(size: 11, wght: 400))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func openDataFolder() {
        let folder = ClawJSServiceManager.workspaceURL
            .appendingPathComponent(".clawjs", isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func openGraphView() {
        if let url = URL(string: "http://127.0.0.1:\(ClawJSService.memory.port)/") {
            NSWorkspace.shared.open(url)
        }
    }
}
