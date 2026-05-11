import SwiftUI
import AppKit

@MainActor
final class IOSSimulatorFramebufferController: ObservableObject {
    enum State: Equatable {
        case idle
        case locatingDevice
        case booting(String)
        case capturing(String)
        case running(String)
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Preparing iOS Simulator"
            case .locatingDevice: return "Finding an iOS device"
            case .booting(let name): return "Booting \(name)"
            case .capturing(let name): return "Reading \(name) display"
            case .running(let name): return "\(name) is running"
            case .failed: return "Simulator unavailable"
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

    enum Appearance: String {
        case light
        case dark
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var frameImage: NSImage?
    @Published private(set) var nativeDisplay: IOSSimulatorNativeDisplayDescriptor?
    @Published private(set) var statusLine = ""
    @Published private(set) var availableDevices: [IOSSimulatorDeviceChoice] = []

    var showsOverlay: Bool {
        switch state {
        case .running:
            return frameImage == nil && nativeDisplay == nil
        default:
            return true
        }
    }

    var canRefresh: Bool { selectedDevice != nil }
    var canControl: Bool { selectedDevice != nil && (frameImage != nil || nativeDisplay != nil) }
    var selectedDeviceName: String { selectedDevice?.name ?? payload?.deviceName ?? "iOS Simulator" }

    private var payload: SidebarItem.IOSSimulatorPayload?
    private var onPayloadChange: (SidebarItem.IOSSimulatorPayload) -> Void = { _ in }
    private var selectedDevice: SimDevice?
    private var startTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var hidBridge: IOSSimulatorHIDBridge?
    private var pointerIsActive = false
    private var lastPointerPoint: CGPoint?

    func configure(
        payload: SidebarItem.IOSSimulatorPayload,
        onPayloadChange: @escaping (SidebarItem.IOSSimulatorPayload) -> Void
    ) {
        self.payload = payload
        self.onPayloadChange = onPayloadChange
    }

    func selectDevice(_ device: IOSSimulatorDeviceChoice) {
        let updatedPayload = SidebarItem.IOSSimulatorPayload(
            id: payload?.id ?? UUID(),
            deviceUDID: device.udid,
            deviceName: device.name
        )
        payload = updatedPayload
        onPayloadChange(updatedPayload)
        restart()
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
        nativeDisplay = nil
        statusLine = ""
        state = .idle
        start()
    }

    func stop() {
        startTask?.cancel()
        captureTask?.cancel()
        refreshTask?.cancel()
        startTask = nil
        captureTask = nil
        refreshTask = nil
        hidBridge = nil
        pointerIsActive = false
        lastPointerPoint = nil
        nativeDisplay = nil
    }

    func refreshNow() {
        guard let device = selectedDevice else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.captureOnce(device: device, markRunning: true)
        }
    }

    func goHome() {
        guard let device = selectedDevice else { return }
        Task { [weak self] in
            _ = try? await Self.runTool("/usr/bin/xcrun", [
                "simctl", "spawn", device.udid,
                "notifyutil", "-p", "com.apple.springboard.homebutton"
            ], timeout: 5)
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self?.captureOnce(device: device, markRunning: true)
        }
    }

    func openURL(_ url: String) {
        guard let device = selectedDevice else { return }
        Task { [weak self] in
            _ = try? await Self.runTool("/usr/bin/xcrun", ["simctl", "openurl", device.udid, url], timeout: 8)
            try? await Task.sleep(nanoseconds: 900_000_000)
            await self?.captureOnce(device: device, markRunning: true)
        }
    }

    func setAppearance(_ appearance: Appearance) {
        guard let device = selectedDevice else { return }
        Task { [weak self] in
            _ = try? await Self.runTool("/usr/bin/xcrun", [
                "simctl", "ui", device.udid, "appearance", appearance.rawValue
            ], timeout: 5)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.captureOnce(device: device, markRunning: true)
        }
    }

    func handlePointer(phase: IOSSimulatorPointerPhase, devicePoint: CGPoint) {
        guard let bridge = hidBridge else { return }
        let previous = lastPointerPoint ?? devicePoint
        let screenSize = frameImage?.size ?? bridge.screenSize
        switch phase {
        case .began:
            pointerIsActive = true
            bridge.sendTouchEvent(phase: .began, point: devicePoint, screenSize: screenSize)
            bridge.sendMouseEvent(type: .leftMouseDown, point: devicePoint, previousPoint: previous, screenSize: screenSize)
            lastPointerPoint = devicePoint
        case .moved:
            bridge.sendTouchEvent(phase: .moved, point: devicePoint, screenSize: screenSize)
            bridge.sendMouseEvent(type: .leftMouseDragged, point: devicePoint, previousPoint: previous, screenSize: screenSize)
            lastPointerPoint = devicePoint
        case .ended:
            bridge.sendTouchEvent(phase: .ended, point: devicePoint, screenSize: screenSize)
            bridge.sendMouseEvent(type: .leftMouseUp, point: devicePoint, previousPoint: previous, screenSize: screenSize)
            lastPointerPoint = nil
            pointerIsActive = false
            refreshAfterPointerInput(device: bridge.device)
        }
    }

