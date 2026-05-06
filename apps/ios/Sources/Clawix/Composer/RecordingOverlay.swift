import SwiftUI

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
            mainPill
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
    }

    private var cancelButton: some View {
        Button(action: triggerCancel) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Circle())
                Image(systemName: "arrow.down")
                    .font(BodyFont.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel recording")
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
        let isPaused = (phase == .paused)
        return HStack(spacing: 8) {
            primaryControlButton(isPaused: isPaused)
            RecordingWaveform(isActive: !isPaused, levels: levels)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .padding(.horizontal, 4)
            sendCircle(enabled: true, action: triggerSend)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Capsule(style: .continuous))
    }

    private var transcribingPill: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.white.opacity(0.75))
                    .scaleEffect(0.9)
                Text("Transcribing")
                    .font(Typography.bodyFont)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, 16)
            Spacer(minLength: 0)
            sendCircle(enabled: false, action: {})
        }
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .frame(minHeight: 50)
        .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: Capsule(style: .continuous))
    }

    // Square stop / triangle resume. Tapping it depends on the phase:
    // recording -> stop (transcribe or pause); paused -> resume the
    // take so the user can keep talking.
    private func primaryControlButton(isPaused: Bool) -> some View {
        Button(action: { isPaused ? triggerResume() : triggerStop() }) {
            ZStack {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: Circle())
                if isPaused {
                    Image(systemName: "play.fill")
                        .font(BodyFont.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .offset(x: 1)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Resume recording" : "Stop recording")
    }

    private func sendCircle(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
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
