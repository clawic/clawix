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
    private var recordingCountdownTask: Task<Void, Never>?
    private var recordingTimerWindow: ScreenToolRecordingTimerWindow?

    private init() {}

    private var featureVisible: Bool {
        FeatureFlags.shared.isVisible(.screenTools)
    }

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

    enum BackgroundPreset: String, CaseIterable, Identifiable {
        case none

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            }
        }
    }

    enum RecordingMaxResolution: String, CaseIterable, Identifiable {
        case original
        case fourK = "4k"
        case p1440 = "1440p"
        case p1080 = "1080p"
        case p720 = "720p"
        case p480 = "480p"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .original: return "Original"
            case .fourK:    return "4k"
            case .p1440:    return "1440p"
            case .p1080:    return "1080p"
            case .p720:     return "720p"
            case .p480:     return "480p"
            }
        }

        var maxDimension: Int? {
            switch self {
            case .original: return nil
            case .fourK:    return 2160
            case .p1440:    return 1440
            case .p1080:    return 1080
            case .p720:     return 720
            case .p480:     return 480
            }
        }
    }

    enum CrosshairMode: String, CaseIterable, Identifiable {
        case always
        case command
        case disabled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .always:   return "Always enabled"
            case .command:  return "When Command is pressed"
            case .disabled: return "Disabled"
            }
        }

        func isVisible(modifierFlags: NSEvent.ModifierFlags) -> Bool {
            switch self {
            case .always: return true
            case .command: return modifierFlags.contains(.command)
            case .disabled: return false
            }
        }
    }

    func captureArea() {
        guard featureVisible else { return }
        guard authorize("captureArea") else { return }
        selectArea { [weak self] selection in
            guard let self else { return }
            if let frozenSnapshot = selection.frozenSnapshot, ScreenToolSettings.imageFormat != .pdf {
                self.runFrozenAreaCapture(selection: selection, snapshot: frozenSnapshot)
            } else {
                self.runCapture(mode: .area, rect: selection.rect)
            }
        }
    }

    func capturePreviousArea() {
        guard featureVisible else { return }
        guard authorize("capturePreviousArea") else { return }
        guard let rect = ScreenToolSettings.previousAreaRect else {
            ToastCenter.shared.show("No previous area", icon: .warning)
            return
        }
        runCapture(mode: .previousArea, rect: rect)
    }

    func captureFullscreen() {
        guard featureVisible else { return }
        guard authorize("captureFullscreen") else { return }
        runCapture(mode: .fullscreen)
    }

    func captureWindow() {
        guard featureVisible else { return }
        guard authorize("captureWindow") else { return }
        runCapture(mode: .window)
    }

    func captureScrolling() {
        guard featureVisible else { return }
        guard authorize("captureScrolling") else { return }
        selectArea { [weak self] selection in
            self?.runScrollingCapture(rect: selection.rect)
        }
    }

    func captureSelfTimer() {
        guard featureVisible else { return }
        guard authorize("captureSelfTimer") else { return }
        runCapture(mode: .selfTimer)
    }

    func recordScreen() {
        guard featureVisible else { return }
        guard authorize("recordScreen") else { return }
        guard Self.ensureScreenCaptureAccess() else { return }
        guard recordingCountdownTask == nil else { return }

        if ScreenToolSettings.showRecordingCountdown {
            startRecordingCountdown()
            return
        }

        startScreenRecording()
    }

    private func startRecordingCountdown() {
        recordingCountdownTask = Task { [weak self] in
            for value in stride(from: 3, through: 1, by: -1) {
                await MainActor.run {
                    ToastCenter.shared.show("Recording starts in \(value)", icon: .info, duration: 0.9)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
            }

            await MainActor.run {
                self?.recordingCountdownTask = nil
                self?.startScreenRecording()
            }
        }
    }

    private func startScreenRecording() {
        let url = outputURL(prefix: "recording", extension: "mov")
        if ScreenToolSettings.displayRecordingTime {
            let timerWindow = ScreenToolRecordingTimerWindow()
            timerWindow.show()
            recordingTimerWindow = timerWindow
        }
        Self.runScreencapture(args: Self.recordingArgs(output: url)) { [weak self] result in
            Task { @MainActor in
                self?.recordingTimerWindow?.close()
                self?.recordingTimerWindow = nil
                guard result.succeeded, FileManager.default.fileExists(atPath: url.path) else {
                    ToastCenter.shared.show(Self.captureFailureMessage(result, fallback: "Recording cancelled"), icon: .warning)
                    return
                }
                let finalURL = await Self.applyRecordingPostProcessing(to: url)
                self?.lastCaptureURL = finalURL
                if ScreenToolSettings.openRecordingEditorAfterRecording {
                    NSWorkspace.shared.open(finalURL)
                    ToastCenter.shared.show("Recording opened")
                } else {
                    ToastCenter.shared.show("Recording saved")
                }
            }
        }
    }

    func captureText(keepLineBreaks: Bool = ScreenToolSettings.keepTextLineBreaks) {
        guard featureVisible else { return }
        guard authorize("captureText") else { return }
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

    func recognizeLastCaptureText(keepLineBreaks: Bool = ScreenToolSettings.keepTextLineBreaks) {
        guard featureVisible else { return }
        guard authorize("recognizeLastCaptureText") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to recognize", icon: .warning)
            return
        }
        Task { @MainActor in
            await Self.recognizeText(in: url, keepLineBreaks: keepLineBreaks)
        }
    }

    func pinLastCapture() {
        guard featureVisible else { return }
        guard authorize("pinLastCapture") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to pin", icon: .warning)
            return
        }
        pin(url: url)
    }

    func showLastCaptureOverlay() {
        guard featureVisible else { return }
        guard authorize("showLastCaptureOverlay") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to show", icon: .warning)
            return
        }
        showOverlay(for: url)
    }

    func restoreLastCapture() {
        guard featureVisible else { return }
        guard authorize("restoreLastCapture") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to restore", icon: .warning)
            return
        }
        lastCaptureURL = url
        showOverlay(for: url)
    }

    func copyLastCapture() {
        guard featureVisible else { return }
        guard authorize("copyLastCapture") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to copy", icon: .warning)
            return
        }
        copyFileAndImage(url)
    }

    func markupLastCapture() {
        guard featureVisible else { return }
        guard authorize("markupLastCapture") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to mark up", icon: .warning)
            return
        }
        openMarkup(url)
    }

    func chooseAndPinImage() {
        guard featureVisible else { return }
        guard authorize("chooseAndPinImage") else { return }
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

    func chooseAndOpenImage() {
        guard featureVisible else { return }
        guard authorize("chooseAndOpenImage") else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.lastCaptureURL = url
                self?.showOverlay(for: url)
            }
        }
    }

    func closeAllPins() {
        guard featureVisible else { return }
        guard authorize("closeAllPins") else { return }
        pins.forEach { $0.close() }
        pins.removeAll()
        ToastCenter.shared.show("Pins closed")
    }

    func closeAllOverlays() {
        guard featureVisible else { return }
        guard authorize("closeAllOverlays") else { return }
        overlays.forEach { $0.close() }
        overlays.removeAll()
        ToastCenter.shared.show("Overlays closed")
    }

    func openCaptureHistory() {
        guard featureVisible else { return }
        guard authorize("openCaptureHistory") else { return }
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
        guard featureVisible else { return }
        guard authorize("revealCaptureFolder") else { return }
        let dir = ScreenToolSettings.exportDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    func openLastCapture() {
        guard featureVisible else { return }
        guard authorize("openLastCapture") else { return }
        guard let url = recentCaptureURL() else {
            ToastCenter.shared.show("No recent capture to open", icon: .warning)
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealLastCapture() {
        guard featureVisible else { return }
        guard authorize("revealLastCapture") else { return }
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
                try? Self.applyScreenshotPostProcessing(to: url)
                self?.lastCaptureURL = url
                self?.handleCapture(url)
            }
        }
    }

    private func runFrozenAreaCapture(selection: ScreenToolAreaSelectionResult, snapshot: NSImage) {
        let url = outputURL(prefix: outputPrefix(for: .area), extension: ScreenToolSettings.imageFormat.rawValue)
        do {
            guard try Self.writeFrozenSelection(from: snapshot, selectionRect: selection.snapshotRect, to: url) else {
                runCapture(mode: .area, rect: selection.rect)
                return
            }
            ScreenToolSettings.previousAreaRect = selection.rect
            try? Self.applyScreenshotPostProcessing(to: url)
            lastCaptureURL = url
            handleCapture(url)
        } catch {
            ToastCenter.shared.show("Could not save frozen capture", icon: .error)
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
                try? Self.applyScreenshotPostProcessing(to: output)
                lastCaptureURL = output
                handleCapture(output)
            } catch {
                ToastCenter.shared.show("Could not assemble scrolling capture", icon: .error)
            }
        }
    }

    private func selectArea(completion: @escaping (ScreenToolAreaSelectionResult) -> Void) {
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
            onComplete: { [weak self] selectionWindow, selection in
                if self?.areaSelectionWindow === selectionWindow {
                    self?.areaSelectionWindow = nil
                }
                completion(selection)
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
            openMarkup(url)
        }
    }

    private func openMarkup(_ url: URL) {
        NSWorkspace.shared.open(url)
        ToastCenter.shared.show("Capture opened for markup")
    }

    func copyFileAndImage(_ url: URL) {
        guard featureVisible else { return }
        guard authorize("copyFileAndImage") else { return }
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
        guard featureVisible else { return }
        guard authorize("pin") else { return }
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
        guard featureVisible else { return }
        guard authorize("reveal") else { return }
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

    static func recordingArgs(
        output url: URL,
        playSounds: Bool = ScreenToolSettings.playSounds,
        showCursor: Bool = ScreenToolSettings.showRecordingCursor,
        showControls: Bool = ScreenToolSettings.showRecordingControls,
        highlightClicks: Bool = ScreenToolSettings.highlightRecordingClicks,
        recordAudio: Bool = ScreenToolSettings.recordRecordingAudio
    ) -> [String] {
        var args: [String] = []
        if !playSounds { args.append("-x") }
        args.append(contentsOf: ["-v", "-J", "video"])
        if showCursor { args.append("-i") }
        if showControls { args.append("-U") }
        if highlightClicks { args.append("-k") }
        if recordAudio { args.append("-g") }
        args.append(url.path)
        return args
    }

    static func retinaVideoScaleArguments(input: URL, output: URL) -> [String] {
        recordingPostProcessingArguments(input: input, output: output, scaleRetinaTo1x: true, monoAudio: false)
    }

    static func monoRecordingAudioArguments(input: URL, output: URL) -> [String] {
        recordingPostProcessingArguments(input: input, output: output, scaleRetinaTo1x: false, monoAudio: true)
    }

    static func recordingPostProcessingArguments(
        input: URL,
        output: URL,
        scaleRetinaTo1x: Bool,
        monoAudio: Bool,
        videoFPS: Int = ScreenToolSettings.defaultRecordingVideoFPS,
        maxResolution: RecordingMaxResolution = ScreenToolSettings.recordingMaxResolution
    ) -> [String] {
        var args = [
            "-y",
            "-i", input.path,
            "-map", "0:v:0",
            "-map", "0:a?"
        ]

        var videoFilters: [String] = []
        if scaleRetinaTo1x {
            videoFilters.append("scale=trunc(iw/4)*2:trunc(ih/4)*2")
        }
        if let filter = maxResolutionVideoFilter(maxResolution) {
            videoFilters.append(filter)
        }
        if videoFPS != ScreenToolSettings.defaultRecordingVideoFPS {
            videoFilters.append("fps=\(videoFPS)")
        }

        if videoFilters.isEmpty {
            args.append(contentsOf: ["-c:v", "copy"])
        } else {
            args.append(contentsOf: [
                "-filter:v", videoFilters.joined(separator: ","),
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-crf", "18"
            ])
        }

        if monoAudio {
            args.append(contentsOf: ["-c:a", "aac", "-ac", "1"])
        } else {
            args.append(contentsOf: ["-c:a", "copy"])
        }

        args.append(contentsOf: ["-movflags", "+faststart", output.path])
        return args
    }

    static func maxResolutionVideoFilter(_ resolution: RecordingMaxResolution) -> String? {
        guard let maxDimension = resolution.maxDimension else { return nil }
        return "scale='if(gte(iw,ih),min(iw,\(maxDimension)),-2)':'if(gte(iw,ih),-2,min(ih,\(maxDimension)))'"
    }

    private static func applyRecordingPostProcessing(to url: URL) async -> URL {
        let scaleRetinaTo1x = ScreenToolSettings.scaleRetinaRecordingsTo1x
        let monoAudio = ScreenToolSettings.recordRecordingAudioInMono
        let videoFPS = ScreenToolSettings.recordingVideoFPS
        let maxResolution = ScreenToolSettings.recordingMaxResolution
        guard scaleRetinaTo1x
            || monoAudio
            || videoFPS != ScreenToolSettings.defaultRecordingVideoFPS
            || maxResolution != .original
        else {
            return url
        }

        do {
            try await postProcessRecording(
                url,
                scaleRetinaTo1x: scaleRetinaTo1x,
                monoAudio: monoAudio,
                videoFPS: videoFPS,
                maxResolution: maxResolution
            )
        } catch {
            ToastCenter.shared.show("Could not process recording", icon: .warning)
        }
        return url
    }

    private static func postProcessRecording(
        _ url: URL,
        scaleRetinaTo1x: Bool,
        monoAudio: Bool,
        videoFPS: Int,
        maxResolution: RecordingMaxResolution
    ) async throws {
        guard let ffmpeg = ffmpegExecutableURL() else {
            throw CocoaError(.fileNoSuchFile)
        }

        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)-processed-\(UUID().uuidString).mov")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let result = await runProcess(
            executableURL: ffmpeg,
            arguments: recordingPostProcessingArguments(
                input: url,
                output: temporaryURL,
                scaleRetinaTo1x: scaleRetinaTo1x,
                monoAudio: monoAudio,
                videoFPS: videoFPS,
                maxResolution: maxResolution
            )
        )
        guard result.succeeded, FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw CocoaError(.fileWriteUnknown)
        }

        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }

    private static func ffmpegExecutableURL(fileManager: FileManager = .default) -> URL? {
        [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        .map { URL(fileURLWithPath: $0) }
        .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func applyScreenshotPostProcessing(to url: URL) throws {
        if ScreenToolSettings.scaleRetinaScreenshotsTo1x {
            _ = try scaleRetinaImageTo1xIfNeeded(url)
        }
        if ScreenToolSettings.addOnePixelBorder {
            _ = try addOnePixelBorderIfNeeded(to: url)
        }
        if ScreenToolSettings.convertScreenshotsToSRGB {
            _ = try convertImageToSRGB(url)
        }
    }

    @discardableResult
    static func writeFrozenSelection(from image: NSImage, selectionRect: NSRect, to url: URL) throws -> Bool {
        guard
            selectionRect.width > 0,
            selectionRect.height > 0,
            let sourceRep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
            image.size.width > 0,
            image.size.height > 0
        else {
            return false
        }

        let xScale = CGFloat(sourceRep.pixelsWide) / image.size.width
        let yScale = CGFloat(sourceRep.pixelsHigh) / image.size.height
        let targetWidth = max(1, Int((selectionRect.width * xScale).rounded(.up)))
        let targetHeight = max(1, Int((selectionRect.height * yScale).rounded(.up)))

        guard let targetRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return false
        }

        targetRep.size = selectionRect.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: targetRep)
        image.draw(
            in: NSRect(origin: .zero, size: selectionRect.size),
            from: selectionRect,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmapData(for: targetRep, url: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return true
    }

    @discardableResult
    static func scaleRetinaImageTo1xIfNeeded(_ url: URL) throws -> Bool {
        guard
            let image = NSImage(contentsOf: url),
            let sourceRep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first
        else {
            return false
        }

        let targetWidth = Int(image.size.width.rounded())
        let targetHeight = Int(image.size.height.rounded())
        guard
            targetWidth > 0,
            targetHeight > 0,
            sourceRep.pixelsWide > targetWidth || sourceRep.pixelsHigh > targetHeight
        else {
            return false
        }

        guard let targetRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return false
        }

        targetRep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: targetRep)
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmapData(for: targetRep, url: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return true
    }

    @discardableResult
    static func addOnePixelBorderIfNeeded(to url: URL) throws -> Bool {
        guard
            let image = NSImage(contentsOf: url),
            let sourceRep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
            sourceRep.pixelsWide > 0,
            sourceRep.pixelsHigh > 0,
            image.size.width > 0,
            image.size.height > 0
        else {
            return false
        }

        let targetPixelsWide = sourceRep.pixelsWide + 2
        let targetPixelsHigh = sourceRep.pixelsHigh + 2
        guard let targetRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetPixelsWide,
            pixelsHigh: targetPixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return false
        }

        let xScale = CGFloat(sourceRep.pixelsWide) / image.size.width
        let yScale = CGFloat(sourceRep.pixelsHigh) / image.size.height
        let insetX = 1 / xScale
        let insetY = 1 / yScale
        let targetSize = NSSize(
            width: image.size.width + (2 / xScale),
            height: image.size.height + (2 / yScale)
        )
        targetRep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: targetRep)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        image.draw(
            in: NSRect(x: insetX, y: insetY, width: image.size.width, height: image.size.height),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmapData(for: targetRep, url: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return true
    }

    @discardableResult
    static func convertImageToSRGB(_ url: URL) throws -> Bool {
        guard
            let image = NSImage(contentsOf: url),
            let sourceRep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
            let cgImage = sourceRep.cgImage,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return false
        }

        guard let context = CGContext(
            data: nil,
            width: sourceRep.pixelsWide,
            height: sourceRep.pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sourceRep.pixelsWide, height: sourceRep.pixelsHigh))
        guard let outputImage = context.makeImage() else {
            return false
        }

        let targetRep = NSBitmapImageRep(cgImage: outputImage)
        targetRep.size = image.size
        guard let data = bitmapData(for: targetRep, url: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return true
    }

    private static func bitmapData(for rep: NSBitmapImageRep, url: URL) -> Data? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
        case "tif", "tiff":
            return rep.representation(using: .tiff, properties: [:])
        case "png":
            return rep.representation(using: .png, properties: [:])
        default:
            return nil
        }
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

    static func historyContent(urls: [URL], service: ScreenToolService) -> NSView {
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

    private static func runProcess(executableURL: URL, arguments: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let task = Process()
            let stderr = Pipe()
            task.executableURL = executableURL
            task.arguments = arguments
            task.standardError = stderr
            task.standardOutput = Pipe()
            task.terminationHandler = { task in
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: ProcessResult(exitStatus: task.terminationStatus, stderr: message))
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: ProcessResult(exitStatus: -1, stderr: error.localizedDescription))
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
