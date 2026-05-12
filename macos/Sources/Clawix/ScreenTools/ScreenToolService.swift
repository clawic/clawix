import AppKit
import UniformTypeIdentifiers
import Vision

@MainActor
final class ScreenToolService: ObservableObject {
    static let shared = ScreenToolService()

    @Published private(set) var lastCaptureURL: URL?
    @Published private(set) var pins: [ScreenToolPinWindow] = []
    @Published private(set) var overlays: [ScreenToolOverlayWindow] = []

    private init() {}

    enum CaptureMode {
        case area
        case fullscreen
        case window
        case selfTimer
    }

    enum CaptureAction: String, CaseIterable, Identifiable {
        case quickOverlay
        case copy
        case save
        case pin
        case annotate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quickOverlay: return "Show Quick Access Overlay"
            case .copy:         return "Copy file to clipboard"
            case .save:         return "Save"
            case .pin:          return "Pin to the screen"
            case .annotate:     return "Open Markup"
            }
        }
    }

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png
        case jpg
        case tiff
        case pdf

        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    func captureArea() {
        runCapture(mode: .area)
    }

    func captureFullscreen() {
        runCapture(mode: .fullscreen)
    }

    func captureWindow() {
        runCapture(mode: .window)
    }

    func captureSelfTimer() {
        runCapture(mode: .selfTimer)
    }

    func recordScreen() {
        let url = outputURL(prefix: "recording", extension: "mov")
        Self.runScreencapture(args: ["-v", "-i", "-J", "video", url.path]) { [weak self] result in
            Task { @MainActor in
                guard result == .success, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show("Recording cancelled", icon: .warning)
                    return
                }
                self?.lastCaptureURL = url
                ToastCenter.shared.show("Recording saved")
            }
        }
    }

    func captureText(keepLineBreaks: Bool = ScreenToolSettings.keepTextLineBreaks) {
        let url = outputURL(prefix: "text", extension: "png")
        Self.runScreencapture(args: interactiveArgs(mode: .area, output: url)) { result in
            Task { @MainActor in
                guard result == .success, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show("Text capture cancelled", icon: .warning)
                    return
                }
                await Self.recognizeText(in: url, keepLineBreaks: keepLineBreaks)
            }
        }
    }

    func pinLastCapture() {
        guard let url = lastCaptureURL else {
            ToastCenter.shared.show("No recent capture to pin", icon: .warning)
            return
        }
        pin(url: url)
    }

    func chooseAndPinImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.pin(url: url) }
        }
    }

    func closeAllPins() {
        pins.forEach { $0.close() }
        pins.removeAll()
        ToastCenter.shared.show("Pins closed")
    }

    func closeAllOverlays() {
        overlays.forEach { $0.close() }
        overlays.removeAll()
        ToastCenter.shared.show("Overlays closed")
    }

    func openCaptureHistory() {
        let dir = ScreenToolSettings.exportDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    func openLastCaptureInMarkup() {
        guard let url = lastCaptureURL else {
            ToastCenter.shared.show("No recent capture to open", icon: .warning)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runCapture(mode: CaptureMode) {
        let url = outputURL(prefix: outputPrefix(for: mode), extension: ScreenToolSettings.imageFormat.rawValue)
        Self.runScreencapture(args: interactiveArgs(mode: mode, output: url)) { [weak self] result in
            Task { @MainActor in
                guard result == .success, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show("Capture cancelled", icon: .warning)
                    return
                }
                self?.lastCaptureURL = url
                self?.handleCapture(url)
            }
        }
    }

    private func handleCapture(_ url: URL) {
        switch ScreenToolSettings.afterCaptureAction {
        case .quickOverlay:
            lastCaptureURL = url
            showOverlay(for: url)
        case .copy:
            copyFileAndImage(url)
        case .save:
            ToastCenter.shared.show("Capture saved")
        case .pin:
            pin(url: url)
        case .annotate:
            NSWorkspace.shared.open(url)
            ToastCenter.shared.show("Capture opened")
        }
    }

    func copyFileAndImage(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image, url as NSURL])
        } else {
            pasteboard.writeObjects([url as NSURL])
        }
        ToastCenter.shared.show("Capture copied")
    }

    func pin(url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            ToastCenter.shared.show("Could not pin image", icon: .error)
            return
        }
        let pin = ScreenToolPinWindow(image: image) { [weak self] window in
            Task { @MainActor in self?.pins.removeAll { $0 === window } }
        }
        pins.append(pin)
        pin.show()
        ToastCenter.shared.show("Pinned to screen")
    }

    func reveal(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func showOverlay(for url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            ToastCenter.shared.show("Capture ready")
            return
        }
        let overlay = ScreenToolOverlayWindow(
            image: image,
            url: url,
            copy: { [weak self] in self?.copyFileAndImage(url) },
            pin: { [weak self] in self?.pin(url: url) },
            open: { NSWorkspace.shared.open(url) },
            reveal: { [weak self] in self?.reveal(url: url) },
            closeOverlay: { [weak self] window in
                Task { @MainActor in self?.overlays.removeAll { $0 === window } }
            }
        )
        overlays.append(overlay)
        overlay.show()
        ToastCenter.shared.show("Capture ready")
    }

    private func outputURL(prefix: String, extension ext: String) -> URL {
        let dir = ScreenToolSettings.exportDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ScreenToolService.timestampFormatter.string(from: Date())
        return dir.appendingPathComponent("\(prefix)-\(stamp).\(ext)")
    }

    private func outputPrefix(for mode: CaptureMode) -> String {
        switch mode {
        case .area:       return "area"
        case .fullscreen: return "fullscreen"
        case .window:     return "window"
        case .selfTimer:  return "timer"
        }
    }

    private func interactiveArgs(mode: CaptureMode, output url: URL) -> [String] {
        var args: [String] = []
        if !ScreenToolSettings.playSounds { args.append("-x") }
        args.append(contentsOf: ["-t", ScreenToolSettings.imageFormat.rawValue])
        switch mode {
        case .area:
            args.append(contentsOf: ["-i", "-s"])
        case .fullscreen:
            if ScreenToolSettings.includeCursor { args.append("-C") }
        case .window:
            args.append(contentsOf: ["-i", "-w"])
            if !ScreenToolSettings.captureWindowShadow { args.append("-o") }
        case .selfTimer:
            args.append(contentsOf: ["-T", String(ScreenToolSettings.selfTimerSeconds)])
            if ScreenToolSettings.includeCursor { args.append("-C") }
        }
        args.append(url.path)
        return args
    }

    private static func runScreencapture(args: [String], completion: @escaping (ProcessResult) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = args
        task.terminationHandler = { task in
            DispatchQueue.main.async {
                completion(task.terminationStatus == 0 ? .success : .failed)
            }
        }
        do {
            try task.run()
        } catch {
            DispatchQueue.main.async { completion(.failed) }
        }
    }

    private static func recognizeText(in url: URL, keepLineBreaks: Bool) async {
        guard let cgImage = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ToastCenter.shared.show("Could not read captured image", icon: .error)
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = ScreenToolSettings.autoDetectTextLanguage

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = keepLineBreaks ? lines.joined(separator: "\n") : lines.joined(separator: " ")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            ToastCenter.shared.show(text.isEmpty ? "No text found" : "Text copied")
        } catch {
            ToastCenter.shared.show("Text recognition failed", icon: .error)
        }
    }

    private enum ProcessResult {
        case success
        case failed
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        return formatter
    }()
}

