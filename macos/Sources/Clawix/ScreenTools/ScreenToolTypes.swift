import AppKit
import CoreGraphics

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

struct ScreenToolAreaSelectionResult {
    let rect: ScreenToolCaptureRect
    let snapshotRect: NSRect
    let frozenSnapshot: NSImage?
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
    static let scaleRetinaScreenshotsTo1xKey = "clawix.screenTools.scaleRetinaScreenshotsTo1x"
    static let convertScreenshotsToSRGBKey = "clawix.screenTools.convertScreenshotsToSRGB"
    static let addOnePixelBorderKey = "clawix.screenTools.addOnePixelBorder"
    static let freezeScreenOnCaptureKey = "clawix.screenTools.freezeScreenOnCapture"
    static let backgroundPresetKey = "clawix.screenTools.backgroundPreset"
    static let crosshairModeKey = "clawix.screenTools.crosshairMode"
    static let showCrosshairMagnifierKey = "clawix.screenTools.showCrosshairMagnifier"
    static let showRecordingCursorKey = "clawix.screenTools.showRecordingCursor"
    static let showRecordingControlsKey = "clawix.screenTools.showRecordingControls"
    static let highlightRecordingClicksKey = "clawix.screenTools.highlightRecordingClicks"
    static let recordRecordingAudioKey = "clawix.screenTools.recordRecordingAudio"
    static let displayRecordingTimeKey = "clawix.screenTools.displayRecordingTime"
    static let showRecordingCountdownKey = "clawix.screenTools.showRecordingCountdown"
    static let recordingMaxResolutionKey = "clawix.screenTools.recordingMaxResolution"
    static let recordingVideoFPSKey = "clawix.screenTools.recordingVideoFPS"
    static let scaleRetinaRecordingsTo1xKey = "clawix.screenTools.scaleRetinaRecordingsTo1x"
    static let recordRecordingAudioInMonoKey = "clawix.screenTools.recordRecordingAudioInMono"
    static let openRecordingEditorAfterRecordingKey = "clawix.screenTools.openRecordingEditorAfterRecording"
    static let keepTextLineBreaksKey = "clawix.screenTools.keepTextLineBreaks"
    static let autoDetectTextLanguageKey = "clawix.screenTools.autoDetectTextLanguage"
    static let previousAreaRectKey = "clawix.screenTools.previousAreaRect"
    static let recordingVideoFPSOptions = [15, 30, 60]
    static let defaultRecordingVideoFPS = 60

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

    static var scaleRetinaScreenshotsTo1x: Bool {
        defaults.bool(forKey: scaleRetinaScreenshotsTo1xKey)
    }

    static var convertScreenshotsToSRGB: Bool {
        defaults.bool(forKey: convertScreenshotsToSRGBKey)
    }

    static var addOnePixelBorder: Bool {
        defaults.bool(forKey: addOnePixelBorderKey)
    }

    static var freezeScreenOnCapture: Bool {
        defaults.bool(forKey: freezeScreenOnCaptureKey)
    }

    static var backgroundPreset: ScreenToolService.BackgroundPreset {
        let raw = defaults.string(forKey: backgroundPresetKey) ?? ScreenToolService.BackgroundPreset.none.rawValue
        return ScreenToolService.BackgroundPreset(rawValue: raw) ?? .none
    }

    static var crosshairMode: ScreenToolService.CrosshairMode {
        let raw = defaults.string(forKey: crosshairModeKey) ?? ScreenToolService.CrosshairMode.disabled.rawValue
        return ScreenToolService.CrosshairMode(rawValue: raw) ?? .disabled
    }

    static var showCrosshairMagnifier: Bool {
        defaults.object(forKey: showCrosshairMagnifierKey) == nil ? true : defaults.bool(forKey: showCrosshairMagnifierKey)
    }

    static var showRecordingCursor: Bool {
        defaults.object(forKey: showRecordingCursorKey) == nil ? true : defaults.bool(forKey: showRecordingCursorKey)
    }

