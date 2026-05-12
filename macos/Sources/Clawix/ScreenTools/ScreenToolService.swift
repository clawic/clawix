import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import Vision

@MainActor
final class ScreenToolService: ObservableObject {
    static let shared = ScreenToolService()

    @Published private(set) var lastCaptureURL: URL?
    @Published private(set) var pins: [ScreenToolPinWindow] = []
    @Published private(set) var overlays: [ScreenToolOverlayWindow] = []

    private var historyWindow: ScreenToolHistoryWindow?
    private var areaSelectionWindow: ScreenToolAreaSelectionWindow?
    private var allInOneMenu: NSMenu?
    private var allInOneMenuTarget: ScreenToolMenuActionTarget?

    private init() {}

    enum CaptureMode {
        case area
        case previousArea
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

    func showAllInOneMenu() {
        let menu = NSMenu()
        let target = ScreenToolMenuActionTarget { [weak self] action in
            guard let self else { return }
            self.allInOneMenu = nil
            self.allInOneMenuTarget = nil
            switch action {
            case .captureArea:         self.captureArea()
            case .capturePreviousArea: self.capturePreviousArea()
            case .captureFullscreen:   self.captureFullscreen()
            case .captureWindow:       self.captureWindow()
            case .captureScrolling:    self.captureScrolling()
            case .captureSelfTimer:    self.captureSelfTimer()
            case .recordScreen:        self.recordScreen()
            case .captureText:         self.captureText()
            case .pinImage:            self.chooseAndPinImage()
            case .captureHistory:      self.openCaptureHistory()
            }
        }
        allInOneMenu = menu
        allInOneMenuTarget = target

        func addItem(_ title: String, action: ScreenToolMenuAction, symbol: String) {
            let item = NSMenuItem(title: title, action: #selector(ScreenToolMenuActionTarget.runScreenToolMenuAction(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            menu.addItem(item)
        }

        addItem("Capture Area", action: .captureArea, symbol: "crop")
        addItem("Capture Previous Area", action: .capturePreviousArea, symbol: "rectangle.dashed")
        addItem("Capture Fullscreen", action: .captureFullscreen, symbol: "rectangle.inset.filled")
        addItem("Capture Window", action: .captureWindow, symbol: "macwindow")
        addItem("Scrolling Capture", action: .captureScrolling, symbol: "arrow.down.doc")
        addItem("Self-Timer", action: .captureSelfTimer, symbol: "timer")
        menu.addItem(.separator())
        addItem("Record Screen", action: .recordScreen, symbol: "record.circle")
        addItem("Capture Text", action: .captureText, symbol: "text.viewfinder")
        menu.addItem(.separator())
        addItem("Pin Image...", action: .pinImage, symbol: "pin")
        addItem("Capture History...", action: .captureHistory, symbol: "clock")

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func captureArea() {
        selectArea { [weak self] rect in
            self?.runCapture(mode: .area, rect: rect)
        }
    }

    func capturePreviousArea() {
        guard let rect = ScreenToolSettings.previousAreaRect else {
            ToastCenter.shared.show("No previous area", icon: .warning)
            return
        }
        runCapture(mode: .previousArea, rect: rect)
    }

    func captureFullscreen() {
        runCapture(mode: .fullscreen)
    }

    func captureWindow() {
        runCapture(mode: .window)
    }

    func captureScrolling() {
        selectArea { [weak self] rect in
            self?.runScrollingCapture(rect: rect)
        }
    }

    func captureSelfTimer() {
        runCapture(mode: .selfTimer)
    }

    func recordScreen() {
        guard Self.ensureScreenCaptureAccess() else { return }
        let url = outputURL(prefix: "recording", extension: "mov")
        Self.runScreencapture(args: ["-v", "-i", "-J", "video", url.path]) { [weak self] result in
            Task { @MainActor in
                guard result.succeeded, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show(Self.captureFailureMessage(result, fallback: "Recording cancelled"), icon: .warning)
                    return
                }
                self?.lastCaptureURL = url
                ToastCenter.shared.show("Recording saved")
            }
        }
    }

    func captureText(keepLineBreaks: Bool = ScreenToolSettings.keepTextLineBreaks) {
        guard Self.ensureScreenCaptureAccess() else { return }
        let url = outputURL(prefix: "text", extension: "png")
        Self.runScreencapture(args: interactiveArgs(mode: .area, output: url)) { result in
            Task { @MainActor in
                guard result.succeeded, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show(Self.captureFailureMessage(result, fallback: "Text capture cancelled"), icon: .warning)
                    return
                }
                await Self.recognizeText(in: url, keepLineBreaks: keepLineBreaks)
            }
        }
    }