enum ScreenToolSettings {
    private static let defaults = UserDefaults.standard

    static let exportDirectoryKey = "clawix.screenTools.exportDirectory"
    static let afterCaptureActionKey = "clawix.screenTools.afterCaptureAction"
    static let imageFormatKey = "clawix.screenTools.imageFormat"
    static let selfTimerSecondsKey = "clawix.screenTools.selfTimerSeconds"
    static let playSoundsKey = "clawix.screenTools.playSounds"
    static let includeCursorKey = "clawix.screenTools.includeCursor"
    static let captureWindowShadowKey = "clawix.screenTools.captureWindowShadow"
    static let keepTextLineBreaksKey = "clawix.screenTools.keepTextLineBreaks"
    static let autoDetectTextLanguageKey = "clawix.screenTools.autoDetectTextLanguage"

    static var exportDirectoryURL: URL {
        if let path = defaults.string(forKey: exportDirectoryKey), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    static var afterCaptureAction: ScreenToolService.CaptureAction {
        let raw = defaults.string(forKey: afterCaptureActionKey) ?? ScreenToolService.CaptureAction.quickOverlay.rawValue
        return ScreenToolService.CaptureAction(rawValue: raw) ?? .quickOverlay
    }

    static var imageFormat: ScreenToolService.ImageFormat {
        let raw = defaults.string(forKey: imageFormatKey) ?? ScreenToolService.ImageFormat.png.rawValue
        return ScreenToolService.ImageFormat(rawValue: raw) ?? .png
    }

    static var selfTimerSeconds: Int {
        let value = defaults.integer(forKey: selfTimerSecondsKey)
        return value == 0 ? 5 : value
    }

    static var playSounds: Bool {
        defaults.object(forKey: playSoundsKey) == nil ? true : defaults.bool(forKey: playSoundsKey)
    }

    static var includeCursor: Bool {
        defaults.bool(forKey: includeCursorKey)
    }

    static var captureWindowShadow: Bool {
        defaults.object(forKey: captureWindowShadowKey) == nil ? true : defaults.bool(forKey: captureWindowShadowKey)
    }

    static var keepTextLineBreaks: Bool {
        defaults.bool(forKey: keepTextLineBreaksKey)
    }

    static var autoDetectTextLanguage: Bool {
        defaults.object(forKey: autoDetectTextLanguageKey) == nil ? true : defaults.bool(forKey: autoDetectTextLanguageKey)
    }
}

final class ScreenToolPinWindow: NSPanel {
    private let onClose: (ScreenToolPinWindow) -> Void

