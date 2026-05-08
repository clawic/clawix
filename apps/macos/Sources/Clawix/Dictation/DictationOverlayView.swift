import SwiftUI

/// Compact recording pill rendered inside the floating overlay panel.
/// Layout intentionally matches the reference dictation UI: a 184×40
/// black capsule with three slots — mic glyph (left), animated audio
/// visualizer / transcribing indicator (center), stop button (right).
///
/// State surface comes from `DictationCoordinator`:
///   - `.recording`     → animated waveform + active red stop button
///   - `.transcribing`  → "Transcribing" label with sequential dots,
///                        stop button collapses to a spinner
///   - `.idle`          → not rendered (overlay panel is hidden)
struct DictationOverlayView: View {
    @ObservedObject var coordinator: DictationCoordinator

    private let pillWidth: CGFloat = 184
    private let pillHeight: CGFloat = 40
    private let pillCorner: CGFloat = 20

    var body: some View {
        VStack(spacing: 10) {
            if coordinator.escHintVisible {
                DictationEscToast(
                    duration: 1.5,
                    onClose: { coordinator.dismissEscHint() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let errorMessage = coordinator.errorToastMessage {
                DictationErrorToast(
                    message: errorMessage,
                    onClose: { coordinator.dismissErrorToast() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            // Live preview (#19) — only meaningful when the active
            // backend streams partials (Apple Speech). Whisper local
            // leaves `partialTranscript` empty so this never shows.
            if shouldShowLivePreview {
                DictationLivePreview(text: coordinator.partialTranscript)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if coordinator.state != .idle {
                pill
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.22), value: coordinator.state)
        .animation(.easeInOut(duration: 0.22), value: coordinator.escHintVisible)
        .animation(.easeInOut(duration: 0.22), value: coordinator.errorToastMessage)
        .animation(.easeInOut(duration: 0.18), value: coordinator.partialTranscript)
    }

    private var shouldShowLivePreview: Bool {
        guard coordinator.state == .recording else { return false }
        guard !coordinator.partialTranscript.isEmpty else { return false }
        return UserDefaults.standard.object(
            forKey: DictationCoordinator.livePreviewEnabledKey
        ) as? Bool ?? true
    }

    private var pill: some View {
        HStack(spacing: 0) {
            DictationMicSlot(state: coordinator.state)
                .frame(width: 22)
                .padding(.leading, 12)

            Spacer(minLength: 0)

            DictationStatusDisplay(
                state: coordinator.state,
                levels: coordinator.levels
            )

            Spacer(minLength: 0)

            DictationStopButton(state: coordinator.state) {
                handleTrailingTap()
            }
            .frame(width: 22)
            .padding(.trailing, 12)
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(
            RoundedRectangle(cornerRadius: pillCorner, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            // Hairline border bumped from 0.06 to 0.18 so the pill
            // separates from dark wallpapers without the heavy drop
            // shadow the previous version painted around it (the
            // "glass" halo the user complained about).
            RoundedRectangle(cornerRadius: pillCorner, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: pillCorner, style: .continuous))
    }

    private func handleTrailingTap() {
        switch coordinator.state {
        case .recording:
            coordinator.stop()
        case .transcribing:
            coordinator.cancel()
        case .idle:
            break
        }
    }
}

// MARK: - Esc confirmation toast

/// Toast that appears above the pill on the first Esc press, prompting
/// the user to press Esc again within `duration` seconds to actually
/// cancel the recording. The blue progress bar at the bottom drains in
/// lockstep with the coordinator's auto-clear timer so the visual
/// state and the underlying timer never disagree.
private struct DictationEscToast: View {
    let duration: TimeInterval
    let onClose: () -> Void

    @State private var progress: Double = 1.0
    @State private var timer: Timer?

    private let accent = Color(red: 0.16, green: 0.46, blue: 0.98)
    private let corner: CGFloat = 10

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)

            Text("Press ESC again to cancel recording")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 6)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(width: 296, height: 40)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            // Progress bar in its own clipped overlay so the toast's
            // border stroke isn't clipped along with it. The VStack +
            // Spacer push the bar to the bottom edge of the rounded
            // rectangle.
            VStack(spacing: 0) {
                Spacer()
                GeometryReader { proxy in
                    Rectangle()
                        .fill(accent)
                        .frame(width: proxy.size.width * max(0, progress), height: 2)
                }
                .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .onAppear { startTimer() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startTimer() {
        let interval: TimeInterval = 0.05
        let totalSteps = max(1, duration / interval)
        let dec = 1.0 / totalSteps
        progress = 1.0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            Task { @MainActor in
                if progress > 0 {
                    progress = max(0, progress - dec)
                } else {
                    t.invalidate()
                }
            }
        }
    }
}

// MARK: - Error toast

/// Toast that surfaces a transcription / lifecycle error so the user
/// knows *why* a press produced no text. Used when the active Whisper
/// model isn't on disk, mic permission flips off mid-session, the
/// cloud provider returns an error, or any other path that leaves
/// `processed` empty + `lastError` set. Auto-dismisses after the
/// coordinator's window; the `x` shortcuts that.
private struct DictationErrorToast: View {
    let message: String
    let onClose: () -> Void

    private let accent = Color(red: 0.92, green: 0.32, blue: 0.32)
    private let corner: CGFloat = 10

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 6)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 296)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - Mic slot

private struct DictationMicSlot: View {
    let state: DictationCoordinator.State

    var body: some View {
        MicIcon(lineWidth: 0)
            .frame(width: 17, height: 17)
            .foregroundStyle(.white.opacity(opacity))
            .animation(.easeInOut(duration: 0.18), value: state)
    }

    private var opacity: Double {
        switch state {
        case .recording:    return 1.0
        case .transcribing: return 0.55
        case .idle:         return 0.55
        }
    }
}

// MARK: - Status display (waveform / transcribing dots)

private struct DictationStatusDisplay: View {
    let state: DictationCoordinator.State
    let levels: [CGFloat]

    var body: some View {
        Group {
            switch state {
            case .recording:
                DictationAudioVisualizer(levels: levels, isActive: true)
                    .transition(.opacity)
            case .transcribing:
                DictationProcessingIndicator()
                    .transition(.opacity)
            case .idle:
                DictationStaticBars()
                    .transition(.opacity)
            }
        }
        .frame(height: 28)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}

// MARK: - Audio visualizer

/// 15-bar capsule visualizer driven by a TimelineView so each bar's
/// height is recomputed at ~60 fps from a sine-wave + amplitude product.
/// Each bar carries a phase offset, and bars near the centre get a
/// subtle taller boost — same recipe the reference UI uses to feel
/// alive even when speech amplitude is low.
private struct DictationAudioVisualizer: View {
    let levels: [CGFloat]
    let isActive: Bool

    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 26

    private let phases: [Double]

    init(levels: [CGFloat], isActive: Bool) {
        self.levels = levels
        self.isActive = isActive
        self.phases = (0..<barCount).map { Double($0) * 0.4 }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { context in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: barWidth, height: barHeight(for: index, at: context.date))
                }
            }
        }
        .frame(height: maxHeight)
    }

    private func barHeight(for index: Int, at date: Date) -> CGFloat {
        guard isActive else { return minHeight }
        let level = Double(levels.last ?? 0)
        let amplitude = max(0, min(1, pow(level, 0.7)))
        let time = date.timeIntervalSince1970
        let wave = sin(time * 8 + phases[index]) * 0.5 + 0.5
        let centerDistance = abs(Double(index) - Double(barCount) / 2) / Double(barCount / 2)
        let centerBoost = 1.0 - (centerDistance * 0.4)
        return max(minHeight, minHeight + CGFloat(amplitude * wave * centerBoost) * (maxHeight - minHeight))
    }
}

private struct DictationStaticBars: View {
    private let barCount = 15
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: barWidth, height: 4)
            }
        }
    }
}

// MARK: - Transcribing indicator

private struct DictationProcessingIndicator: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Transcribing")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            DictationDots()
        }
    }
}

