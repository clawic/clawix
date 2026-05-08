import SwiftUI
import AVFoundation
import ClawixCore

/// Audio player rendered inline with a user voice-note message. Mirrors
/// the WhatsApp idiom: round play/pause bubble, static waveform glyph,
/// duration label. The bytes live on the Mac (the daemon writes the
/// canonical copy under Application Support); the bubble lazily fetches
/// them on first tap via `BridgeStore.requestAudio` and caches the
/// download to NSCachesDirectory so subsequent replays don't re-roundtrip.
struct UserAudioBubble: View {
    let audioRef: WireAudioRef
    @Bindable var store: BridgeStore

    @State private var player: AVAudioPlayer?
    @State private var playerDelegate: PlayerDelegate?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var failureMessage: String?
    @State private var isLoadingBytes = false
    @State private var progressTimer: Timer?

    var body: some View {
        HStack(spacing: 10) {
            playPauseButton
            waveform
                .frame(maxWidth: .infinity)
            Text(durationLabel)
                .font(BodyFont.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
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
                    .fill(Color.white.opacity(0.16))
                if isLoadingBytes && player == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Palette.textPrimary)
                } else {
                    LucideIcon.auto(isPlaying ? "pause.fill" : "play.fill", size: 12)
                        .foregroundStyle(Palette.textPrimary)
                        .offset(x: isPlaying ? 0 : 1)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")
    }

    private var waveform: some View {
        let bars = 22
        // Deterministic pseudo-waveform derived from the audioId so the
        // bubble has texture without us having to decode the audio just
        // to draw it. Real waveform rendering is a future polish pass.
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
            if isPlaying { return formatTime(player.currentTime) }
            return formatTime(Double(audioRef.durationMs) / 1000.0)
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
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                player.play()
                isPlaying = true
                startProgressTimer()
            }
            return
        }
        guard !isLoadingBytes else { return }
        isLoadingBytes = true
        let audioId = audioRef.id
        Task {
            do {
                let payload = try await store.requestAudio(audioId: audioId)
                let url = try cacheAudio(audioId: audioId, data: payload.data, mimeType: payload.mimeType)
                await MainActor.run {
                    self.isLoadingBytes = false
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
                    try? AVAudioSession.sharedInstance().setActive(true, options: [])
                    if let p = try? AVAudioPlayer(contentsOf: url) {
                        let delegate = PlayerDelegate { didFinish in
                            Task { @MainActor in
                                if didFinish { self.isPlaying = false; self.progress = 0 }
                            }
                        }
                        p.delegate = delegate
                        self.playerDelegate = delegate
                        p.prepareToPlay()
                        p.play()
                        self.player = p
                        self.isPlaying = true
                        self.startProgressTimer()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingBytes = false
                    self.failureMessage = "Audio unavailable"
                }
            }
        }
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
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                }
            }
        }
    }

    private func cacheAudio(audioId: String, data: Data, mimeType: String) throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = caches.appendingPathComponent("clawix-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = audioFileExtension(for: mimeType)
        let url = dir.appendingPathComponent("\(audioId).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func audioFileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/wav", "audio/x-wav", "audio/wave":     return "wav"
        case "audio/m4a", "audio/mp4", "audio/x-m4a":      return "m4a"
        case "audio/aac":                                  return "aac"
        case "audio/mpeg", "audio/mp3":                    return "mp3"
        case "audio/caf", "audio/x-caf":                   return "caf"
        default:                                           return "m4a"
        }
    }

    private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish(flag)
        }
    }
}