    static var showRecordingControls: Bool {
        defaults.object(forKey: showRecordingControlsKey) == nil ? true : defaults.bool(forKey: showRecordingControlsKey)
    }

    static var highlightRecordingClicks: Bool {
        defaults.object(forKey: highlightRecordingClicksKey) == nil ? true : defaults.bool(forKey: highlightRecordingClicksKey)
    }

    static var recordRecordingAudio: Bool {
        defaults.bool(forKey: recordRecordingAudioKey)
    }

    static var displayRecordingTime: Bool {
        defaults.bool(forKey: displayRecordingTimeKey)
    }

    static var showRecordingCountdown: Bool {
        defaults.bool(forKey: showRecordingCountdownKey)
    }

    static var recordingMaxResolution: ScreenToolService.RecordingMaxResolution {
        let raw = defaults.string(forKey: recordingMaxResolutionKey) ?? ScreenToolService.RecordingMaxResolution.original.rawValue
        return ScreenToolService.RecordingMaxResolution(rawValue: raw) ?? .original
    }

    static var recordingVideoFPS: Int {
        let value = defaults.integer(forKey: recordingVideoFPSKey)
        return recordingVideoFPSOptions.contains(value) ? value : defaultRecordingVideoFPS
    }

    static var scaleRetinaRecordingsTo1x: Bool {
        defaults.bool(forKey: scaleRetinaRecordingsTo1xKey)
    }

    static var recordRecordingAudioInMono: Bool {
        defaults.bool(forKey: recordRecordingAudioInMonoKey)
    }

