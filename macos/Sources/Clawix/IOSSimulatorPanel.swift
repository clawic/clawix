import SwiftUI
import AppKit
import ClawixSimulatorKitShim

/// In-app iOS simulator surface for the right sidebar.
///
/// Apple does not expose a public NSView for Simulator.app. This panel uses
/// CoreSimulator as the backend and renders the booted device framebuffer in a
/// Clawix-owned view via `simctl io screenshot`, so the visible simulator is
/// part of this window and follows the sidebar when it is hidden, shown, or
/// resized.
struct IOSSimulatorPanel: View {
    let payload: SidebarItem.IOSSimulatorPayload
    var onPayloadChange: (SidebarItem.IOSSimulatorPayload) -> Void = { _ in }
    @StateObject private var controller = IOSSimulatorFramebufferController()

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
            IOSSimulatorIconButton(systemName: "arrow.clockwise", enabled: controller.canRefresh) {
                controller.refreshNow()
            }
            .accessibilityLabel("Refresh simulator")

            IOSSimulatorIconButton(systemName: "house", enabled: controller.canControl) {
                controller.goHome()
            }
            .accessibilityLabel("Home")

            IOSSimulatorIconButton(systemName: "safari", enabled: controller.canControl) {
                controller.openURL("https://www.apple.com")
            }
            .accessibilityLabel("Open Safari")

            IOSSimulatorIconButton(systemName: "sun.max", enabled: controller.canControl) {
                controller.setAppearance(.light)
            }
            .accessibilityLabel("Light appearance")

            IOSSimulatorIconButton(systemName: "moon", enabled: controller.canControl) {
                controller.setAppearance(.dark)
            }
            .accessibilityLabel("Dark appearance")

