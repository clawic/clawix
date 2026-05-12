import SwiftUI

struct RunsTabView: View {
    @ObservedObject var manager: IndexManager
    @State private var selectedRunId: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                CardDivider()
                list
            }
            .frame(maxWidth: .infinity)
            CardDivider()
            RunDetailPane(manager: manager, runId: selectedRunId)
                .frame(width: 380)
                .background(Color.black.opacity(0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text("\(manager.runs.count) runs")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var list: some View {
        Group {
            if manager.runs.isEmpty {
                IndexEmptyState(
                    title: "No runs yet",
                    systemImage: "play.circle",
                    description: "Each Search Run or Monitor fire creates a row here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.runs) { run in
                            RunRow(
                                run: run,
                                monitorName: manager.monitors.first { $0.id == run.monitorId }?.name,
                                searchName: manager.searches.first { $0.id == run.searchId }?.name,
                                isSelected: selectedRunId == run.id,
                                onSelect: { selectedRunId = run.id }
                            )
                            CardDivider()
                        }
                    }
                }
                .thinScrollers()
            }
        }
    }
}

private struct RunRow: View {
    let run: ClawJSIndexClient.Run
    let monitorName: String?
    let searchName: String?
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                StatusBadge(status: run.status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitorName ?? searchName ?? "Manual run")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(.white.opacity(0.92))
                    HStack(spacing: 8) {
                        Text("\(run.entitiesSeen) entities · \(run.observationsCount) observations")
                            .font(BodyFont.system(size: 11, wght: 400))
                            .foregroundColor(.white.opacity(0.55))
                        if run.alertsFired > 0 {
                            Text("· \(run.alertsFired) alerts")
                                .font(BodyFont.system(size: 11, wght: 600))
                                .foregroundColor(.orange)
                        }
                    }
                }
                Spacer()
                if let started = run.startedAt {
                    Text(started.prefix(16))
                        .font(BodyFont.system(size: 10.5, wght: 400))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isSelected ? Color.white.opacity(0.06) : (hovered ? Color.white.opacity(0.03) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.capitalized)
            .font(BodyFont.system(size: 10.5, wght: 700))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                Capsule(style: .continuous).fill(color.opacity(0.7))
            )
    }
    private var color: Color {
        switch status {
        case "running": return .orange
        case "succeeded": return .green
        case "failed", "timeout": return .red
        case "cancelled": return .gray
        default: return .blue
        }
    }
}

private struct RunDetailPane: View {
    @ObservedObject var manager: IndexManager
    let runId: String?

    @State private var detail: ClawJSIndexClient.RunDetail?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Run details")
                            .font(BodyFont.system(size: 13, wght: 700))
                            .foregroundColor(.white)
                        Text("Status \(detail.run.status)")
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(.white.opacity(0.85))
                        if let prompt = detail.run.prompt {
                            Text("Prompt")
                                .font(BodyFont.system(size: 10.5, wght: 700))
                                .kerning(0.5)
                                .foregroundColor(.white.opacity(0.5))
                            Text(prompt)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.30)))
                        }
                        if let error = detail.run.error {
                            Text("Error")
                                .font(BodyFont.system(size: 10.5, wght: 700))
                                .kerning(0.5)
                                .foregroundColor(.white.opacity(0.5))
                            Text(error)
                                .font(BodyFont.system(size: 11.5, wght: 500))
                                .foregroundColor(.red.opacity(0.9))
                        }
                        Text("Entities captured (\(detail.entities.count))")
                            .font(BodyFont.system(size: 10.5, wght: 700))
                            .kerning(0.5)
                            .foregroundColor(.white.opacity(0.5))
                        ForEach(detail.entities) { entity in
                            HStack(spacing: 8) {
                                LucideIcon.auto(IndexTypeCatalog.meta(for: entity.typeName).lucideName, size: 12)
                                    .foregroundColor(IndexTypeCatalog.meta(for: entity.typeName).accent)
                                Text(entity.title ?? entity.identityKey)
                                    .font(BodyFont.system(size: 12, wght: 500))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.03)))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .thinScrollers()
            } else if let loadError {
                IndexEmptyState(
                    title: "Could not load run",
                    systemImage: "exclamationmark.triangle",
                    description: loadError
                )
            } else if runId != nil {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Text("Select a run.")
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(.white.opacity(0.40))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: runId) {
            detail = nil
            loadError = nil
            guard let runId else { return }
            manager.ensureToken()
            do {
                detail = try await ClawJSIndexClient(bearerToken: ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)).getRun(id: runId)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
