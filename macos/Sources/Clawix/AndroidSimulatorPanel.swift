import SwiftUI
import AppKit
import Darwin

/// In-app Android emulator surface for the right sidebar.
///
/// The Android Emulator does not expose a public AppKit view that can be
/// embedded. This panel runs an AVD headlessly when possible, renders its
/// framebuffer with `adb exec-out screencap -p`, and routes pointer input back
/// through `adb shell input`, keeping the visible emulator inside Clawix.
struct AndroidSimulatorPanel: View {
    let payload: SidebarItem.AndroidSimulatorPayload
    var onPayloadChange: (SidebarItem.AndroidSimulatorPayload) -> Void = { _ in }
    @StateObject private var controller = AndroidSimulatorFramebufferController()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.white.opacity(0.06))
            ZStack {
                Color.black
                simulatorStage
                if controller.showsOverlay {
                    overlay
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .onAppear {
            controller.configure(payload: payload, onPayloadChange: onPayloadChange)
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            AndroidSimulatorIconButton(systemName: "arrow.clockwise", enabled: controller.canRefresh) {
                controller.refreshNow()
            }
            .accessibilityLabel("Refresh emulator")

            AndroidSimulatorIconButton(systemName: "house", enabled: controller.canControl) {
                controller.keyEvent("KEYCODE_HOME")
            }
            .accessibilityLabel("Home")

            AndroidSimulatorIconButton(systemName: "chevron.left", enabled: controller.canControl) {
                controller.keyEvent("KEYCODE_BACK")
            }
            .accessibilityLabel("Back")

            AndroidSimulatorIconButton(systemName: "square.on.square", enabled: controller.canControl) {
                controller.keyEvent("KEYCODE_APP_SWITCH")
            }
            .accessibilityLabel("App switcher")

            AndroidSimulatorIconButton(systemName: "globe", enabled: controller.canControl) {
                controller.openURL("https://www.google.com")
            }
            .accessibilityLabel("Open browser")

            AndroidSimulatorIconButton(systemName: "sun.max", enabled: controller.canControl) {
                controller.setNightMode(false)
            }
            .accessibilityLabel("Light mode")

            AndroidSimulatorIconButton(systemName: "moon", enabled: controller.canControl) {
                controller.setNightMode(true)
            }
            .accessibilityLabel("Dark mode")

            Menu {
                ForEach(controller.availableAVDs) { avd in
                    Button(avd.menuTitle) {
                        controller.selectAVD(avd)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(controller.selectedDeviceName)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(Color(white: 0.82))
                        .lineLimit(1)
                    LucideIcon(.chevronDown, size: 10)
                        .foregroundColor(Color(white: 0.55))
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(controller.availableAVDs.isEmpty)
            .accessibilityLabel("Select Android emulator")

            Spacer(minLength: 0)

            Text(controller.statusLine)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Color(white: 0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.black)
    }

    @ViewBuilder
    private var simulatorStage: some View {
        if let image = controller.frameImage {
            GeometryReader { proxy in
                let screenAspect = max(0.1, image.size.width / max(1, image.size.height))
                AndroidSimulatorFrameSurface(
                    image: image,
                    aspectRatio: screenAspect,
                    stageSize: proxy.size
                ) { phase, point in
                    controller.handlePointer(phase: phase, devicePoint: point)
                }
            }
        } else {
            VStack(spacing: 10) {
                LucideIcon.auto("smartphone", size: 28)
                    .foregroundColor(Color(white: 0.32))
                Text("Waiting for Android display")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.54))
            }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                switch controller.state {
                case .running:
                    LucideIcon(.circleCheck, size: 14)
                        .foregroundColor(Color.green.opacity(0.85))
                case .failed:
                    LucideIcon(.triangleAlert, size: 14)
                        .foregroundColor(Color.orange.opacity(0.90))
                default:
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 14, height: 14)
                }

                Text(controller.state.title)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Color(white: 0.92))
            }

            if let detail = controller.state.detail {
                Text(detail)
                    .font(BodyFont.system(size: 11.5, wght: 400))
                    .foregroundColor(Color(white: 0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.state.allowsRetry {
                Button("Retry") {
                    controller.restart()
                }
                .buttonStyle(AndroidSimulatorPanelButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: 390, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

private struct AndroidSimulatorFrameSurface: View {
    let image: NSImage
    let aspectRatio: CGFloat
    let stageSize: CGSize
    let onPointer: (AndroidSimulatorPointerPhase, CGPoint) -> Void

    var body: some View {
        let screenRect = displayRect(in: stageSize)
        let chromeRect = screenRect.insetBy(dx: -11, dy: -11)
        let radius = min(34, max(16, min(chromeRect.width, chromeRect.height) * 0.08))

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(white: 0.025))
                .frame(width: chromeRect.width, height: chromeRect.height)
                .position(x: chromeRect.midX, y: chromeRect.midY)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.9)
                        .frame(width: chromeRect.width, height: chromeRect.height)
                        .position(x: chromeRect.midX, y: chromeRect.midY)
                )
                .shadow(color: .black.opacity(0.48), radius: 18, x: 0, y: 12)

            AndroidSimulatorFramebufferView(image: image, onPointer: onPointer)
                .frame(width: screenRect.width, height: screenRect.height)
                .position(x: screenRect.midX, y: screenRect.midY)
        }
        .frame(width: stageSize.width, height: stageSize.height)
    }

    private func displayRect(in size: CGSize) -> CGRect {
        let maxWidth = max(120, size.width - 50)
        let maxHeight = max(160, size.height - 50)
        var width = min(maxWidth, maxHeight * aspectRatio)
        var height = width / aspectRatio
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

private struct AndroidSimulatorFramebufferView: NSViewRepresentable {
    let image: NSImage
    let onPointer: (AndroidSimulatorPointerPhase, CGPoint) -> Void

    func makeNSView(context: Context) -> FramebufferNSView {
        FramebufferNSView(image: image, onPointer: onPointer)
    }

    func updateNSView(_ nsView: FramebufferNSView, context: Context) {
        nsView.image = image
        nsView.imageSize = image.size
        nsView.onPointer = onPointer
        nsView.needsDisplay = true
    }

    final class FramebufferNSView: NSView {
        var image: NSImage
        var imageSize: CGSize
        var onPointer: (AndroidSimulatorPointerPhase, CGPoint) -> Void

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        init(image: NSImage, onPointer: @escaping (AndroidSimulatorPointerPhase, CGPoint) -> Void) {
            self.image = image
            self.imageSize = image.size
            self.onPointer = onPointer
            super.init(frame: .zero)
            wantsLayer = true
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Embedded Android emulator framebuffer")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSGraphicsContext.current?.imageInterpolation = .medium
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onPointer(.began, mapToDevice(event))
        }

        override func mouseDragged(with event: NSEvent) {
            onPointer(.moved, mapToDevice(event))
        }

        override func mouseUp(with event: NSEvent) {
            onPointer(.ended, mapToDevice(event))
        }

        override func accessibilityPerformPress() -> Bool {
            guard let point = currentMousePoint() else { return false }
            onPointer(.began, point)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.onPointer(.ended, point)
            }
            return true
        }

        private func mapToDevice(_ event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            return mapLocalPointToDevice(local)
        }

        private func currentMousePoint() -> CGPoint? {
            guard let window else { return nil }
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return mapLocalPointToDevice(convert(windowPoint, from: nil))
        }

        private func mapLocalPointToDevice(_ local: CGPoint) -> CGPoint {
            let clampedX = min(max(local.x, bounds.minX), bounds.maxX)
            let clampedY = min(max(local.y, bounds.minY), bounds.maxY)
            let x = (clampedX - bounds.minX) / max(1, bounds.width) * imageSize.width
            let y = (clampedY - bounds.minY) / max(1, bounds.height) * imageSize.height
            return CGPoint(x: x, y: y)
        }
    }
}

private enum AndroidSimulatorPointerPhase {
    case began
    case moved
    case ended
}

private struct AndroidSimulatorIconButton: View {
    let systemName: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 13)
                .foregroundColor(foreground)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered && enabled ? Color.white.opacity(0.07) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var foreground: Color {
        if !enabled { return Color(white: 0.32) }
        return hovered ? Color(white: 0.92) : Color(white: 0.72)
    }
}

private struct AndroidSimulatorPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BodyFont.system(size: 11.5, wght: 600))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.20) : Color.white.opacity(0.12))
            )
    }
}

