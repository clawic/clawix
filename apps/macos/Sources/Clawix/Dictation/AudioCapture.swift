import Foundation
import AVFoundation
import Accelerate
import CoreAudio
import AudioToolbox

/// Captures mic audio into a 16 kHz mono Float32 buffer (Whisper's
/// input format) and reports a rolling RMS-normalized waveform level.
///
/// `AVAudioEngine` is used instead of `AVAudioRecorder` because we want
/// raw PCM samples in memory (Whisper's input format) rather than a
/// compressed file we'd have to decode again. The `inputNode` runs at
/// the device's hardware format; an `AVAudioConverter` adapts that to
/// 16 kHz mono Float32.
///
/// The class is intentionally NOT `@MainActor`. The audio tap callback
/// runs on a real-time audio thread; trying to bounce every tick onto
/// the main actor would either drop frames or starve the UI. Conversion
/// and accumulation happen on a private serial queue. Only the small,
/// already-throttled `onLevels` callback hops to the main actor so the
/// `DictationCoordinator` can republish to SwiftUI.
final class AudioCapture {

    private let engine = AVAudioEngine()
    private let workQueue = DispatchQueue(label: "clawix.dictation.capture")

    /// Mutable state guarded by `workQueue` (or set during `start()`
    /// before the tap is installed and read after `stop()` drains).
    private var converter: AVAudioConverter?
    private var collected: [Float] = []
    private var lastLevels: [CGFloat] = []
    private var running = false

    /// 16 kHz mono Float32 — exactly what Whisper consumes.
    private let targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }()

    /// Same buffer size the composer's `VoiceWaveform` expects.
    private let maxLevels = 120

    /// Called on the main actor whenever the rolling levels change.
    /// `DictationCoordinator` republishes them as `@Published`.
    var onLevels: ((_ levels: [CGFloat]) -> Void)?

    /// Start capture, optionally bound to a specific input device. The
    /// caller resolves the AudioDeviceID on the main actor (typically
    /// via `MicrophonePreferences.shared.activeDeviceID()`) and passes
    /// it through, so this method can do its work on `workQueue`
    /// without re-entering main and risking deadlock.
    func start(deviceID: AudioDeviceID? = nil) throws {
        try workQueue.sync {
            guard !running else { return }

            // Apply the user-preferred input device BEFORE asking the
            // input node for its format; the format depends on which
            // hardware unit is currently bound to the engine.
            if let deviceID, deviceID != 0 {
                try applyInputDevice(deviceID)
            }

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            collected.removeAll(keepingCapacity: false)
            lastLevels.removeAll(keepingCapacity: true)

            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.workQueue.async { self?.process(buffer: buffer) }
            }

            engine.prepare()
            do {
                try engine.start()
                running = true
            } catch {
                input.removeTap(onBus: 0)
                throw error
            }
        }
    }

    func stopAndCollect() -> [Float] {
        workQueue.sync {
            guard running else { return [] }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
            let copy = collected
            collected.removeAll(keepingCapacity: false)
            return copy
        }
    }

    func cancel() {
        workQueue.sync {
            guard running else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
            collected.removeAll(keepingCapacity: false)
        }
    }

    // MARK: - Private (workQueue-only)

    private func applyInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let unit = engine.inputNode.audioUnit else { return }
        var id = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to bind audio input device (status \(status))"]
            )
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil,
              let channel = output.floatChannelData?[0] else { return }
        let count = Int(output.frameLength)
        guard count > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        collected.append(contentsOf: samples)
        appendLevel(from: samples)
    }

    private func appendLevel(from samples: [Float]) {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let dB = 20 * log10(max(rms, .leastNonzeroMagnitude))
        // Soft-knee mapping: quiet speech still produces a visible bar
        // without loud peaks clipping everything to the maximum.
        let normalized = pow(10.0, Double(dB) / 30.0)
        let clamped = max(0.0, min(1.0, normalized))
        lastLevels.append(CGFloat(clamped))
        if lastLevels.count > maxLevels {
            lastLevels.removeFirst(lastLevels.count - maxLevels)
        }
        let snapshot = lastLevels
        DispatchQueue.main.async { [weak self] in
            self?.onLevels?(snapshot)
        }
    }
}
