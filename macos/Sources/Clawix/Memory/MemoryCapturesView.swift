import SwiftUI

/// Captures section: lists pending capture entries from the daemon and
/// lets the user promote them to durable memories one click at a time.
struct MemoryCapturesView: View {

    @ObservedObject var manager: MemoryManager
    let onClose: () -> Void
    @State private var promotingId: String? = nil
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CardDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if pendingCaptures.isEmpty {
                        Text("No pending captures.")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.top, 30)
                            .padding(.horizontal, 12)
                    }
                    ForEach(pendingCaptures) { capture in
                        captureCard(capture: capture, isPromoted: false)
                    }
                    if !promotedCaptures.isEmpty {
                        Text("Promoted")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(.white.opacity(0.5))
                            .textCase(.uppercase)
                            .padding(.top, 10)
                        ForEach(promotedCaptures) { capture in
                            captureCard(capture: capture, isPromoted: true, dimmed: true)
                        }
                    }
                }
                .padding(16)
            }
            if let errorText {
                Text(errorText)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(8)
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
            Text("\(pendingCaptures.count) pending")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var pendingCaptures: [ClawJSMemoryClient.Capture] {
        manager.captures.filter { $0.promotedAt == nil }
    }

    private var promotedCaptures: [ClawJSMemoryClient.Capture] {
        manager.captures.filter { $0.promotedAt != nil }
    }

    private func captureCard(capture: ClawJSMemoryClient.Capture, isPromoted: Bool, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(capture.sessionId ?? "session")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(.white.opacity(0.85))
                if let captured = capture.capturedAt {
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text(String(captured.prefix(19)).replacingOccurrences(of: "T", with: " "))
                        .font(BodyFont.system(size: 11, wght: 400))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                if !isPromoted {
                    Button(action: { promote(capture) }) {
                        Text(promotingId == capture.id ? "Promoting…" : "Promote")
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(promotingId == capture.id ? 0.5 : 0.95))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(promotingId == capture.id)
                } else {
                    Text("promoted")
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(.green.opacity(0.85))
                }
            }
            if let user = capture.user, !user.isEmpty {
                excerpt(label: "User", text: user)
            }
            if let assistant = capture.assistant, !assistant.isEmpty {
                excerpt(label: "Assistant", text: assistant)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(dimmed ? 0.02 : 0.05))
        )
        .opacity(dimmed ? 0.7 : 1)
        .id("\(capture.id)-\(capture.promotedAt ?? "pending")")
    }

    private func excerpt(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(.white.opacity(0.45))
                .textCase(.uppercase)
            Text(text)
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(3)
        }
    }

    private func promote(_ capture: ClawJSMemoryClient.Capture) {
        promotingId = capture.id
        errorText = nil
        Task {
            do {
                _ = try await manager.promote(captureId: capture.id)
                await MainActor.run {
                    promotingId = nil
                }
            } catch {
                await MainActor.run {
                    promotingId = nil
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
