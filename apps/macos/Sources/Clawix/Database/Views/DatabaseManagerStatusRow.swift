import SwiftUI

/// Status row added to the ClawJS Settings page when the database
/// service is `.ready`. Shows namespace + collections count + last
/// realtime event timestamp + a button to retry bootstrap.
struct DatabaseManagerStatusRow: View {
    @EnvironmentObject private var manager: DatabaseManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(label: "Namespace") {
                Text(manager.currentNamespace)
                    .font(BodyFont.system(size: 12.5, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .monospaced()
            }
            row(label: "Collections") {
                Text("\(manager.collections.count)")
                    .font(BodyFont.system(size: 12.5, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .monospacedDigit()
            }
            row(label: "Realtime") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.realtime.isConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(manager.realtime.isConnected ? "Connected" : "Reconnecting…")
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(Palette.textSecondary)
                    if let last = manager.lastEventAt {
                        Text("· last event \(last.formatted(.relative(presentation: .numeric)))")
                            .font(BodyFont.system(size: 11.5))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
            }
            HStack {
                Button("Re-bootstrap") {
                    Task { await manager.bootstrap() }
                }
                .buttonStyle(.borderless)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                if case .bootstrapping = manager.state {
                    ProgressView().controlSize(.small)
                }
                if case .failed(let reason) = manager.state {
                    Text(reason)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func row<Trailing: View>(label: String, @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 90, alignment: .leading)
            trailing()
            Spacer()
        }
    }
}
