import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import Accelerate

/// Captures mic audio at 16 kHz mono Float32 (Whisper's input format)
/// and reports a rolling normalized level history for the recording UI.
///
/// The earlier implementation used `AVAudioEngine.installTap`, which on
/// macOS is fragile when the input node's underlying audio unit has its
/// device rebound at runtime (`kAudioOutputUnitProperty_CurrentDevice`):
/// the tap silently stops delivering buffers in many cases. This one
/// uses AUHAL directly — the same path validated dictation tools rely
/// on — so the input callback fires every audio cycle regardless of
/// which device is bound.
///
/// Design notes:
///   * Public surface (`onLevels`, `start`, `stopAndCollect`, `cancel`)
///     is unchanged from the previous AVAudioEngine version, so the
///     coordinator and the transcription pipeline didn't have to move.
///   * The render callback runs on a real-time audio thread; allocations
///     and locks there cause glitches and dropouts. Render/conversion
///     buffers are pre-allocated, the level publish hops to main via a
///     plain `DispatchQueue.main.async`, and the only synchronization is
///     a single `pthread_mutex` around the recorded-samples buffer
///     (taken only when `stopAndCollect` drains).
///   * Sample-rate conversion is a small linear interpolator inline in
///     the callback (cheap; mic input is single-channel after mixing).
///     This keeps us off `AVAudioConverter` which insists on its own
///     buffer protocol and made the AVAudioEngine path even more
///     fragile.
final class AudioCapture {

    // MARK: - Public surface

    /// Called on the main thread whenever the rolling levels change.
    /// `DictationCoordinator` republishes them as `@Published` so the
    /// SwiftUI overlay's bar visualizer reads `levels.last`.
    var onLevels: ((_ levels: [CGFloat]) -> Void)?

    enum CaptureError: Error, LocalizedError {
        case audioUnitNotFound
        case osStatus(name: String, status: OSStatus)
        case noInputDevice

        var errorDescription: String? {
            switch self {
            case .audioUnitNotFound:
                return "HAL Output AudioUnit not found"
            case .noInputDevice:
                return "No audio input device is available"
            case .osStatus(let name, let status):
                return "\(name) failed (status \(status))"
            }
        }
    }

    /// Start capture, optionally bound to a specific input device. The
    /// caller resolves the AudioDeviceID on the main actor (typically
    /// `MicrophonePreferences.shared.activeDeviceID()`); pass `nil` or
    /// `0` to fall back to the system default.
    func start(deviceID: AudioDeviceID? = nil) throws {
        try setupQueue.sync {
            try startLocked(deviceID: deviceID)
        }
    }

    /// Stop capture and return the entire 16 kHz mono Float32 buffer.
    /// Called by the coordinator at the end of a session before
    /// handing the samples to `TranscriptionService`.
    func stopAndCollect() -> [Float] {
        return setupQueue.sync {
            guard isRunning else { return [] }
            tearDown()
            samplesLock.lock()
            let copy = collectedSamples
            collectedSamples.removeAll(keepingCapacity: false)
            samplesLock.unlock()
            return copy
        }
    }

    /// Discard the in-flight session without surfacing samples. Used by
    /// `coordinator.cancel()` and the overlay's Esc handler.
    func cancel() {
        setupQueue.sync {
            guard isRunning else { return }
            tearDown()
            samplesLock.lock()
            collectedSamples.removeAll(keepingCapacity: false)
            samplesLock.unlock()
        }
    }

    // MARK: - State (setupQueue / audio thread)

    /// Serial queue used for every public mutation. The render callback
    /// itself runs on the real-time audio thread; this queue only
    /// coordinates start/stop transitions and reads the drain.
    private let setupQueue = DispatchQueue(label: "clawix.dictation.capture.setup", qos: .userInitiated)

    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var deviceFormat = AudioStreamBasicDescription()