private struct DictationDots: View {
    @State private var currentDot: Int = -1
    @State private var timer: Timer?

    private let dotCount = 5
    private let dotSize: CGFloat = 3
    private let dotSpacing: CGFloat = 2.5
    private let stepInterval: TimeInterval = 0.18

    var body: some View {
        HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: dotSize / 2, style: .continuous)
                    .fill(Color.white.opacity(index <= currentDot ? 0.85 : 0.25))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .frame(height: 6)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        currentDot = 0
        timer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { _ in
            Task { @MainActor in
                currentDot = (currentDot + 1) % (dotCount + 2)
                if currentDot > dotCount { currentDot = -1 }
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Stop button

/// Right-slot button. Tap stops a recording or cancels a transcription.
/// Disabled while in the brief idle transition so the user can't
/// double-tap and re-arm a stale session.
private struct DictationStopButton: View {
    let state: DictationCoordinator.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .recording {
                    Circle()
                        .fill(Color(red: 0.92, green: 0.26, blue: 0.26))
                        .frame(width: 22, height: 22)
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
                inner
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .idle)
        .animation(.easeInOut(duration: 0.18), value: state)
    }

    @ViewBuilder
    private var inner: some View {
        switch state {
        case .recording:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.white)
                .frame(width: 8, height: 8)
        case .transcribing:
            DictationSpinner()
                .frame(width: 14, height: 14)
        case .idle:
            EmptyView()
        }
    }
}

/// Two-ring spinner matching `SidebarChatRowSpinner`: a static track
/// plus a rotating arc, both stroked at 1.7pt with the same slow 2.4s
/// rotation so transcription progress reads as quiet, not urgent.
private struct DictationSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.32),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .trim(from: 0.0, to: 0.76)
                .stroke(Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Live preview pill

/// Glass pill that floats above the recording capsule and renders the
/// streaming partial transcript while the user is still speaking
/// (#19). Apple Speech publishes refinements every ~150 ms; the
/// `.animation(value:)` on the parent VStack interpolates the text
/// fade so successive partials don't flash.
private struct DictationLivePreview: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 12, wght: 600))
            .foregroundColor(Color.white.opacity(0.92))
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 340)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            )
    }
}