    init(image: NSImage, onClose: @escaping (ScreenToolPinWindow) -> Void) {
        self.onClose = onClose
        let imageSize = image.size
        let maxWidth: CGFloat = 640
        let scale = min(1, maxWidth / max(imageSize.width, 1))
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let rect = NSRect(x: 160, y: 160, width: max(size.width, 120), height: max(size.height, 90))
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .hudWindow, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear

        let view = NSImageView(frame: NSRect(origin: .zero, size: rect.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = ScreenToolSettings.captureWindowShadow ? 10 : 0
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        contentView = view
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        onClose(self)
    }
}

final class ScreenToolOverlayWindow: NSPanel {
    private let onClose: (ScreenToolOverlayWindow) -> Void

    init(
        image: NSImage,
        url: URL,
        copy: @escaping () -> Void,
        pin: @escaping () -> Void,
        open: @escaping () -> Void,
        reveal: @escaping () -> Void,
        closeOverlay: @escaping (ScreenToolOverlayWindow) -> Void
    ) {
        self.onClose = closeOverlay

        let imageSize = image.size
        let previewWidth: CGFloat = 320
        let previewHeight = max(120, min(220, previewWidth * imageSize.height / max(imageSize.width, 1)))
        let rect = NSRect(x: 80, y: 120, width: 360, height: previewHeight + 86)

        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .hudWindow, .closable],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.heightAnchor.constraint(equalToConstant: previewHeight).isActive = true

        let filename = NSTextField(labelWithString: url.lastPathComponent)
        filename.lineBreakMode = .byTruncatingMiddle
        filename.maximumNumberOfLines = 1
        filename.font = .systemFont(ofSize: 11, weight: .medium)
        filename.textColor = .secondaryLabelColor

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually

        let copyButton = Self.actionButton(title: "Copy", action: copy)
        let pinButton = Self.actionButton(title: "Pin", action: pin)
        let openButton = Self.actionButton(title: "Open", action: open)
        let revealButton = Self.actionButton(title: "Reveal", action: reveal)

        [copyButton, pinButton, openButton, revealButton].forEach(buttonRow.addArrangedSubview)

        root.addArrangedSubview(imageView)
        root.addArrangedSubview(filename)
        root.addArrangedSubview(buttonRow)
        contentView = root
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        onClose(self)
    }

    private static func actionButton(title: String, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }
}

private final class ClosureButton: NSButton {
    private let closure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.closure = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(run)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        closure()
    }
}