    static var openRecordingEditorAfterRecording: Bool {
        defaults.bool(forKey: openRecordingEditorAfterRecordingKey)
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
    private let onComplete: (ScreenToolAreaSelectionWindow, ScreenToolAreaSelectionResult) -> Void

    init(
        screen: NSScreen,
        onCancel: @escaping (ScreenToolAreaSelectionWindow) -> Void,
        onComplete: @escaping (ScreenToolAreaSelectionWindow, ScreenToolAreaSelectionResult) -> Void
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
            complete: { [weak self] selection in
                guard let self else { return }
                self.close()
                self.onComplete(self, selection)
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
    private let complete: (ScreenToolAreaSelectionResult) -> Void
    private let crosshairMode: ScreenToolService.CrosshairMode
    private let showMagnifier: Bool
    private let freezeScreen: Bool
    private let screenSnapshot: NSImage?
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var mousePoint: NSPoint?
    private var activeModifierFlags: NSEvent.ModifierFlags = []
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, cancel: @escaping () -> Void, complete: @escaping (ScreenToolAreaSelectionResult) -> Void) {
        self.screen = screen
        self.cancel = cancel
        self.complete = complete
        self.crosshairMode = ScreenToolSettings.crosshairMode
        self.showMagnifier = ScreenToolSettings.showCrosshairMagnifier
        self.freezeScreen = ScreenToolSettings.freezeScreenOnCapture
        self.screenSnapshot = Self.captureSnapshot(for: screen)
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(freezeScreen ? 0 : 0.16).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedEventPoint(event)
        startPoint = point
        currentPoint = point
        mousePoint = point
        activeModifierFlags = event.modifierFlags
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mousePoint = clampedEventPoint(event)
        activeModifierFlags = event.modifierFlags
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clampedEventPoint(event)
        currentPoint = point
        mousePoint = point
        activeModifierFlags = event.modifierFlags
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
        complete(ScreenToolAreaSelectionResult(
            rect: captureRect,
            snapshotRect: rect,
            frozenSnapshot: freezeScreen ? screenSnapshot : nil
        ))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        activeModifierFlags = event.modifierFlags
        needsDisplay = true
        super.flagsChanged(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if freezeScreen, let screenSnapshot {
            screenSnapshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            NSColor.black.withAlphaComponent(0.16).setFill()
            bounds.fill()
        }
        if let rect = currentSelectionRect {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
        }
        if shouldDrawCrosshair, let point = mousePoint {
            drawCrosshair(at: point)
            if showMagnifier {
                drawMagnifier(at: point)
            }
        }
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

    private var shouldDrawCrosshair: Bool {
        crosshairMode.isVisible(modifierFlags: activeModifierFlags)
    }

    private func drawCrosshair(at point: NSPoint) {
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: point.y))
        path.line(to: NSPoint(x: bounds.maxX, y: point.y))
        path.move(to: NSPoint(x: point.x, y: bounds.minY))
        path.line(to: NSPoint(x: point.x, y: bounds.maxY))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawMagnifier(at point: NSPoint) {
        guard let screenSnapshot else { return }
        let sampleSize = NSSize(width: 44, height: 44)
        let targetSize = NSSize(width: 112, height: 112)
        let inset: CGFloat = 18
        let targetOrigin = NSPoint(
            x: min(max(point.x + inset, bounds.minX + inset), bounds.maxX - targetSize.width - inset),
            y: min(max(point.y + inset, bounds.minY + inset), bounds.maxY - targetSize.height - inset)
        )
        let targetRect = NSRect(origin: targetOrigin, size: targetSize)
        let sourceRect = NSRect(
            x: min(max(point.x - sampleSize.width / 2, bounds.minX), bounds.maxX - sampleSize.width),
            y: min(max(point.y - sampleSize.height / 2, bounds.minY), bounds.maxY - sampleSize.height),
            width: sampleSize.width,
            height: sampleSize.height
        )

        let magnifierRadius = min(targetRect.width, targetRect.height) * 0.42

        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: targetRect, xRadius: magnifierRadius, yRadius: magnifierRadius)
        clipPath.addClip()
        screenSnapshot.draw(in: targetRect, from: sourceRect, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.72).setStroke()
        let border = NSBezierPath(roundedRect: targetRect, xRadius: magnifierRadius, yRadius: magnifierRadius)
        border.lineWidth = 2
        border.stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        let center = NSPoint(x: targetRect.midX, y: targetRect.midY)
        let guides = NSBezierPath()
        guides.move(to: NSPoint(x: targetRect.minX, y: center.y))
        guides.line(to: NSPoint(x: targetRect.maxX, y: center.y))
        guides.move(to: NSPoint(x: center.x, y: targetRect.minY))
        guides.line(to: NSPoint(x: center.x, y: targetRect.maxY))
        guides.lineWidth = 1
        guides.stroke()
    }

    private static func captureSnapshot(for screen: NSScreen) -> NSImage? {
        guard
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let image = CGDisplayCreateImage(displayID)
        else {
            return nil
        }
        return NSImage(cgImage: image, size: screen.frame.size)
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

final class ScreenToolRecordingTimerWindow: NSPanel {
    private let label = NSTextField(labelWithString: "00:00")
    private let startedAt = Date()
    private var timer: Timer?

    init(screen: NSScreen? = nil) {
        let size = NSSize(width: 96, height: 38)
        let visibleFrame = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 640, height: 480)
        let rect = NSRect(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )

        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true

        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 8
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true

        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        contentView = root
        updateLabel()
    }

    func show() {
        orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLabel()
        }
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
    }

    static func formattedElapsedTime(_ elapsedSeconds: TimeInterval) -> String {
        let total = max(0, Int(elapsedSeconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func updateLabel() {
        label.stringValue = Self.formattedElapsedTime(Date().timeIntervalSince(startedAt))
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

final class ClosureButton: NSButton {
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

enum ScreenToolMenuAction: String {
    case captureArea
    case capturePreviousArea
    case captureFullscreen
    case captureWindow
    case captureScrolling
    case captureSelfTimer
    case recordScreen
    case captureText
    case recognizeLastText
    case hideDesktopIcons
    case openImage
    case pinImage
    case pinLastCapture
    case showLastCapture
    case markupLastCapture
    case restoreLastCapture
    case copyLastCapture
    case openLastCapture
    case revealLastCapture
    case captureHistory
    case revealCaptureFolder
    case closeAllOverlays
    case closeAllPins
}

final class ScreenToolMenuActionTarget: NSObject {
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