    /// Pre-allocated buffer the render callback writes into. Sized for
    /// the maximum expected slice count so the callback never has to
    /// allocate.
    private var renderBuffer: UnsafeMutablePointer<Float32>?
    private var renderBufferFrames: UInt32 = 0
    private var renderBufferChannels: UInt32 = 0

    /// Samples collected since the start of the session, already
    /// downsampled to 16 kHz mono Float32. Guarded by `samplesLock`,
    /// which is an `NSLock` (lock-free Swift call sites; `pthread_mutex_t`
    /// would need C-style `pthread_mutex_lock(&l)` everywhere).
    private let samplesLock = NSLock()
    private var collectedSamples: [Float] = []
    /// Carry-over from the previous render callback's last sample, used
    /// by the linear interpolator to bridge buffer boundaries cleanly.
    private var resamplerLastSample: Float = 0
    /// Fractional position into the input buffer carried across calls
    /// so consecutive callbacks produce a continuous output stream.
    private var resamplerPhase: Double = 0

    /// Rolling level history (last 120 normalized 0…1 values) and its
    /// EMA-smoothed accumulator, both touched only on the audio thread.
    private var lastLevels: [CGFloat] = []
    private let maxLevels = 120
    private var smoothedLevel: Float = 0

    /// 16 kHz mono Float32 — Whisper's required input format.
    private let outputSampleRate: Double = 16_000

    init() {}

    deinit {
        cancel()
    }

    // MARK: - Start (setupQueue only)

    private func startLocked(deviceID: AudioDeviceID?) throws {
        guard !isRunning else { return }

        // Resolve a usable device. 0 means "system default"; we don't
        // bind in that case and let the HAL pick the default input.
        let resolved = (deviceID ?? 0) != 0
            ? deviceID!
            : Self.systemDefaultInputDevice()
        guard resolved != 0 else { throw CaptureError.noInputDevice }

        // 1. Create the HAL Output audio unit with input enabled.
        let unit = try makeAudioUnit()
        audioUnit = unit
        try enableIO(unit: unit)

        // 2. Bind the input device. Even when the resolved device is
        // the system default, binding it explicitly stops the unit
        // from drifting if the user changes the default mid-session.
        try setProperty(
            unit: unit,
            id: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: resolved,
            label: "kAudioOutputUnitProperty_CurrentDevice"
        )

        // 3. Read the device's native format and tell the unit the
        // callback wants Float32 at the same sample rate / channel
        // count. Sample rate / channel conversion to 16 kHz mono is
        // handled inline in the callback — keeping the negotiated unit
        // format identical to the device's avoids the unit refusing
        // because we asked it to do too much.
        let nativeFormat = try inputStreamFormat(unit: unit)
        deviceFormat = nativeFormat

        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: nativeFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * nativeFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * nativeFormat.mChannelsPerFrame,
            mChannelsPerFrame: nativeFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try setStreamFormat(unit: unit, format: &callbackFormat)

        // 4. Pre-allocate the render buffer for the worst-case slice
        // size. 4096 frames is generous; system buffer sizes top out
        // around 1024-2048 in normal use.
        let maxFrames: UInt32 = 4096
        let totalSamples = maxFrames * nativeFormat.mChannelsPerFrame
        let buffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(totalSamples))
        renderBuffer = buffer
        renderBufferFrames = maxFrames
        renderBufferChannels = nativeFormat.mChannelsPerFrame

        // 5. Reset rolling state so a previous session's tail doesn't
        // leak into the new one's first frame.
        samplesLock.lock()
        collectedSamples.removeAll(keepingCapacity: true)
        samplesLock.unlock()
        lastLevels.removeAll(keepingCapacity: true)
        smoothedLevel = 0
        resamplerLastSample = 0
        resamplerPhase = 0