@MainActor
private final class AndroidSimulatorFramebufferController: ObservableObject {
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

    @Published private(set) var state: State = .idle
    @Published private(set) var frameImage: NSImage?
    @Published private(set) var statusLine = ""
    @Published private(set) var availableAVDs: [AndroidAVDChoice] = []

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

    private var payload: SidebarItem.AndroidSimulatorPayload?
    private var onPayloadChange: (SidebarItem.AndroidSimulatorPayload) -> Void = { _ in }
    private var adbPath: String?
    private var emulatorPath: String?
    private var selectedDevice: AndroidEmulatorDevice?
    private var startTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var interactionTask: Task<Void, Never>?
    private var emulatorProcess: Process?
    private var ownsSelectedDevice = false
    private var pointerIsActive = false
    private var pointerStart: CGPoint?
    private var lastPointerPoint: CGPoint?
    private var captureInFlight = false
    private var consecutiveCaptureFailures = 0

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

    fileprivate func handlePointer(phase: AndroidSimulatorPointerPhase, devicePoint: CGPoint) {
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

    private func runStartup() async {
        state = .locatingTools
        do {
            let toolchain = try await Self.locateToolchain()
            let adb = toolchain.adbPath
            let emulator = toolchain.emulatorPath
            adbPath = adb
            emulatorPath = emulator
            availableAVDs = toolchain.avds
            state = .locatingDevice

            let beforeDevices = try await Self.connectedEmulators(adbPath: adb)
            let device: AndroidEmulatorDevice
            var ownsDevice = false
            if let existing = Self.selectConnectedDevice(
                from: beforeDevices,
                preferredAVDName: payload?.avdName
            ) {
                device = existing
            } else {
                let avd = try Self.selectAVD(from: availableAVDs, preferredName: payload?.avdName)
                state = .booting(avd.displayName)
                try await launchHeadlessAVD(avd, emulatorPath: emulator)
                device = try await Self.waitForBootedEmulator(
                    adbPath: adb,
                    preferredAVDName: avd.name,
                    previousSerials: Set(beforeDevices.map(\.serial))
                )
                ownsDevice = true
            }

            if Task.isCancelled { return }
            selectedDevice = device
            ownsSelectedDevice = ownsDevice
            state = .capturing(device.displayName)
            await captureOnce(adbPath: adb, device: device, markRunning: true)
            startCaptureLoop(adbPath: adb, device: device)
        } catch {
            if !Task.isCancelled {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func launchHeadlessAVD(_ avd: AndroidAVDChoice, emulatorPath: String?) async throws {
        guard let emulatorPath else {
            throw AndroidSimulatorError.commandFailed("Android Emulator was not found. Install Android SDK Emulator and create at least one AVD.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulatorPath)
        process.arguments = [
            "-avd", avd.name,
            "-no-window",
            "-no-audio",
            "-no-boot-anim",
            "-no-metrics",
            "-gpu", "swiftshader_indirect"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        emulatorProcess = process
    }

    private func startCaptureLoop(adbPath: String, device: AndroidEmulatorDevice) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.pointerIsActive == true {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continue
                }
                await self?.captureOnce(adbPath: adbPath, device: device, markRunning: true)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func captureOnce(adbPath: String, device: AndroidEmulatorDevice, markRunning: Bool) async {
        guard !captureInFlight else { return }
        captureInFlight = true
        defer { captureInFlight = false }

        do {
            let png = try await Self.screenshot(adbPath: adbPath, serial: device.serial)
            if Task.isCancelled { return }
            guard let image = NSImage(data: png) else {
                throw AndroidSimulatorError.commandFailed("Emulator returned an unreadable screenshot.")
            }
            consecutiveCaptureFailures = 0
            frameImage = image
            statusLine = "\(device.displayName) · \(Int(image.size.width))x\(Int(image.size.height)) · embedded · interactive"
            if markRunning {
                state = .running(device.displayName)
            }
        } catch {
            if !Task.isCancelled {
                consecutiveCaptureFailures += 1
                if frameImage != nil && consecutiveCaptureFailures < 3 {
                    statusLine = "\(device.displayName) · display capture retrying · embedded · interactive"
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    nonisolated private static func locateADB() throws -> String {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let sdkRoots = [
            env["ANDROID_HOME"],
            env["ANDROID_SDK_ROOT"],
            "\(home)/Library/Android/sdk",
            "/opt/homebrew/share/android-commandlinetools",
            "/usr/local/share/android-commandlinetools"
        ].compactMap { $0 }
        let candidates =
            sdkRoots.map { "\($0)/platform-tools/adb" } +
            ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw AndroidSimulatorError.commandFailed("adb was not found. Install Android Platform Tools or set ANDROID_HOME.")
    }

    nonisolated private static func locateToolchain() async throws -> AndroidToolchain {
        try await Task.detached(priority: .utility) {
            let adb = try locateADB()
            let emulator = locateEmulator()
            return AndroidToolchain(adbPath: adb, emulatorPath: emulator, avds: loadAVDs(emulatorPath: emulator))
        }.value
    }

    nonisolated private static func locateEmulator() -> String? {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let sdkRoots = [
            env["ANDROID_HOME"],
            env["ANDROID_SDK_ROOT"],
            "\(home)/Library/Android/sdk",
            "/opt/homebrew/share/android-commandlinetools",
            "/usr/local/share/android-commandlinetools"
        ].compactMap { $0 }
        let candidates =
            sdkRoots.map { "\($0)/emulator/emulator" } +
            ["/opt/homebrew/bin/emulator", "/usr/local/bin/emulator"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    nonisolated private static func loadAVDs(emulatorPath: String?) -> [AndroidAVDChoice] {
        if let emulatorPath,
           let result = try? runToolSync(emulatorPath, ["-list-avds"]),
           result.status == 0 {
            let names = result.stdout
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !names.isEmpty {
                return names.map { AndroidAVDChoice(name: $0, config: configForAVD(named: $0)) }
                    .sorted()
            }
        }

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let avdRoot = URL(fileURLWithPath: "\(home)/.android/avd")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: avdRoot,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "avd" }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return AndroidAVDChoice(name: name, config: configForAVD(named: name))
            }
            .sorted()
    }

    nonisolated private static func configForAVD(named name: String) -> AndroidAVDConfig {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let path = "\(home)/.android/avd/\(name).avd/config.ini"
        guard let raw = try? String(contentsOfFile: path) else {
            return AndroidAVDConfig(width: nil, height: nil, deviceName: nil)
        }
        var values: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        return AndroidAVDConfig(
            width: values["hw.lcd.width"].flatMap(Int.init),
            height: values["hw.lcd.height"].flatMap(Int.init),
            deviceName: values["hw.device.name"]
        )
    }

    nonisolated private static func selectAVD(from avds: [AndroidAVDChoice], preferredName: String?) throws -> AndroidAVDChoice {
        if let preferredName, let preferred = avds.first(where: { $0.name == preferredName }) {
            return preferred
        }
        guard let avd = avds.first else {
            throw AndroidSimulatorError.noAVD
        }
        return avd
    }

    nonisolated private static func selectConnectedDevice(
        from devices: [AndroidEmulatorDevice],
        preferredAVDName: String?
    ) -> AndroidEmulatorDevice? {
        if let preferredAVDName {
            return devices.first(where: { $0.avdName == preferredAVDName && $0.state == "device" })
        }
        return devices.first(where: { $0.state == "device" })
    }

    nonisolated private static func connectedEmulators(adbPath: String) async throws -> [AndroidEmulatorDevice] {
        let result = try await runTool(adbPath, ["devices"])
        guard result.status == 0 else {
            throw AndroidSimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let serials = result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> (String, String)? in
                let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                guard parts.count >= 2, parts[0].hasPrefix("emulator-") else { return nil }
                return (parts[0], parts[1])
            }

        var devices: [AndroidEmulatorDevice] = []
        for (serial, state) in serials {
            let avdName = try? await avdName(adbPath: adbPath, serial: serial)
            devices.append(AndroidEmulatorDevice(serial: serial, state: state, avdName: avdName))
        }
        return devices
    }

    nonisolated private static func waitForBootedEmulator(
        adbPath: String,
        preferredAVDName: String?,
        previousSerials: Set<String>
    ) async throws -> AndroidEmulatorDevice {
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            let devices = try await connectedEmulatorStates(adbPath: adbPath)
            let sorted = devices.sorted { lhs, rhs in
                let lhsNew = !previousSerials.contains(lhs.serial)
                let rhsNew = !previousSerials.contains(rhs.serial)
                if lhsNew != rhsNew { return lhsNew && !rhsNew }
                return lhs.serial < rhs.serial
            }
            for device in sorted where device.state == "device" {
                let booted = try? await runTool(adbPath, [
                    "-s", device.serial,
                    "shell", "getprop", "sys.boot_completed"
                ])
                if booted?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                    _ = try? await runTool(adbPath, ["-s", device.serial, "shell", "input", "keyevent", "82"])
                    return AndroidEmulatorDevice(
                        serial: device.serial,
                        state: device.state,
                        avdName: preferredAVDName ?? device.avdName
                    )
                }
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw AndroidSimulatorError.commandFailed("Timed out waiting for the Android emulator to boot.")
    }

    nonisolated private static func connectedEmulatorStates(adbPath: String) async throws -> [AndroidEmulatorDevice] {
        let result = try await runTool(adbPath, ["devices"], timeout: 8)
        guard result.status == 0 else {
            throw AndroidSimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line -> AndroidEmulatorDevice? in
                let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                guard parts.count >= 2, parts[0].hasPrefix("emulator-") else { return nil }
                return AndroidEmulatorDevice(serial: parts[0], state: parts[1], avdName: nil)
            }
    }

    nonisolated private static func avdName(adbPath: String, serial: String) async throws -> String? {
        let result = try await runTool(adbPath, ["-s", serial, "emu", "avd", "name"])
        guard result.status == 0 else { return nil }
        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "OK" }
    }

    nonisolated private static func screenshot(adbPath: String, serial: String) async throws -> Data {
        let result = try await runTool(adbPath, ["-s", serial, "exec-out", "screencap", "-p"], captureBinary: true)
        guard result.status == 0 else {
            throw AndroidSimulatorError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdoutData
    }

    nonisolated private static func runTool(
        _ executable: String,
        _ arguments: [String],
        captureBinary: Bool = false,
        timeout: TimeInterval = 20
    ) async throws -> AndroidToolResult {
        try await Task.detached(priority: .userInitiated) {
            try Self.runToolSync(executable, arguments, captureBinary: captureBinary, timeout: timeout)
        }.value
    }

    nonisolated private static func runToolSync(
        _ executable: String,
        _ arguments: [String],
        captureBinary: Bool = false,
        timeout: TimeInterval = 20
    ) throws -> AndroidToolResult {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let token = UUID().uuidString
        let stdoutURL = tempDir.appendingPathComponent("clawix-android-\(token).stdout")
        let stderrURL = tempDir.appendingPathComponent("clawix-android-\(token).stderr")
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        let stdoutFD = open(stdoutURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard stdoutFD >= 0 else {
            throw AndroidSimulatorError.commandFailed("Could not create Android stdout capture file.")
        }
        let stderrFD = open(stderrURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard stderrFD >= 0 else {
            close(stdoutFD)
            throw AndroidSimulatorError.commandFailed("Could not create Android stderr capture file.")
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdoutFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrFD, STDERR_FILENO)

        var pid: pid_t = 0
        var cArguments = ([executable] + arguments).map { strdup($0) }
        cArguments.append(nil)
        defer {
            for pointer in cArguments where pointer != nil {
                free(pointer)
            }
        }
        let environmentStrings: [String] = ProcessInfo.processInfo.environment.map { key, value in
            "\(key)=\(value)"
        }
        var cEnvironment: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) }
        cEnvironment.append(nil)
        defer {
            for pointer in cEnvironment where pointer != nil {
                free(pointer)
            }
        }

        let spawnStatus = cArguments.withUnsafeMutableBufferPointer { buffer -> Int32 in
            cEnvironment.withUnsafeMutableBufferPointer { envBuffer -> Int32 in
                posix_spawn(&pid, executable, &actions, nil, buffer.baseAddress, envBuffer.baseAddress)
            }
        }
        close(stdoutFD)
        close(stderrFD)

        guard spawnStatus == 0 else {
            throw AndroidSimulatorError.commandFailed(String(cString: strerror(spawnStatus)))
        }

        var waitStatus: Int32 = 0
        func pollUntil(_ deadline: Date) throws -> Bool {
            while Date() < deadline {
                let result = waitpid(pid, &waitStatus, WNOHANG)
                if result == pid { return true }
                if result == -1 {
                    if errno == EINTR { continue }
                    throw AndroidSimulatorError.commandFailed(String(cString: strerror(errno)))
                }
                usleep(20_000)
            }
            return false
        }

        if try !pollUntil(Date().addingTimeInterval(timeout)) {
            kill(pid, SIGTERM)
            if try !pollUntil(Date().addingTimeInterval(1)) {
                kill(pid, SIGKILL)
                _ = try? pollUntil(Date().addingTimeInterval(1))
            }
            throw AndroidSimulatorError.commandFailed("Android command timed out: \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))")
        }

        let outData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let errData = (try? Data(contentsOf: stderrURL)) ?? Data()
        let out = captureBinary ? "" : (String(data: outData, encoding: .utf8) ?? "")
        let err = String(data: errData, encoding: .utf8) ?? ""
        let terminationStatus: Int32
        if waitStatus & 0x7f == 0 {
            terminationStatus = (waitStatus >> 8) & 0xff
        } else {
            terminationStatus = 128 + (waitStatus & 0x7f)
        }
        return AndroidToolResult(
            status: terminationStatus,
            stdout: out,
            stdoutData: outData,
            stderr: err
        )
    }
}

private final class AndroidPipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}

private struct AndroidToolResult {
    let status: Int32
    let stdout: String
    let stdoutData: Data
    let stderr: String
}

private struct AndroidToolchain {
    let adbPath: String
    let emulatorPath: String?
    let avds: [AndroidAVDChoice]
}

private struct AndroidEmulatorDevice: Equatable {
    let serial: String
    let state: String
    let avdName: String?

    var displayName: String {
        if let avdName, !avdName.isEmpty { return AndroidDeviceNameFormatter.displayName(for: avdName) }
        return serial
    }
}

private struct AndroidAVDConfig: Equatable {
    let width: Int?
    let height: Int?
    let deviceName: String?
}

private struct AndroidAVDChoice: Identifiable, Equatable, Comparable {
    let id: String
    let name: String
    let config: AndroidAVDConfig

    init(name: String, config: AndroidAVDConfig) {
        self.id = name
        self.name = name
        self.config = config
    }

    var displayName: String {
        AndroidDeviceNameFormatter.displayName(
            for: (config.deviceName?.isEmpty == false ? config.deviceName : nil) ?? name
        )
    }

    var menuTitle: String {
        if let width = config.width, let height = config.height {
            return "\(displayName) · \(width)x\(height)"
        }
        return displayName
    }

    static func < (lhs: AndroidAVDChoice, rhs: AndroidAVDChoice) -> Bool {
        let lhsTablet = lhs.isTablet
        let rhsTablet = rhs.isTablet
        if lhsTablet != rhsTablet { return !lhsTablet && rhsTablet }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private var isTablet: Bool {
        let lower = "\(name) \(config.deviceName ?? "")".lowercased()
        if lower.contains("tablet") || lower.contains("fold") { return true }
        if let width = config.width, let height = config.height {
            return max(width, height) >= 1800 && min(width, height) >= 1200
        }
        return false
    }
}

private enum AndroidDeviceNameFormatter {
    static func displayName(for raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map(formatToken)
            .joined(separator: " ")
    }

    private static func formatToken(_ token: Substring) -> String {
        let raw = String(token)
        let lower = raw.lowercased()
        switch lower {
        case "avd": return "AVD"
        case "api": return "API"
        case "pixel": return "Pixel"
        case "nexus": return "Nexus"
        case "tablet": return "Tablet"
        default:
            if lower.allSatisfy(\.isNumber) { return lower }
            if lower.count <= 2 { return lower.uppercased() }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
    }
}

private enum AndroidSimulatorError: LocalizedError {
    case noAVD
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAVD:
            return "No Android Virtual Devices were found. Create phone and tablet AVDs with Android Studio or avdmanager."
        case .commandFailed(let message):
            return message.isEmpty ? "Android command failed." : message
        }
    }
}
