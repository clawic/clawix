import SwiftUI
import AppKit

@MainActor
final class AndroidSimulatorFramebufferController: ObservableObject {
    enum State: Equatable {
        case idle
        case locatingTools
        case locatingDevice
        case booting(String)
        case capturing(String)
        case running(String)
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Preparing Android Emulator"
            case .locatingTools: return "Finding Android tools"
            case .locatingDevice: return "Finding an Android emulator"
            case .booting(let name): return "Booting \(name)"
            case .capturing(let name): return "Reading \(name) display"
            case .running(let name): return "\(name) is running"
            case .failed: return "Android emulator unavailable"
            }
        }

        var detail: String? {
            if case .failed(let message) = self { return message }
            return nil
        }

        var allowsRetry: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published var state: State = .idle
    @Published var frameImage: NSImage?
    @Published var statusLine = ""
    @Published var availableAVDs: [AndroidAVDChoice] = []

    var showsOverlay: Bool {
        switch state {
        case .running:
            return frameImage == nil
        default:
            return true
        }
    }

    var canRefresh: Bool { selectedDevice != nil }
    var canControl: Bool { selectedDevice != nil && frameImage != nil }
    var selectedDeviceName: String { selectedDevice?.displayName ?? payload?.deviceName ?? "Android Emulator" }

    var payload: SidebarItem.AndroidSimulatorPayload?
    var onPayloadChange: (SidebarItem.AndroidSimulatorPayload) -> Void = { _ in }
    var adbPath: String?
    var emulatorPath: String?
    var selectedDevice: AndroidEmulatorDevice?
    var startTask: Task<Void, Never>?
    var captureTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var interactionTask: Task<Void, Never>?
    var emulatorProcess: Process?
    var ownsSelectedDevice = false
    var pointerIsActive = false
    var pointerStart: CGPoint?
    var lastPointerPoint: CGPoint?
    var captureInFlight = false
    var consecutiveCaptureFailures = 0

    func configure(
        payload: SidebarItem.AndroidSimulatorPayload,
        onPayloadChange: @escaping (SidebarItem.AndroidSimulatorPayload) -> Void
    ) {
        self.payload = payload
        self.onPayloadChange = onPayloadChange
    }

    func start() {
        guard startTask == nil else { return }
        startTask = Task { [weak self] in
            await self?.runStartup()
        }
    }

    func restart() {
        stop()
        frameImage = nil
        statusLine = ""
        state = .idle
        start()
    }

    func stop() {
        startTask?.cancel()
        captureTask?.cancel()
        refreshTask?.cancel()
        interactionTask?.cancel()
        if ownsSelectedDevice, let selectedDevice, let adbPath {
            Task.detached(priority: .utility) {
                _ = try? await Self.runTool(adbPath, ["-s", selectedDevice.serial, "emu", "kill"])
            }
        }
        if let emulatorProcess, emulatorProcess.isRunning {
            emulatorProcess.terminate()
        }
        startTask = nil
        captureTask = nil
        refreshTask = nil
        interactionTask = nil
        emulatorProcess = nil
        ownsSelectedDevice = false
        selectedDevice = nil
        pointerIsActive = false
        pointerStart = nil
        lastPointerPoint = nil
        captureInFlight = false
        consecutiveCaptureFailures = 0
    }

    func selectAVD(_ avd: AndroidAVDChoice) {
        let updatedPayload = SidebarItem.AndroidSimulatorPayload(
            id: payload?.id ?? UUID(),
            avdName: avd.name,
            deviceName: avd.displayName
        )
        payload = updatedPayload
        onPayloadChange(updatedPayload)
        restart()
    }

    func refreshNow() {
        guard let device = selectedDevice, let adbPath else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
        }
    }

    func keyEvent(_ key: String) {
        guard let device = selectedDevice, let adbPath else { return }
        Task { [weak self] in
            _ = try? await Self.runTool(adbPath, ["-s", device.serial, "shell", "input", "keyevent", key], timeout: 5)
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
        }
    }

    func openURL(_ url: String) {
        guard let device = selectedDevice, let adbPath else { return }
        Task { [weak self] in
            _ = try? await Self.runTool(adbPath, [
                "-s", device.serial,
                "shell", "am", "start",
                "-a", "android.intent.action.VIEW",
                "-d", url
            ], timeout: 8)
            try? await Task.sleep(nanoseconds: 800_000_000)
            await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
        }
    }

    func setNightMode(_ enabled: Bool) {
        guard let device = selectedDevice, let adbPath else { return }
        Task { [weak self] in
            _ = try? await Self.runTool(adbPath, [
                "-s", device.serial,
                "shell", "cmd", "uimode", "night", enabled ? "yes" : "no"
            ], timeout: 5)
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
        }
    }

    func handlePointer(phase: AndroidSimulatorPointerPhase, devicePoint: CGPoint) {
        guard let device = selectedDevice, let adbPath else { return }
        let rounded = CGPoint(x: round(devicePoint.x), y: round(devicePoint.y))
        switch phase {
        case .began:
            pointerIsActive = true
            pointerStart = rounded
            lastPointerPoint = rounded
        case .moved:
            lastPointerPoint = rounded
        case .ended:
            let start = pointerStart ?? rounded
            let end = rounded
            pointerStart = nil
            lastPointerPoint = nil
            interactionTask?.cancel()
            interactionTask = Task { [weak self] in
                defer {
                    Task { @MainActor [weak self] in
                        self?.pointerIsActive = false
                    }
                }
                if hypot(end.x - start.x, end.y - start.y) < 8 {
                    _ = try? await Self.runTool(adbPath, [
                        "-s", device.serial,
                        "shell", "input", "tap",
                        "\(Int(end.x))", "\(Int(end.y))"
                    ], timeout: 5)
                } else {
                    _ = try? await Self.runTool(adbPath, [
                        "-s", device.serial,
                        "shell", "input", "swipe",
                        "\(Int(start.x))", "\(Int(start.y))",
                        "\(Int(end.x))", "\(Int(end.y))",
                        "260"
                    ], timeout: 5)
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
            }
        }
    }
}
