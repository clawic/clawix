import SwiftUI
import AVFoundation
import ClawixCore
import ClawixEngine

/// Pill-shaped player rendered above a user message that originated as
/// a voice clip. Mirrors the WhatsApp idiom: round play/pause bubble
/// followed by a static waveform glyph and the clip's total duration.
/// The transcript stays under the bubble (rendered by the parent), so
/// the user can read what they sent and replay it without losing
/// context.
///
/// macOS reads audio bytes from the framework audio catalog.
struct UserAudioBubble: View {
    let audioRef: WireAudioRef

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var displayURL: URL?
    @State private var isLoadingBytes = false
    @State private var failureMessage: String?
    @State private var progressTimer: Timer?

    var body: some View {
        HStack(spacing: 10) {
            playPauseButton
            waveform
                .frame(maxWidth: .infinity)
            Text(durationLabel)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .onDisappear {
            progressTimer?.invalidate()
            progressTimer = nil
            player?.stop()
        }
    }

    private var playPauseButton: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                LucideIcon.auto(isPlaying ? "pause.fill" : "play.fill", size: 13)
                    .foregroundColor(Palette.textPrimary)
                    .offset(x: isPlaying ? 0 : 1)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingBytes && player == nil)
        .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")
    }

    private var waveform: some View {
        // Static deterministic glyph: a row of vertical bars whose
        // heights are derived from the audio id so the bubble has
        // some character without needing to decode the full
        // waveform off disk on first paint.
        let bars = 22
        let seed = audioRef.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let pseudo = Double((seed &+ i &* 17) % 9 + 2) / 11.0
                    let played = Double(i) / Double(bars - 1) <= progress
                    Capsule(style: .continuous)
                        .fill(played
                              ? Palette.textPrimary.opacity(0.85)
                              : Palette.textPrimary.opacity(0.30))
                        .frame(width: 2, height: max(4, geo.size.height * pseudo))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 22)
    }

    private var durationLabel: String {
        if let player {
            let elapsed = player.currentTime
            let totalSec = max(0, Double(audioRef.durationMs) / 1000.0)
            if isPlaying {
                return formatTime(elapsed)
            } else {
                return formatTime(totalSec)
            }
        }
        return formatTime(Double(audioRef.durationMs) / 1000.0)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func toggle() {
        if let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                progressTimer?.invalidate()
                progressTimer = nil
            } else {
                player.play()
                isPlaying = true
                startProgressTimer()
            }
            return
        }
        guard !isLoadingBytes else { return }
        isLoadingBytes = true
        Task {
            let payload = await Self.loadBytes(for: audioRef.id)
            await MainActor.run {
                self.isLoadingBytes = false
                guard let payload else {
                    self.failureMessage = "Audio no longer available"
                    return
                }
                let ext = AudioCatalogRegistration.fileExtension(for: payload.mimeType)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("clawix-replay-\(self.audioRef.id).\(ext)")
                try? payload.data.write(to: url, options: .atomic)
                self.displayURL = url
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.prepareToPlay()
                    p.play()
                    self.player = p
                    self.isPlaying = true
                    self.startProgressTimer()
                }
            }
        }
    }

    /// Resolution order: framework audio catalog only. The host does not
    /// read sidecar audio files for message playback.
    private static func loadBytes(for audioId: String) async -> (data: Data, mimeType: String)? {
        if let client = await MainActor.run(body: { AudioCatalogBootstrap.shared.currentClient }) {
            do {
                let response = try await client.getBytes(audioId: audioId, appId: "clawix")
                if let bytes = Data(base64Encoded: response.base64) {
                    return (bytes, response.mimeType)
                }
            } catch ClawJSAudioClient.Error.notFound {
                return nil
            } catch {
                return nil
            }
        }
        return nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let p = self.player else { return }
                if p.duration > 0 {
                    self.progress = min(1, p.currentTime / p.duration)
                }
                if !p.isPlaying {
                    self.isPlaying = false
                    if p.currentTime >= p.duration - 0.05 {
                        self.progress = 0
                        p.currentTime = 0
                    }
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            }
        }
    }
}
