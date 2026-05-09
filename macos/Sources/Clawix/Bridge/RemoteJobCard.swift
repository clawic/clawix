import SwiftUI
import ClawixCore

// In-chat status card for an outbound remote-mesh job. Shows the
// destination Mac, the workspace path the job is pinned to, the
// queued/running/completed/failed/cancelled status, the streamed event
// log, and (when the job ends) the final result text. A separate
// banner reads the daemon's `workspaceDenied` error and turns it into
// a clear next step (open Settings → Machines on the remote Mac).
struct RemoteJobCard: View {

    let state: RemoteJobUIState
    var onDismiss: () -> Void = {}

    @State private var eventsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if isWorkspaceDeniedError {
                InfoBanner(
                    text: "Workspace denied. Add \(state.workspacePath) to \(state.peerDisplayName)’s allowed workspaces, or pick a different folder.",
                    kind: .error
                )
            } else if let error = state.errorMessage, state.status == .failed {
                InfoBanner(text: error, kind: .error)
            } else if let transient = state.transientError {
                InfoBanner(text: transient, kind: .danger)
            }

            if !state.events.isEmpty {
                eventsBlock
            }

            if !state.resultText.isEmpty {
                resultBlock
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(state.peerDisplayName)
                        .font(BodyFont.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    statusPill
                }
                Text(state.workspacePath)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("RemoteJobCard.workspacePath")
            }
            Spacer()
            if state.isTerminal {
                Button(action: onDismiss) {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var statusPill: some View {
        Text(state.statusLabel)
            .font(BodyFont.system(size: 10, weight: .semibold))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(
                Capsule(style: .continuous).fill(statusColor.opacity(0.55))
            )
    }

    private var statusColor: Color {
        switch state.status {
        case .queued:    return Color(red: 0.55, green: 0.65, blue: 0.85)
        case .running:   return Color(red: 0.30, green: 0.65, blue: 1.0)
        case .completed: return Color(red: 0.30, green: 0.78, blue: 0.45)
        case .failed:    return Color(red: 0.85, green: 0.35, blue: 0.30)
        case .cancelled: return Color(white: 0.50)
        }
    }

    // MARK: - Events

    private var eventsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    eventsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(eventsExpanded ? .chevronDown : .chevronRight, size: 9)
                    Text("Events (\(state.events.count))")
                        .font(BodyFont.system(size: 11.5, weight: .medium))
                    Spacer()
                }
                .foregroundColor(Palette.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RemoteJobCard.eventsToggle")

            if eventsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.events, id: \.id) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.type)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(Palette.textSecondary)
                                .frame(width: 70, alignment: .leading)
                            Text(event.message)
                                .font(BodyFont.system(size: 11.5))
                                .foregroundColor(Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Result

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LucideIcon(.messageCircle, size: 11)
                Text("Result")
                    .font(BodyFont.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(Palette.textSecondary)

            Text(state.resultText)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var isWorkspaceDeniedError: Bool {
        guard let message = state.errorMessage else { return false }
        let lowered = message.lowercased()
        return lowered.contains("workspace") && lowered.contains("denied")
    }
}