            Menu {
                ForEach(controller.availableDevices) { device in
                    Button(device.menuTitle) {
                        controller.selectDevice(device)
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
            .disabled(controller.availableDevices.isEmpty)
            .accessibilityLabel("Select iOS simulator device")

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
        if let display = controller.nativeDisplay {
            IOSSimulatorNativeDisplayView(display: display)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
        } else if let image = controller.frameImage {
            GeometryReader { proxy in
                let screenAspect = max(0.1, image.size.width / max(1, image.size.height))
                IOSSimulatorFrameSurface(
                    image: image,
                    aspectRatio: screenAspect,
                    stageSize: proxy.size
                ) { phase, point in
                    controller.handlePointer(phase: phase, devicePoint: point)
                }
            }
        } else {
            VStack(spacing: 10) {
                LucideIcon(.appWindow, size: 28)
                    .foregroundColor(Color(white: 0.32))
                Text("Waiting for iOS display")
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
                .buttonStyle(IOSSimulatorPanelButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: 360, alignment: .leading)
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

private struct IOSSimulatorFrameSurface: View {
    let image: NSImage
    let aspectRatio: CGFloat
    let stageSize: CGSize
    let onPointer: (IOSSimulatorPointerPhase, CGPoint) -> Void

    @State private var isDragging = false

    var body: some View {
        let screenRect = displayRect(in: stageSize)
        let chromeRect = screenRect.insetBy(dx: -11, dy: -11)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(white: 0.025))
                .frame(width: chromeRect.width, height: chromeRect.height)
                .position(x: chromeRect.midX, y: chromeRect.midY)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.9)
                        .frame(width: chromeRect.width, height: chromeRect.height)
                        .position(x: chromeRect.midX, y: chromeRect.midY)
                )
                .shadow(color: .black.opacity(0.48), radius: 18, x: 0, y: 12)

            IOSSimulatorFramebufferView(image: image, onPointer: onPointer)
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

private struct IOSSimulatorFramebufferView: NSViewRepresentable {
    let image: NSImage
    let onPointer: (IOSSimulatorPointerPhase, CGPoint) -> Void

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
        var onPointer: (IOSSimulatorPointerPhase, CGPoint) -> Void

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        init(image: NSImage, onPointer: @escaping (IOSSimulatorPointerPhase, CGPoint) -> Void) {
            self.image = image
            self.imageSize = image.size
            self.onPointer = onPointer
            super.init(frame: .zero)
            wantsLayer = true
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Embedded iOS Simulator framebuffer")
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
            let yFromTop = (clampedY - bounds.minY) / max(1, bounds.height) * imageSize.height
            return CGPoint(x: x, y: yFromTop)
        }
    }
}

private enum IOSSimulatorPointerPhase {
    case began
    case moved
    case ended
}

struct IOSSimulatorNativeDisplayDescriptor: Equatable {
    let deviceUDID: String
    let deviceName: String
    let aspectRatio: CGFloat
}

private struct IOSSimulatorNativeDisplayView: NSViewRepresentable {
    let display: IOSSimulatorNativeDisplayDescriptor

    func makeNSView(context: Context) -> NativeDisplayHostView {
        let view = NativeDisplayHostView()
        view.configure(display: display)
        return view
    }

    func updateNSView(_ nsView: NativeDisplayHostView, context: Context) {
        nsView.configure(display: display)
    }

    final class NativeDisplayHostView: NSView {
        private typealias ObjCInitScreenFn = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> AnyObject?
        private typealias ObjCInitFrameFn = @convention(c) (AnyObject, Selector, CGRect) -> AnyObject?

        private var configuredUDID: String?
        private var configuredAspectRatio: CGFloat = 1206.0 / 2622.0
        private var displayView: NSView?
        private var retainedScreen: AnyObject?
        private var retainedDisplay: AnyObject?

        private static let simulatorKitPath = "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
        private static let coreSimulatorPath = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
        private static let mainScreenID: UInt32 = 1
        private static let allInputs: UInt = 7

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel("Embedded iOS Simulator")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configure(display: IOSSimulatorNativeDisplayDescriptor) {
            configuredAspectRatio = display.aspectRatio
            if configuredUDID == display.deviceUDID {
                needsLayout = true
                return
            }
            configuredUDID = display.deviceUDID
            displayView?.removeFromSuperview()
            displayView = nil
            retainedScreen = nil
            retainedDisplay = nil

            guard
                Self.loadFramework(Self.coreSimulatorPath) != nil,
                let simulatorKit = Self.loadFramework(Self.simulatorKitPath),
                let simDevice = Self.resolveSimDevice(udid: display.deviceUDID),
                let screen = Self.createScreen(device: simDevice),
                let view = Self.createDisplayView(),
                let connect = dlsym(simulatorKit, "$s12SimulatorKit14SimDisplayViewC7connect6screen6inputsyAA0C12DeviceScreenC_AC0j5InputI0VtKFTj")
            else {
                return
            }

            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            addSubview(view)
            displayView = view
            retainedScreen = screen
            retainedDisplay = view
            needsLayout = true
            ClawixSimKitConnectDisplayView(
                connect,
                Unmanaged.passUnretained(view).toOpaque(),
                Unmanaged.passUnretained(screen).toOpaque(),
                Self.allInputs
            )
        }

        override func layout() {
            super.layout()
            guard let displayView else { return }
            let maxRect = bounds.insetBy(dx: 2, dy: 2)
            let aspect = max(0.1, configuredAspectRatio)
            var width = min(maxRect.width, maxRect.height * aspect)
            var height = width / aspect
            if height > maxRect.height {
                height = maxRect.height
                width = height * aspect
            }
            displayView.frame = CGRect(
                x: maxRect.midX - width / 2,
                y: maxRect.midY - height / 2,
                width: width,
                height: height
            )
        }

        private static func createDisplayView() -> NSView? {
            guard
                let displayClass = NSClassFromString("SimulatorKit.SimDisplayView") as AnyObject?,
                let allocated = displayClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
            else {
                return nil
            }
            let initFrame = unsafeBitCast(objcMessageSymbol, to: ObjCInitFrameFn.self)
            return initFrame(
                allocated,
                NSSelectorFromString("initWithFrame:"),
                CGRect(x: 0, y: 0, width: 393, height: 852)
            ) as? NSView
        }

        private static func loadFramework(_ path: String) -> UnsafeMutableRawPointer? {
            if let handle = dlopen(path, RTLD_NOLOAD | RTLD_NOW | RTLD_GLOBAL) {
                return handle
            }
            return dlopen(path, RTLD_NOW | RTLD_GLOBAL)
        }

        private static func resolveSimDevice(udid: String) -> AnyObject? {
            guard
                let contextClass = NSClassFromString("SimServiceContext") as? NSObject.Type,
                let context = contextClass.perform(
                    NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"),
                    with: "/Applications/Xcode.app/Contents/Developer" as NSString,
                    with: nil
                )?.takeUnretainedValue() as? NSObject
            else {
                return nil
            }

            _ = context.perform(NSSelectorFromString("connectWithError:"), with: nil)
            guard
                let set = context.perform(NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?
                    .takeUnretainedValue() as? NSObject,
                let devices = set.value(forKey: "devices") as? NSArray
            else {
                return nil
            }

            for case let device as NSObject in devices {
                guard
                    let uuid = device.perform(NSSelectorFromString("UDID"))?.takeUnretainedValue() as? NSUUID,
                    uuid.uuidString == udid
                else {
                    continue
                }
                return device
            }
            return nil
        }

        private static func createScreen(device: AnyObject) -> AnyObject? {
            guard
                let screenClass = NSClassFromString("SimulatorKit.SimDeviceScreen") as AnyObject?,
                let allocated = screenClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
            else {
                return nil
            }

            let initScreen = unsafeBitCast(objcMessageSymbol, to: ObjCInitScreenFn.self)
            return initScreen(
                allocated,
                NSSelectorFromString("initWithDevice:screenID:"),
                device,
                mainScreenID
            )
        }
    }
}

private struct IOSSimulatorIconButton: View {
    let systemName: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(enabled ? Color(white: hovered ? 0.95 : 0.72) : Color(white: 0.32))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovered && enabled ? Color.white.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

private struct IOSSimulatorPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BodyFont.system(size: 11.5, wght: 600))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.11))
            )
    }
}

