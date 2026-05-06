import SwiftUI

/// Floating recording pill rendered inside `DictationOverlay`'s panel.
/// Two phases: while recording shows a live waveform; while
/// transcribing shows a "Transcribing" label with three pulsing dots.
struct DictationOverlayView: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Group {
            if coordinator.state == .idle {
                EmptyView()
            } else {
                pill
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: coordinator.state)
    }

    private var pill: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))

                content
                    .frame(maxWidth: .infinity)

                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.78))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 10)

            Text("Press Esc to cancel")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .recording:
            OverlayWaveform(levels: coordinator.levels)
                .frame(height: 22)
        case .transcribing:
            VStack(spacing: 4) {
                Text("Transcribing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                TranscribingDots()
                    .frame(height: 6)
            }
        case .idle:
            EmptyView()
        }
    }
}

/// Compact bar-style waveform tuned for the floating pill: short, fewer
/// bars, fixed gap between them. Uses the same level buffer the
/// `DictationCoordinator` publishes for the composer waveform.
private struct OverlayWaveform: View {
    let levels: [CGFloat]
    private let barCount = 14

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .frame(width: 3, height: barHeight(at: i, in: proxy.size.height))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func barHeight(at index: Int, in maxHeight: CGFloat) -> CGFloat {
        guard !levels.isEmpty else { return 4 }
        let stride = max(1, levels.count / barCount)
        let lookup = min(levels.count - 1, index * stride)
        let level = levels[lookup]
        let amplified = max(0.12, min(1.0, level * 1.6))
        return max(4, amplified * maxHeight)
    }
}

private struct TranscribingDots: View {
    @State private var phase: Int = 0
    let dotCount = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(opacity(at: i)))
                    .frame(width: 4, height: 4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { timer in
                Task { @MainActor in
                    phase = (phase + 1) % dotCount
                }
                _ = timer
            }
        }
    }

    private func opacity(at index: Int) -> Double {
        let distance = abs(index - phase)
        return distance == 0 ? 1.0 : (distance == 1 ? 0.55 : 0.25)
    }
}