        // 6. Wire the render callback. The opaque pointer captures
        // `self` unretained — the callback handler immediately
        // dereferences it back, so as long as `cancel()`/`stopAndCollect`
        // run before deinit (they do; `setupQueue.sync` enforces it),
        // there's no use-after-free risk.
        var callbackStruct = AURenderCallbackStruct(
            inputProc: AudioCapture.renderCallbackThunk,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        if status != noErr {
            tearDown()
            throw CaptureError.osStatus(name: "SetInputCallback", status: status)
        }

        // 7. Initialize and start. From here on, the callback fires.
        var initStatus = AudioUnitInitialize(unit)
        if initStatus != noErr {
            tearDown()
            throw CaptureError.osStatus(name: "AudioUnitInitialize", status: initStatus)
        }
        initStatus = AudioOutputUnitStart(unit)
        if initStatus != noErr {
            tearDown()
            throw CaptureError.osStatus(name: "AudioOutputUnitStart", status: initStatus)
        }

        isRunning = true
    }

    private func tearDown() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }
        if let buffer = renderBuffer {
            buffer.deallocate()
            renderBuffer = nil
            renderBufferFrames = 0
            renderBufferChannels = 0
        }
        isRunning = false
    }

    // MARK: - Render callback

    /// C-callback shim. AUHAL hands us the render context for the input
    /// bus; we delegate to the recorder instance via the captured
    /// opaque pointer.
    private static let renderCallbackThunk: AURenderCallback = {
        inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
        let recorder = Unmanaged<AudioCapture>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.renderInput(
            ioActionFlags: ioActionFlags,
            timeStamp: inTimeStamp,
            busNumber: inBusNumber,
            frameCount: inNumberFrames
        )
    }

    private func renderInput(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard let unit = audioUnit, let buffer = renderBuffer, isRunning else {
            return noErr
        }
        let channelCount = renderBufferChannels
        let totalSamples = frameCount * channelCount
        guard totalSamples > 0, totalSamples <= renderBufferFrames * channelCount else {
            return noErr
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * channelCount
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: channelCount,
                mDataByteSize: frameCount * bytesPerFrame,
                mData: UnsafeMutableRawPointer(buffer)
            )
        )

        let status = AudioUnitRender(unit, ioActionFlags, timeStamp, busNumber, frameCount, &bufferList)
        if status != noErr {
            return status
        }

        // 1. Mix to mono in-place by averaging channels. The downstream
        // resampler reads the first `frameCount` Float32s as a mono
        // signal; subsequent slots in the buffer are scratch.
        if channelCount == 1 {
            // Already mono — nothing to do.
        } else {
            for i in 0..<Int(frameCount) {
                var sum: Float32 = 0
                for ch in 0..<Int(channelCount) {
                    sum += buffer[i * Int(channelCount) + ch]
                }
                buffer[i] = sum / Float32(channelCount)
            }
        }

        // 2. Compute RMS over the mono signal for the meter.
        var rms: Float = 0
        vDSP_rmsqv(buffer, 1, &rms, vDSP_Length(frameCount))
        publishLevel(rms: rms)

        // 3. Linear-interpolate down to 16 kHz and append to the
        // collected buffer. We carry `resamplerPhase` and
        // `resamplerLastSample` across calls so adjacent buffers join
        // seamlessly without a click.
        appendResampled(monoSource: buffer, frameCount: Int(frameCount))

        return noErr
    }

    private func publishLevel(rms: Float) {
        let dB = 20 * log10(max(rms, 0.000001))
        // Linear remap of -60…0 dB into 0…1, the window most macOS
        // dictation UIs use to drive their bar visualizers. The earlier
        // soft-knee curve compressed normal speech (~-26 dB) down to
        // ~0.13, leaving the bars almost flat once the visualizer
        // applied its `pow(level, 0.7)` amplitude term.
        let minDb: Float = -60
        let maxDb: Float = 0
        let raw: Float
        if dB <= minDb {
            raw = 0
        } else if dB >= maxDb {
            raw = 1
        } else {
            raw = (dB - minDb) / (maxDb - minDb)
        }
        // EMA smoothing: a single quiet buffer between speech bursts
        // shouldn't snap the bars to zero. 0.6 / 0.4 keeps the meter
        // glued to the voice without feeling laggy.
        smoothedLevel = smoothedLevel * 0.6 + raw * 0.4
        let display = max(0, min(1, smoothedLevel))
        lastLevels.append(CGFloat(display))
        if lastLevels.count > maxLevels {
            lastLevels.removeFirst(lastLevels.count - maxLevels)
        }
        let snapshot = lastLevels
        DispatchQueue.main.async { [weak self] in
            self?.onLevels?(snapshot)
        }
    }

    private func appendResampled(monoSource: UnsafeMutablePointer<Float32>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let inputRate = deviceFormat.mSampleRate
        let outputRate = outputSampleRate

        if inputRate == outputRate {
            // No conversion needed.
            samplesLock.lock()
            collectedSamples.append(contentsOf: UnsafeBufferPointer(start: monoSource, count: frameCount))
            samplesLock.unlock()
            resamplerLastSample = monoSource[frameCount - 1]
            return
        }

        let ratio = inputRate / outputRate // typically 3 (48k→16k) or 2.756 etc.
        var produced: [Float] = []
        produced.reserveCapacity(Int(Double(frameCount) / ratio) + 2)

        // `phase` walks across the input buffer at increments of
        // `ratio`, picking interpolated samples. `resamplerLastSample`
        // is the conceptual sample at index -1 from the previous call,
        // so the very first interpolated sample at small phase still
        // has a left neighbour.
        var phase = resamplerPhase
        while phase < Double(frameCount) {
            let idx = Int(phase)
            let frac = Float(phase - Double(idx))
            let left = idx == 0 ? resamplerLastSample : monoSource[idx - 1]
            let right = monoSource[idx]
            // Interpolate between the previous and current sample.
            let value = left + (right - left) * frac
            produced.append(value)
            phase += ratio
        }
        // Carry the leftover phase into the next call so the output
        // stream is rate-coherent across buffer boundaries.
        resamplerPhase = phase - Double(frameCount)
        resamplerLastSample = monoSource[frameCount - 1]

        samplesLock.lock()
        collectedSamples.append(contentsOf: produced)
        samplesLock.unlock()
    }

    // MARK: - AudioUnit boilerplate

    private func makeAudioUnit() throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw CaptureError.audioUnitNotFound
        }
        var unit: AudioUnit?
        let status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let unit else {
            throw CaptureError.osStatus(name: "AudioComponentInstanceNew", status: status)
        }
        return unit
    }

    private func enableIO(unit: AudioUnit) throws {
        // Element 1 is the input scope, element 0 the output scope. We
        // want input on, output off — the unit then runs as a pure
        // recorder driven by the device's hardware clock.
        try setProperty(
            unit: unit,
            id: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Input,
            element: 1,
            value: UInt32(1),
            label: "EnableIO(input)"
        )
        try setProperty(
            unit: unit,
            id: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Output,
            element: 0,
            value: UInt32(0),
            label: "EnableIO(output off)"
        )
    }

    private func inputStreamFormat(unit: AudioUnit) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &format,
            &size
        )
        if status != noErr {
            throw CaptureError.osStatus(name: "GetStreamFormat", status: status)
        }
        return format
    }

    private func setStreamFormat(unit: AudioUnit, format: inout AudioStreamBasicDescription) throws {
        let status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        if status != noErr {
            throw CaptureError.osStatus(name: "SetStreamFormat", status: status)
        }
    }

    private func setProperty<T>(
        unit: AudioUnit,
        id: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: T,
        label: String
    ) throws {
        var v = value
        let status = withUnsafeMutablePointer(to: &v) { ptr in
            AudioUnitSetProperty(
                unit,
                id,
                scope,
                element,
                ptr,
                UInt32(MemoryLayout<T>.size)
            )
        }
        if status != noErr {
            throw CaptureError.osStatus(name: label, status: status)
        }
    }

    // MARK: - Helpers

    private static func systemDefaultInputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr ? device : 0
    }
}
