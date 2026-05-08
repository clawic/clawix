import SwiftUI
import LucideIcon

// Recording UI shown over the bottom of the chat while the user is
// dictating a prompt or capturing an audio message. Two purposes:
//
//   .transcribeToText  (mic button)   -> stop runs the transcription
//                                        animation and drops the
//                                        recognised text back into the
//                                        composer for editing; send
//                                        does the same but submits the
//                                        prompt automatically once the
//                                        text lands.
//   .sendAsAudio       (voice button) -> send button ships the clip as
//                                        an audio attachment; stop
//                                        pauses the take so the user
//                                        can resume it before deciding
//                                        to send or cancel.
//
// The overlay itself is dumb. It owns the visual phase
// (recording/paused/transcribing) but delegates "what does each button
// mean" to the host via the action closures, so the mode-specific
// behaviour lives next to the rest of the chat send pipeline.
struct RecordingOverlay: View {
    enum Purpose: Equatable {
        case transcribeToText
        case sendAsAudio
    }

    enum Phase: Equatable {
        case recording
        case paused
        case transcribing
    }

    let purpose: Purpose
    let phase: Phase
    var levels: [CGFloat] = []
    let onCancel: () -> Void
    let onStop: () -> Void
    let onResume: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            cancelButton
            HStack(alignment: .center, spacing: 8) {
                primaryControlBubble
                mainPill
            }
        }
        .padding(.horizontal, 14)
    }

    private var cancelButton: some View {
        Button(action: triggerCancel) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Circle())
                Image(lucide: .x)
                    .font(BodyFont.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel recording")
    }

    // Stop / resume bubble. Sits next to the waveform pill as its own
    // glass circle, mirroring the `+` attachments button on the
    // composer — the waveform pill stays focused on the level meter and
    // the send affordance, the destructive control lives outside it.
    @ViewBuilder
    private var primaryControlBubble: some View {
        switch phase {
        case .recording:
            stopBubble
        case .paused:
            resumeBubble
        case .transcribing:
            disabledStopBubble
        }
    }

    private var stopBubble: some View {
        Button(action: triggerStop) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Circle())
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
    }

    private var resumeBubble: some View {
        Button(action: triggerResume) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Circle())
                Image(lucide: .play)
                    .font(BodyFont.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .offset(x: 1)
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume recording")
    }

    // Non-interactive placeholder during transcription so the bubble
    // keeps its slot next to the pill instead of collapsing the layout
    // when the take ends.
    private var disabledStopBubble: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.tint(Color.black.opacity(0.30)), in: Circle())
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(white: 0.55))
                .frame(width: 14, height: 14)
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mainPill: some View {
        switch phase {
        case .recording, .paused:
            recordingPill
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        case .transcribing:
            transcribingPill
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private var recordingPill: some View {
        HStack(spacing: 8) {
            RecordingWaveform(isActive: phase == .recording, levels: levels)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .padding(.horizontal, 4)
            sendCircle(enabled: true, action: triggerSend)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Capsule(style: .continuous))
    }

    private var transcribingPill: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.white.opacity(0.75))
                .scaleEffect(0.9)
            Text("Transcribing")
                .font(Typography.bodyFont)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
            sendCircle(enabled: false, action: {})
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Capsule(style: .continuous))
    }

    private func sendCircle(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(lucide: .arrow_up)
                .font(BodyFont.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Color.black : Color(white: 0.35))
                .frame(width: 38, height: 38)
                .background(Circle().fill(enabled ? Color.white : Color(white: 0.55)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(enabled ? "Send" : "Send (transcribing)")
    }

    private func triggerCancel() {
        Haptics.tap()
        onCancel()
    }

    private func triggerStop() {
        Haptics.tap()
        onStop()
    }

    private func triggerResume() {
        Haptics.tap()
        onResume()
    }

    private func triggerSend() {
        Haptics.send()
        onSend()
    }
}

#Preview("Recording, mic") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            RecordingOverlay(
                purpose: .transcribeToText,
                phase: .recording,
                onCancel: {},
                onStop: {},
                onResume: {},
                onSend: {}
            )
            .padding(.bottom, 12)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Paused, voice") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            RecordingOverlay(
                purpose: .sendAsAudio,
                phase: .paused,
                onCancel: {},
                onStop: {},
                onResume: {},
                onSend: {}
            )
            .padding(.bottom, 12)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Transcribing") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            RecordingOverlay(
                purpose: .transcribeToText,
                phase: .transcribing,
                onCancel: {},
                onStop: {},
                onResume: {},
                onSend: {}
            )
            .padding(.bottom, 12)
        }
    }
    .preferredColorScheme(.dark)
}