    func pinLastCapture() {
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to pin", icon: .warning)
            return
        }
        pin(url: url)
    }

    func showLastCaptureOverlay() {
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to show", icon: .warning)
            return
        }
        showOverlay(for: url)
    }

    func copyLastCapture() {
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to copy", icon: .warning)
            return
        }
        copyFileAndImage(url)
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
        let urls = captureHistoryURLs(limit: 30)
        let window = ScreenToolHistoryWindow(
            urls: urls,
            service: self,
            closeHistory: { [weak self] window in
                Task { @MainActor in
                    if self?.historyWindow === window {
                        self?.historyWindow = nil
                    }
                }
            }
        )
        historyWindow?.close()
        historyWindow = window
        window.show()
    }

    func revealCaptureFolder() {
        let dir = ScreenToolSettings.exportDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    func openLastCapture() {
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to open", icon: .warning)
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealLastCapture() {
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to reveal", icon: .warning)
            return
        }
        reveal(url: url)
    }

    private func runCapture(mode: CaptureMode, rect: ScreenToolCaptureRect? = nil) {
        guard Self.ensureScreenCaptureAccess() else { return }
        let url = outputURL(prefix: outputPrefix(for: mode), extension: ScreenToolSettings.imageFormat.rawValue)
        Self.runScreencapture(args: interactiveArgs(mode: mode, output: url, rect: rect)) { [weak self] result in
            Task { @MainActor in
                guard result.succeeded, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show(Self.captureFailureMessage(result, fallback: "Capture cancelled"), icon: .warning)
                    return
                }
                if mode == .area, let rect {
                    ScreenToolSettings.previousAreaRect = rect
                }
                self?.lastCaptureURL = url
                self?.handleCapture(url)
            }
        }
    }

    private func runScrollingCapture(rect: ScreenToolCaptureRect) {
        guard Self.ensureScreenCaptureAccess() else { return }
        ScreenToolSettings.previousAreaRect = rect
        ToastCenter.shared.show("Scrolling capture started")

        Task { @MainActor in
            let temporaryURLs = (0..<Self.scrollingCaptureFrameCount).map { index in
                FileManager.default.temporaryDirectory
                    .appendingPathComponent("clawix-scrolling-\(UUID().uuidString)-\(index).png")
            }
            defer {
                for url in temporaryURLs {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            for (index, url) in temporaryURLs.enumerated() {
                let result = await Self.runScreencapture(args: scrollingCaptureArgs(rect: rect, output: url))
                guard result.succeeded, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show(Self.captureFailureMessage(result, fallback: "Scrolling capture cancelled"), icon: .warning)
                    return
                }

                if index < temporaryURLs.count - 1 {
                    Self.scrollDown(rect: rect)
                    try? await Task.sleep(nanoseconds: Self.scrollingCaptureFrameDelay)
                }
            }

            let output = outputURL(prefix: "scrolling", extension: "png")
            do {
                try Self.writeStitchedImage(from: temporaryURLs, to: output)
                lastCaptureURL = output
                handleCapture(output)
            } catch {
                ToastCenter.shared.show("Could not assemble scrolling capture", icon: .error)
            }
        }
    }

    private func selectArea(completion: @escaping (ScreenToolCaptureRect) -> Void) {
        guard let screen = Self.activeScreen() else {
            ToastCenter.shared.show("No screen available", icon: .error)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let window = ScreenToolAreaSelectionWindow(
            screen: screen,
            onCancel: { [weak self] selectionWindow in
                if self?.areaSelectionWindow === selectionWindow {
                    self?.areaSelectionWindow = nil
                }
                ToastCenter.shared.show("Capture cancelled", icon: .warning)
            },
            onComplete: { [weak self] selectionWindow, rect in
                if self?.areaSelectionWindow === selectionWindow {
                    self?.areaSelectionWindow = nil
                }
                completion(rect)
            }
        )
        areaSelectionWindow?.close()
        areaSelectionWindow = window
        window.show()
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

    private func scrollingCaptureArgs(rect: ScreenToolCaptureRect, output url: URL) -> [String] {
        var args: [String] = []
        if !ScreenToolSettings.playSounds { args.append("-x") }
        args.append(contentsOf: ["-t", "png", "-R", rect.screencaptureArgument, url.path])
        return args
    }

    private func outputPrefix(for mode: CaptureMode) -> String {
        switch mode {
        case .area:         return "area"
        case .previousArea: return "area"
        case .fullscreen:   return "fullscreen"
        case .window:       return "window"
        case .selfTimer:    return "timer"
        }
    }

    private func interactiveArgs(mode: CaptureMode, output url: URL, rect: ScreenToolCaptureRect? = nil) -> [String] {
        var args: [String] = []
        if !ScreenToolSettings.playSounds { args.append("-x") }
        args.append(contentsOf: ["-t", ScreenToolSettings.imageFormat.rawValue])
        switch mode {
        case .area, .previousArea:
            if let rect {
                args.append(contentsOf: ["-R", rect.screencaptureArgument])
            } else {
                args.append(contentsOf: ["-i", "-s"])
            }
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

    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func recentCaptureURL() -> URL? {
        if let lastCaptureURL, FileManager.default.fileExists(atPath: lastCaptureURL.path) {
            return lastCaptureURL
        }

        return captureHistoryURLs(limit: 1).first
    }

    private func captureHistoryURLs(limit: Int?) -> [URL] {
        let dir = ScreenToolSettings.exportDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let prefixes = ["area-", "fullscreen-", "window-", "scrolling-", "timer-", "text-", "recording-"]
        let extensions = Set(["png", "jpg", "tiff", "pdf", "mov"])
        let sorted = urls
            .filter { url in
                prefixes.contains { url.lastPathComponent.hasPrefix($0) }
                    && extensions.contains(url.pathExtension.lowercased())
            }
            .sorted { lhs, rhs in
                Self.modificationDate(for: lhs) > Self.modificationDate(for: rhs)
            }
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    private static func displayDate(for url: URL) -> String {
        historyDateFormatter.string(from: modificationDate(for: url))
    }

    private static func fileSizeText(for url: URL) -> String {
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    fileprivate static func historyDetail(for url: URL) -> String {
        "\(displayDate(for: url)) · \(fileSizeText(for: url))"
    }

    fileprivate static func historyFileName(for url: URL) -> String {
        url.lastPathComponent
    }

    fileprivate func showHistoryItem(_ url: URL) {
        showOverlay(for: url)
    }

    fileprivate func copyHistoryItem(_ url: URL) {
        copyFileAndImage(url)
    }

    fileprivate func pinHistoryItem(_ url: URL) {
        pin(url: url)
    }

    fileprivate func revealHistoryItem(_ url: URL) {
        reveal(url: url)
    }

    fileprivate func openHistoryItem(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    fileprivate func closeHistoryWindow(_ window: ScreenToolHistoryWindow) {
        if historyWindow === window {
            historyWindow = nil
        }
    }

    fileprivate static func historyRowButton(title: String, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    fileprivate static func historyLabel(_ title: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.font = font
        label.textColor = color
        return label
    }

    fileprivate static func historyEmptyLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "No local captures yet")
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    fileprivate static func historyHeaderLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "Capture History")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    fileprivate static func historySubtitleLabel(_ count: Int) -> NSTextField {
        let label = NSTextField(labelWithString: "\(count) recent local captures")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    fileprivate static func historyRow(url: URL, service: ScreenToolService) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.spacing = 2
        labels.addArrangedSubview(historyLabel(historyFileName(for: url), font: .systemFont(ofSize: 12, weight: .medium), color: .labelColor))
        labels.addArrangedSubview(historyLabel(historyDetail(for: url), font: .systemFont(ofSize: 11), color: .secondaryLabelColor))
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.addArrangedSubview(historyRowButton(title: "Show") { service.showHistoryItem(url) })
        buttons.addArrangedSubview(historyRowButton(title: "Copy") { service.copyHistoryItem(url) })
        buttons.addArrangedSubview(historyRowButton(title: "Pin") { service.pinHistoryItem(url) })
        buttons.addArrangedSubview(historyRowButton(title: "Open") { service.openHistoryItem(url) })
        buttons.addArrangedSubview(historyRowButton(title: "Reveal") { service.revealHistoryItem(url) })

        row.addArrangedSubview(labels)
        row.addArrangedSubview(buttons)
        return row
    }

    fileprivate static func historyDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        return divider
    }

    fileprivate static func historyContent(urls: [URL], service: ScreenToolService) -> NSView {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        root.addArrangedSubview(historyHeaderLabel())
        root.addArrangedSubview(historySubtitleLabel(urls.count))
        root.addArrangedSubview(historyDivider())

        if urls.isEmpty {
            root.addArrangedSubview(historyEmptyLabel())
            return root
        }

        for (index, url) in urls.enumerated() {
            root.addArrangedSubview(historyRow(url: url, service: service))
            if index < urls.count - 1 {
                root.addArrangedSubview(historyDivider())
            }
        }
        return root
    }

    private static func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        if CGRequestScreenCaptureAccess() {
            return true
        }

        ToastCenter.shared.show("Allow Screen Recording in System Settings", icon: .warning, duration: 4)
        return false
    }

    private static func runScreencapture(args: [String], completion: @escaping (ProcessResult) -> Void) {
        let task = Process()
        let stderr = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = args
        task.standardError = stderr
        task.terminationHandler = { task in
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                completion(ProcessResult(exitStatus: task.terminationStatus, stderr: message))
            }
        }
        do {
            try task.run()
        } catch {
            DispatchQueue.main.async {
                completion(ProcessResult(exitStatus: -1, stderr: error.localizedDescription))
            }
        }
    }

    private static func runScreencapture(args: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            runScreencapture(args: args) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private static func scrollDown(rect: ScreenToolCaptureRect) {
        let amount = max(120, Int32(Double(rect.height) * 0.85))
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -amount, wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private static func writeStitchedImage(from urls: [URL], to outputURL: URL) throws {
        let images = urls.compactMap(NSImage.init(contentsOf:))
        guard !images.isEmpty else { throw CocoaError(.fileReadCorruptFile) }

        let width = images.map(\.size.width).max() ?? 0
        let height = images.reduce(CGFloat(0)) { $0 + $1.size.height }
        let stitched = NSImage(size: NSSize(width: width, height: height))
        stitched.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var y = height
        for image in images {
            y -= image.size.height
            image.draw(
                in: NSRect(x: 0, y: y, width: image.size.width, height: image.size.height),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
        }
        stitched.unlockFocus()

        guard
            let tiff = stitched.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private static func captureFailureMessage(_ result: ProcessResult, fallback: String) -> String {
        if !CGPreflightScreenCaptureAccess() {
            return "Screen Recording permission required"
        }
        if !result.stderr.isEmpty {
            return result.stderr
        }
        return fallback
    }

    private static func modificationDate(for url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
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

    private struct ProcessResult {
        let exitStatus: Int32
        let stderr: String

        var succeeded: Bool {
            exitStatus == 0
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        return formatter
    }()

    private static let scrollingCaptureFrameCount = 3
    private static let scrollingCaptureFrameDelay: UInt64 = 450_000_000
}

struct ScreenToolCaptureRect: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var screencaptureArgument: String {
        "\(x),\(y),\(width),\(height)"
    }

    var storageValue: String {
        screencaptureArgument
    }

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
        self.init(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    init?(selectionRect: NSRect, in screen: NSScreen) {
        let normalized = selectionRect.standardized
        guard normalized.width >= 4, normalized.height >= 4 else { return nil }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        let displayBounds = CGDisplayBounds(displayID)
        let x = Int((displayBounds.minX + normalized.minX).rounded(.down))
        let y = Int((displayBounds.minY + (screen.frame.height - normalized.maxY)).rounded(.down))
        let width = Int(normalized.width.rounded(.up))
        let height = Int(normalized.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }
        self.init(x: x, y: y, width: width, height: height)
    }
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
    static let previousAreaRectKey = "clawix.screenTools.previousAreaRect"

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

    static var previousAreaRect: ScreenToolCaptureRect? {
        get {
            guard let value = defaults.string(forKey: previousAreaRectKey), !value.isEmpty else { return nil }
            return ScreenToolCaptureRect(storageValue: value)
        }
        set {
            if let newValue {
                defaults.set(newValue.storageValue, forKey: previousAreaRectKey)
            } else {
                defaults.removeObject(forKey: previousAreaRectKey)
            }
        }
    }
}

final class ScreenToolAreaSelectionWindow: NSPanel {
    private let onCancel: (ScreenToolAreaSelectionWindow) -> Void
    private let onComplete: (ScreenToolAreaSelectionWindow, ScreenToolCaptureRect) -> Void

    init(
        screen: NSScreen,
        onCancel: @escaping (ScreenToolAreaSelectionWindow) -> Void,
        onComplete: @escaping (ScreenToolAreaSelectionWindow, ScreenToolCaptureRect) -> Void
    ) {
        self.onCancel = onCancel
        self.onComplete = onComplete
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false

        contentView = ScreenToolAreaSelectionView(
            screen: screen,
            cancel: { [weak self] in
                guard let self else { return }
                self.close()
                self.onCancel(self)
            },
            complete: { [weak self] rect in
                guard let self else { return }
                self.close()
                self.onComplete(self, rect)
            }
        )
    }

    func show() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(contentView)
    }

    override var canBecomeKey: Bool { true }
}

private final class ScreenToolAreaSelectionView: NSView {
    private let screen: NSScreen
    private let cancel: () -> Void
    private let complete: (ScreenToolCaptureRect) -> Void
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    init(screen: NSScreen, cancel: @escaping () -> Void, complete: @escaping (ScreenToolCaptureRect) -> Void) {
        self.screen = screen
        self.cancel = cancel
        self.complete = complete
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = clampedEventPoint(event)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = clampedEventPoint(event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clampedEventPoint(event)
        guard let rect = currentSelectionRect,
              let captureRect = ScreenToolCaptureRect(selectionRect: rect, in: screen)
        else {
            cancel()
            return
        }
        complete(captureRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = currentSelectionRect else { return }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    private var currentSelectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func clampedEventPoint(_ event: NSEvent) -> NSPoint {
        let point = convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
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
        let closeButton = Self.actionButton(title: "Close") { [weak self] in
            self?.close()
        }

        [copyButton, pinButton, openButton, revealButton, closeButton].forEach(buttonRow.addArrangedSubview)

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

final class ScreenToolHistoryWindow: NSPanel {
    private let onClose: (ScreenToolHistoryWindow) -> Void

    init(
        urls: [URL],
        service: ScreenToolService,
        closeHistory: @escaping (ScreenToolHistoryWindow) -> Void
    ) {
        self.onClose = closeHistory
        let rows = max(1, min(urls.count, 8))
        let rect = NSRect(x: 140, y: 140, width: 780, height: CGFloat(130 + rows * 58))

        super.init(
            contentRect: rect,
            styleMask: [.hudWindow, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        title = "Capture History"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        positionOnActiveScreen(size: rect.size)

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: rect.size))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScroller = ThinScroller()

        let content = ScreenToolService.historyContent(urls: urls, service: service)
        content.frame = NSRect(x: 0, y: 0, width: rect.width, height: max(rect.height, CGFloat(96 + max(1, urls.count) * 58)))
        scroll.documentView = content
        contentView = scroll
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        onClose(self)
    }

    private func positionOnActiveScreen(size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        setFrame(NSRect(origin: origin, size: size), display: false)
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

private enum ScreenToolMenuAction: String {
    case captureArea
    case capturePreviousArea
    case captureFullscreen
    case captureWindow
    case captureScrolling
    case captureSelfTimer
    case recordScreen
    case captureText
    case pinImage
    case captureHistory
}

private final class ScreenToolMenuActionTarget: NSObject {
    private let handler: (ScreenToolMenuAction) -> Void

    init(handler: @escaping (ScreenToolMenuAction) -> Void) {
        self.handler = handler
    }

    @objc func runScreenToolMenuAction(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let action = ScreenToolMenuAction(rawValue: rawValue)
        else { return }
        handler(action)
    }
}
