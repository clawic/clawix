import SwiftUI
import AVFoundation
import Accelerate
import CoreAudio
import AudioToolbox

/// Live RMS meter that lives only while the Voice-to-Text Settings page
/// is on screen. It taps the currently selected input device, normalises
/// each buffer to a 0…1 level, smooths it for display, and pauses
/// automatically while a real dictation is in progress so it never
/// fights for the device with `AudioCapture`.
///
/// Not `@MainActor` on purpose: the audio tap callback runs on a
/// real-time thread. Engine lifecycle hops to a private serial queue,
/// and only the @Published mutations bounce back to the main thread.
final class MicLevelMeterModel: ObservableObject {

    @Published private(set) var level: CGFloat = 0
    @Published private(set) var peak: CGFloat = 0
    @Published private(set) var isCapturing: Bool = false

    private let engine = AVAudioEngine()
    private let workQueue = DispatchQueue(label: "clawix.mic.meter")
    private var running = false

    // Read/written only on the main thread.
    private var smoothed: CGFloat = 0
    private var peakValue: CGFloat = 0
    private var decayTimer: Timer?

    func start(deviceID: AudioDeviceID?) {
        workQueue.async { [weak self] in
            guard let self else { return }
            guard !self.running else { return }
            if let deviceID, deviceID != 0 {
                self.applyInputDevice(deviceID)
            }
            let input = self.engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.process(buffer: buffer)
            }
            self.engine.prepare()
            do {
                try self.engine.start()
                self.running = true
                DispatchQueue.main.async { [weak self] in
                    self?.isCapturing = true
                    self?.startDecayTimer()
                }
            } catch {
                input.removeTap(onBus: 0)
            }
        }
    }

    func stop() {
        workQueue.async { [weak self] in
            guard let self, self.running else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            self.running = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCapturing = false
                self.smoothed = 0
                self.peakValue = 0
                self.level = 0
                self.peak = 0
                self.decayTimer?.invalidate()
                self.decayTimer = nil
            }
        }
    }

    // MARK: - Audio thread

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(count))
        let dB = 20 * log10(max(rms, .leastNonzeroMagnitude))
        // Map dBFS linearly to the visual 0…1 range. −45 dBFS is the
        // quiet-room floor (nothing below shows up); −3 dBFS is the
        // "all bars lit" ceiling. Linear-in-dB compresses the response
        // around conversational levels so a normal voice already lights
        // 2–3 of the six segments instead of just one.
        let normalized = (Double(dB) + 45.0) / 42.0
        let clamped = CGFloat(max(0.0, min(1.0, normalized)))
        DispatchQueue.main.async { [weak self] in
            self?.ingest(clamped)
        }
    }

    private func applyInputDevice(_ deviceID: AudioDeviceID) {
        guard let unit = engine.inputNode.audioUnit else { return }
        var id = deviceID
        _ = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    // MARK: - Main thread

    private func ingest(_ raw: CGFloat) {
        // Fast attack so a sudden word lights up the meter immediately;
        // slow release is handled by the decay timer below.
        if raw > smoothed {
            smoothed = smoothed * 0.4 + raw * 0.6
        } else {
            smoothed = smoothed * 0.85 + raw * 0.15
        }
        level = smoothed
        if smoothed > peakValue {
            peakValue = smoothed
        }
        peak = peakValue
    }

    private func startDecayTimer() {
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.smoothed = max(0, self.smoothed - 0.04)
            self.peakValue = max(self.smoothed, self.peakValue - 0.012)
            self.level = self.smoothed
            self.peak = self.peakValue
        }
    }
}

// MARK: - Inline meter

/// Three-dot inline level meter that sits inside the microphone
/// dropdown trigger, between the device name and the chevron. Just
/// enough visual feedback to confirm the mic is picking up sound; the
/// heavy lifting (engine lifecycle, gain) lives in
/// `MicLevelMeterModel`.
struct MicLevelTinyMeter: View {
    @ObservedObject var meter: MicLevelMeterModel
    let active: Bool

    private let dotCount = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                MicLevelTinyDot(
                    index: index,
                    total: dotCount,
                    level: meter.level,
                    active: active
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MicLevelTinyDot: View {
    let index: Int
    let total: Int
    let level: CGFloat
    let active: Bool

    var body: some View {
        let threshold = CGFloat(index) / CGFloat(total) + (1.0 / CGFloat(total)) * 0.35
        let lit = active && level >= threshold

        Circle()
            .fill(lit ? Color.white.opacity(0.92) : Color.white.opacity(0.22))
            .frame(width: 3.5, height: 3.5)
            .animation(.linear(duration: 0.05), value: lit)
    }
}