@MainActor
private final class IOSSimulatorFramebufferController: ObservableObject {
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

    fileprivate func handlePointer(phase: IOSSimulatorPointerPhase, devicePoint: CGPoint) {
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

private struct ToolResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

private struct SimDevice: Equatable {
    let runtime: String
    let name: String
    let udid: String
    let state: String

    var isPhone: Bool { name.localizedCaseInsensitiveContains("iPhone") }
}

private struct IOSSimulatorDeviceChoice: Identifiable, Equatable {
    let id: String
    let udid: String
    let name: String
    let runtime: String
    let isBooted: Bool

    init(device: SimDevice) {
        self.id = device.udid
        self.udid = device.udid
        self.name = device.name
        self.runtime = device.runtime
        self.isBooted = device.state == "Booted"
    }

    var menuTitle: String {
        let suffix = isBooted ? " · booted" : ""
        return "\(name)\(suffix)"
    }
}

private struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]
}

private struct SimctlDevice: Decodable {
    let name: String
    let udid: String
    let state: String
}

@MainActor
private final class IOSSimulatorHIDBridge {
    let device: SimDevice

    private typealias ObjCInitScreenFn = @convention(c) (AnyObject, Selector, AnyObject, UInt32) -> AnyObject?
    private typealias HIDTargetForScreenFn = @convention(c) (AnyObject) -> UInt64
    private typealias HIDMouseMessageFn = @convention(c) (
        UnsafePointer<CGPoint>,
        UnsafePointer<CGPoint>,
        UInt64,
        UInt,
        CGSize,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias HIDNoArgMessageFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias HIDPointerEventMessageFn = @convention(c) (UnsafeMutableRawPointer, UInt64) -> UnsafeMutableRawPointer?
    private typealias HIDSendMessageFn = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutableRawPointer?,
        Bool,
        AnyObject?,
        AnyObject?
    ) -> Void
    private typealias IOHIDCreateDigitizerEventFn = @convention(c) (
        CFAllocator?,
        UInt64,
        UInt32,
        UInt32,
        UInt32,
        UInt32,
        UInt32,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        Bool,
        Bool,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias IOHIDCreateDigitizerFingerEventFn = @convention(c) (
        CFAllocator?,
        UInt64,
        UInt32,
        UInt32,
        UInt32,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        CGFloat,
        Bool,
        Bool,
        UInt32
    ) -> UnsafeMutableRawPointer?
    private typealias IOHIDAppendEventFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32) -> Void
    private typealias IOHIDSetIntegerValueFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Int) -> Void
    private typealias IOHIDSetFloatValueFn = @convention(c) (UnsafeMutableRawPointer, UInt32, CGFloat) -> Void

    private static let simulatorKitPath = "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
    private static let coreSimulatorPath = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
    private static let ioKitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"
    private static let mainScreenID: UInt32 = 1
    private static let digitizerEventRange: UInt32 = 1 << 0
    private static let digitizerEventTouch: UInt32 = 1 << 1
    private static let digitizerEventPosition: UInt32 = 1 << 2
    private static let digitizerTransducerHand: UInt32 = 3
    private static let digitizerFieldMajorRadius: UInt32 = 0xB0014
    private static let digitizerFieldMinorRadius: UInt32 = 0xB0015
    private static let digitizerFieldDisplayIntegrated: UInt32 = 0xB0019

    private let client: AnyObject
    private let target: UInt64
    let screenSize: CGSize
    private let mouseMessage: HIDMouseMessageFn
    private let pointerEventMessage: HIDPointerEventMessageFn?
    private let createDigitizerEvent: IOHIDCreateDigitizerEventFn?
    private let createDigitizerFingerEvent: IOHIDCreateDigitizerFingerEventFn?
    private let appendHIDEvent: IOHIDAppendEventFn?
    private let setHIDIntegerValue: IOHIDSetIntegerValueFn?
    private let setHIDFloatValue: IOHIDSetFloatValueFn?
    private let sendMessage: HIDSendMessageFn

    init?(device: SimDevice) {
        self.device = device
        _ = Self.loadFramework(Self.coreSimulatorPath)
        let ioKit = Self.loadFramework(Self.ioKitPath)
        guard
            let simulatorKit = Self.loadFramework(Self.simulatorKitPath),
            let simDevice = Self.resolveSimDevice(udid: device.udid),
            let screen = Self.createScreen(device: simDevice),
            let client = Self.createClient(device: simDevice),
            let targetForScreenSymbol = dlsym(simulatorKit, "IndigoHIDTargetForScreen"),
            let mouseMessageSymbol = dlsym(simulatorKit, "IndigoHIDMessageForMouseNSEvent"),
            let createMouseSymbol = dlsym(simulatorKit, "IndigoHIDMessageToCreateMouseService"),
            let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
        else {
            return nil
        }

        let targetForScreen = unsafeBitCast(targetForScreenSymbol, to: HIDTargetForScreenFn.self)
        let createMouseMessage = unsafeBitCast(createMouseSymbol, to: HIDNoArgMessageFn.self)
        self.mouseMessage = unsafeBitCast(mouseMessageSymbol, to: HIDMouseMessageFn.self)
        self.pointerEventMessage = dlsym(simulatorKit, "IndigoHIDMessageForPointerEventFromHIDEventRef")
            .map { unsafeBitCast($0, to: HIDPointerEventMessageFn.self) }
        self.createDigitizerEvent = ioKit.flatMap { dlsym($0, "IOHIDEventCreateDigitizerEvent") }
            .map { unsafeBitCast($0, to: IOHIDCreateDigitizerEventFn.self) }
        self.createDigitizerFingerEvent = ioKit.flatMap { dlsym($0, "IOHIDEventCreateDigitizerFingerEvent") }
            .map { unsafeBitCast($0, to: IOHIDCreateDigitizerFingerEventFn.self) }
        self.appendHIDEvent = ioKit.flatMap { dlsym($0, "IOHIDEventAppendEvent") }
            .map { unsafeBitCast($0, to: IOHIDAppendEventFn.self) }
        self.setHIDIntegerValue = ioKit.flatMap { dlsym($0, "IOHIDEventSetIntegerValue") }
            .map { unsafeBitCast($0, to: IOHIDSetIntegerValueFn.self) }
        self.setHIDFloatValue = ioKit.flatMap { dlsym($0, "IOHIDEventSetFloatValue") }
            .map { unsafeBitCast($0, to: IOHIDSetFloatValueFn.self) }
        self.sendMessage = unsafeBitCast(objcMessageSymbol, to: HIDSendMessageFn.self)
        self.client = client
        self.target = targetForScreen(screen)
        self.screenSize = CGSize(width: 1206, height: 2622)

        send(createMouseMessage())
    }

    enum TouchPhase {
        case began
        case moved
        case ended
    }

    func sendTouchEvent(phase: TouchPhase, point: CGPoint, screenSize: CGSize) {
        guard
            let pointerEventMessage,
            let createDigitizerEvent,
            let createDigitizerFingerEvent,
            let appendHIDEvent,
            let setHIDIntegerValue,
            let setHIDFloatValue
        else {
            return
        }

        let touchX = min(max(point.x, 0), max(1, screenSize.width))
        let touchY = min(max(point.y, 0), max(1, screenSize.height))
        let mask: UInt32
        let isTouching: Bool
        switch phase {
        case .began:
            mask = Self.digitizerEventRange | Self.digitizerEventTouch | Self.digitizerEventPosition
            isTouching = true
        case .moved:
            mask = Self.digitizerEventPosition
            isTouching = true
        case .ended:
            mask = Self.digitizerEventRange | Self.digitizerEventTouch
            isTouching = false
        }

        guard
            let parent = createDigitizerEvent(
                kCFAllocatorDefault,
                mach_absolute_time(),
                Self.digitizerTransducerHand,
                0,
                0,
                mask,
                0,
                0,
                0,
                0,
                0,
                0,
                isTouching,
                isTouching,
                0
            ),
            let finger = createDigitizerFingerEvent(
                kCFAllocatorDefault,
                mach_absolute_time(),
                1,
                1,
                mask,
                touchX,
                touchY,
                0,
                isTouching ? 0.5 : 0,
                0,
                isTouching,
                isTouching,
                0
            )
        else {
            return
        }

        setHIDIntegerValue(parent, Self.digitizerFieldDisplayIntegrated, 1)
        setHIDFloatValue(finger, Self.digitizerFieldMajorRadius, 0.04)
        setHIDFloatValue(finger, Self.digitizerFieldMinorRadius, 0.04)
        appendHIDEvent(parent, finger, 0)
        send(pointerEventMessage(parent, target))
    }

    func sendMouseEvent(type: NSEvent.EventType, point: CGPoint, previousPoint: CGPoint, screenSize: CGSize) {
        let width = max(1, screenSize.width)
        let height = max(1, screenSize.height)
        var current = CGPoint(
            x: min(max(point.x / width, 0), 1),
            y: 1 - min(max(point.y / height, 0), 1)
        )
        var previous = CGPoint(
            x: min(max(previousPoint.x / width, 0), 1),
            y: 1 - min(max(previousPoint.y / height, 0), 1)
        )
        let unitScreenSize = CGSize(width: 1, height: 1)
        let message = mouseMessage(
            &current,
            &previous,
            target,
            UInt(type.rawValue),
            unitScreenSize,
            0
        )
        send(message)
    }

    private func send(_ message: UnsafeMutableRawPointer?) {
        guard let message else { return }
        sendMessage(
            client,
            NSSelectorFromString("sendWithMessage:freeWhenDone:completionQueue:completion:"),
            message,
            true,
            nil,
            nil
        )
    }

    private static func loadFramework(_ path: String) -> UnsafeMutableRawPointer? {
        if let handle = dlopen(path, RTLD_NOLOAD | RTLD_NOW | RTLD_GLOBAL) {
            return handle
        }
        return dlopen(path, RTLD_NOW | RTLD_GLOBAL)
    }

    private static func resolveSimDevice(udid: String) -> AnyObject? {
        guard
            let contextClass = NSClassFromString("SimServiceContext") as? NSObject.Type,
            let context = contextClass.perform(
                NSSelectorFromString("sharedServiceContextForDeveloperDir:error:"),
                with: "/Applications/Xcode.app/Contents/Developer" as NSString,
                with: nil
            )?.takeUnretainedValue() as? NSObject
        else {
            return nil
        }

        _ = context.perform(NSSelectorFromString("connectWithError:"), with: nil)
        guard
            let set = context.perform(NSSelectorFromString("defaultDeviceSetWithError:"), with: nil)?
                .takeUnretainedValue() as? NSObject,
            let devices = set.value(forKey: "devices") as? NSArray
        else {
            return nil
        }

        for case let device as NSObject in devices {
            guard
                let uuid = device.perform(NSSelectorFromString("UDID"))?.takeUnretainedValue() as? NSUUID,
                uuid.uuidString == udid
            else {
                continue
            }
            return device
        }
        return nil
    }

    private static func createScreen(device: AnyObject) -> AnyObject? {
        guard
            let screenClass = NSClassFromString("SimulatorKit.SimDeviceScreen") as AnyObject?,
            let allocated = screenClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
            let objcMessageSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
        else {
            return nil
        }

        let initScreen = unsafeBitCast(objcMessageSymbol, to: ObjCInitScreenFn.self)
        return initScreen(
            allocated,
            NSSelectorFromString("initWithDevice:screenID:"),
            device,
            mainScreenID
        )
    }

    private static func createClient(device: AnyObject) -> AnyObject? {
        guard
            let clientClass = NSClassFromString("SimulatorKit.SimDeviceLegacyHIDClient") as AnyObject?,
            let allocated = clientClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
        else {
            return nil
        }
        return allocated
            .perform(NSSelectorFromString("initWithDevice:error:"), with: device, with: nil)?
            .takeUnretainedValue()
    }
}

private enum SimulatorError: LocalizedError {
    case noDevice
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No available iPhone simulator was found. Install an iOS runtime in Xcode."
        case .commandFailed(let message):
            return message.isEmpty ? "The simulator command failed." : message
        }
    }
}
