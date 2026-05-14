import Foundation
import CoreAudio
import AudioToolbox
import Combine

/// Resolved input device identified by its persistent UID. The UID
/// survives reboots and reconnects, so it's the right key for the
/// "preferred mic" list — the AudioDeviceID is just a runtime handle.
struct MicrophoneDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    let deviceID: AudioDeviceID

    var id: String { uid }
}

/// Owns the user's microphone preferences and the live list of input
/// devices. Persists the last `maxPreferred` user-selected UIDs and
/// resolves the active device with this priority:
///
///   1. Most-recent preferred UID that is currently connected.
///   2. Next-recent preferred UID that is connected.
///   3. The system default input device.
///   4. The first available input device (fallback if Core Audio
///      reports no default).
///
/// Observes Core Audio so a hot-plug between recordings updates
/// `activeUID` automatically. The `DictationCoordinator` queries
/// `activeDeviceID()` at the start of every recording, so a newly
/// reconnected preferred mic takes effect on the next session without
/// the user touching anything.
/// Three-mode selection picker. `systemDefault` ignores the preferred
/// list entirely and binds to whatever macOS Sound preferences pick;
/// `custom` keeps a single preferred mic; `prioritized` walks an
/// ordered list and falls back if the top one disconnects.
enum MicrophoneInputMode: String, CaseIterable {
    case systemDefault
    case custom
    case prioritized

    var displayName: String {
        switch self {
        case .systemDefault: return "System default"
        case .custom:        return "Custom"
        case .prioritized:   return "Prioritized list"
        }
    }
}

@MainActor
final class MicrophonePreferences: ObservableObject {

    static let shared = MicrophonePreferences()

    static let modeKey = "dictation.microphone.mode"

    /// Input devices currently visible to Core Audio, ordered with
    /// preferred entries (most-recent first) and the rest below in
    /// alphabetical order.
    @Published private(set) var devices: [MicrophoneDevice] = []

    /// UID of the device the next recording will open. `nil` only when
    /// the system reports no input devices at all.
    @Published private(set) var activeUID: String?

    /// Persisted last-N user-selected UIDs, most recent first.
    @Published private(set) var preferredUIDs: [String] = []

    private let defaults: UserDefaults
    static let preferredKey = "dictation.microphone.preferred"
    private let maxPreferred = 3

    private var listenersInstalled = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferredUIDs = (defaults.stringArray(forKey: Self.preferredKey) ?? [])
            .filter { !$0.isEmpty }
        if preferredUIDs.count > maxPreferred {
            preferredUIDs = Array(preferredUIDs.prefix(maxPreferred))
        }
        installCoreAudioListeners()
        refresh()
    }

    /// Mark `uid` as the most-recent preferred device. Trims the list
    /// to `maxPreferred` and re-resolves the active selection.
    func selectPreferred(uid: String) {
        var list = preferredUIDs
        list.removeAll { $0 == uid }
        list.insert(uid, at: 0)
        if list.count > maxPreferred {
            list = Array(list.prefix(maxPreferred))
        }
        preferredUIDs = list
        defaults.set(list, forKey: Self.preferredKey)
        refresh()
    }

    /// Returns the AudioDeviceID for the next recording. Falls through
    /// to the system default input when no preferred device is
    /// connected; returns `nil` only when Core Audio reports no input
    /// devices at all (the engine then falls back to whatever input
    /// AVAudioEngine picks up by default).
    func activeDeviceID() -> AudioDeviceID? {
        // Mode `.systemDefault` short-circuits the preferred-list
        // walk and binds to whatever macOS picked in Sound prefs.
        if currentMode() == .systemDefault {
            return Self.systemDefaultInputDeviceID()
        }
        if let uid = activeUID, let dev = devices.first(where: { $0.uid == uid }) {
            return dev.deviceID
        }
        return Self.systemDefaultInputDeviceID()
    }

    var mode: MicrophoneInputMode {
        get { currentMode() }
        set {
            defaults.set(newValue.rawValue, forKey: Self.modeKey)
            objectWillChange.send()
            recomputeActive()
        }
    }

    private func currentMode() -> MicrophoneInputMode {
        let raw = defaults.string(forKey: Self.modeKey) ?? MicrophoneInputMode.custom.rawValue
        return MicrophoneInputMode(rawValue: raw) ?? .custom
    }

    /// Re-enumerate input devices and re-resolve the active selection.
    /// Called on init, on every Core Audio device-list change, and
    /// after the user selects a new preferred device.
    func refresh() {
        let inputs = Self.enumerateInputDevices()
        let preferredSet = Set(preferredUIDs)
        let preferredDevices = preferredUIDs.compactMap { uid in
            inputs.first(where: { $0.uid == uid })
        }
        let others = inputs
            .filter { !preferredSet.contains($0.uid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        devices = preferredDevices + others
        recomputeActive()
    }

    private func recomputeActive() {
        if let uid = preferredUIDs.first(where: { uid in devices.contains(where: { $0.uid == uid }) }) {
            activeUID = uid
            return
        }
        if let defaultID = Self.systemDefaultInputDeviceID(),
           let dev = devices.first(where: { $0.deviceID == defaultID }) {
            activeUID = dev.uid
            return
        }
        activeUID = devices.first?.uid
    }

    // MARK: - Core Audio plumbing

    private static func enumerateInputDevices() -> [MicrophoneDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize
        )
        if status != noErr || dataSize == 0 { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &ids
        )
        if status != noErr { return [] }

        var result: [MicrophoneDevice] = []
        for id in ids {
            guard hasInputChannels(deviceID: id) else { continue }
            guard let uid = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID),
                  let name = deviceName(deviceID: id) else { continue }
            result.append(MicrophoneDevice(uid: uid, name: name, deviceID: id))
        }
        return result
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let probe = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        if probe != noErr || dataSize == 0 { return false }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer)
        if status != noErr { return false }
        let abl = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        var totalChannels: UInt32 = 0
        for entry in buffers { totalChannels += entry.mNumberChannels }
        return totalChannels > 0
    }

    private static func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cf: Unmanaged<CFString>?
        var dataSize: UInt32 = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cf)
        guard status == noErr, let cf else { return nil }
        return cf.takeRetainedValue() as String
    }

    /// Prefer the user-friendly `kAudioObjectPropertyName`; fall back to
    /// the bare device-name selector if it's not exposed.
    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        if let n = stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) {
            return n
        }
        return stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
    }

    static func systemDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceID
        )
        if status != noErr || deviceID == 0 { return nil }
        return deviceID
    }

    private func installCoreAudioListeners() {
        guard !listenersInstalled else { return }
        listenersInstalled = true
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice
        ]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in
                    MicrophonePreferences.shared.refresh()
                }
            }
            _ = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }
}