    private func runStartup() async {
        state = .locatingDevice
        do {
            let devices = try await Self.loadAvailableDevices()
            availableDevices = devices.map(IOSSimulatorDeviceChoice.init(device:))
            let device = try Self.selectDevice(from: devices, preferredUDID: payload?.deviceUDID)
            if Task.isCancelled { return }
            selectedDevice = device
            state = .booting(device.name)
            try await Self.boot(device: device)
            if Task.isCancelled { return }
            Self.terminateSimulatorAppIfOpen()
            hidBridge = IOSSimulatorHIDBridge(device: device)
            if device.isPhone {
                let aspectRatio = await nativeDisplayAspectRatio(for: device)
                nativeDisplay = IOSSimulatorNativeDisplayDescriptor(
                    deviceUDID: device.udid,
                    deviceName: device.name,
                    aspectRatio: aspectRatio
                )
                statusLine = "\(device.name) · embedded · interactive"
            } else {
                nativeDisplay = nil
                await captureOnce(device: device, markRunning: false)
                startCaptureLoop(device: device)
            }
            state = .running(device.name)
        } catch {
            if !Task.isCancelled {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func refreshAfterPointerInput(device: SimDevice) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            await self?.captureOnce(device: device, markRunning: true)
        }
    }

    private func startCaptureLoop(device: SimDevice) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.pointerIsActive == true {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }
                await self?.captureOnce(device: device, markRunning: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func captureOnce(device: SimDevice, markRunning: Bool) async {
        do {
            let png = try await Self.screenshot(device: device)
            if Task.isCancelled { return }
            guard let image = NSImage(data: png) else {
                throw SimulatorError.commandFailed("Simulator returned an unreadable screenshot.")
            }
            frameImage = image
            let inputStatus = hidBridge == nil ? "view only" : "interactive"
            statusLine = "\(device.name) · \(Int(image.size.width))x\(Int(image.size.height)) · \(inputStatus)"
            if markRunning {
                state = .running(device.name)
            }
        } catch {
            if !Task.isCancelled {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func nativeDisplayAspectRatio(for device: SimDevice) async -> CGFloat {
        do {
            let png = try await Self.screenshot(device: device)
            if let image = NSImage(data: png), image.size.height > 0 {
                return image.size.width / image.size.height
            }
        } catch {
            // Keep native SimulatorKit rendering available even if the
            // one-off aspect probe fails; the fallback ratio matches modern
            // full-screen iPhones closely enough to boot visibly.
        }
        return 1206.0 / 2622.0
    }

    private static func terminateSimulatorAppIfOpen() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.iphonesimulator")
            .forEach { app in
                if !app.terminate() {
                    app.forceTerminate()
                }
            }
    }

    private static func loadAvailableDevices() async throws -> [SimDevice] {
        let result = try await runTool("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"])
        guard result.status == 0 else {
            throw SimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let data = Data(result.stdout.utf8)
        let list = try JSONDecoder().decode(SimctlDeviceList.self, from: data)
        return list.devices
            .flatMap { runtime, devices in
                devices.map { device in
                    SimDevice(runtime: runtime, name: device.name, udid: device.udid, state: device.state)
                }
            }
            .filter {
                $0.name.localizedCaseInsensitiveContains("iPhone") ||
                $0.name.localizedCaseInsensitiveContains("iPad")
            }
            .sorted { lhs, rhs in
                if lhs.state == "Booted", rhs.state != "Booted" { return true }
                if rhs.state == "Booted", lhs.state != "Booted" { return false }
                if lhs.isPhone != rhs.isPhone { return lhs.isPhone && !rhs.isPhone }
                if lhs.runtime != rhs.runtime { return lhs.runtime > rhs.runtime }
                return lhs.name < rhs.name
            }
    }

    private static func selectDevice(from all: [SimDevice], preferredUDID: String?) throws -> SimDevice {
        if let preferredUDID, let preferred = all.first(where: { $0.udid == preferredUDID }) {
            return preferred
        }
        guard let device = all.first else {
            throw SimulatorError.noDevice
        }
        return device
    }

    private static func boot(device: SimDevice) async throws {
        if device.state == "Booted" { return }
        let result = try await runTool("/usr/bin/xcrun", ["simctl", "boot", device.udid])
        if result.status == 0 { return }
        let message = result.stderr + result.stdout
        if message.localizedCaseInsensitiveContains("current state: booted") { return }
        if message.localizedCaseInsensitiveContains("Unable to boot device in current state: Booted") { return }
        throw SimulatorError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func screenshot(device: SimDevice) async throws -> Data {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-ios-simulator-\(device.udid)-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }

        let result = try await runTool("/usr/bin/xcrun", [
            "simctl", "io", device.udid,
            "screenshot", "--type=png", "--mask=alpha",
            path.path
        ])
        guard result.status == 0 else {
            throw SimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Data(contentsOf: path)
    }

    nonisolated private static func runTool(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 20
    ) async throws -> ToolResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runToolSync(executable, arguments, timeout: timeout)
        }.value
    }

    nonisolated private static func runToolSync(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 20
    ) throws -> ToolResult {
        let tempDirectory = FileManager.default.temporaryDirectory
        let stdoutURL = tempDirectory.appendingPathComponent("clawix-ios-tool-\(UUID().uuidString).out")
        let stderrURL = tempDirectory.appendingPathComponent("clawix-ios-tool-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                let killDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            throw SimulatorError.commandFailed("simctl command timed out: \(arguments.joined(separator: " "))")
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()
        let out = String(data: (try? Data(contentsOf: stdoutURL)) ?? Data(), encoding: .utf8) ?? ""
        let err = String(data: (try? Data(contentsOf: stderrURL)) ?? Data(), encoding: .utf8) ?? ""
        return ToolResult(status: process.terminationStatus, stdout: out, stderr: err)
    }
}
