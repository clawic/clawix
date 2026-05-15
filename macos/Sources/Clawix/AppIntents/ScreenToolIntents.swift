import AppIntents
import AppKit
import Foundation

enum ScreenToolsIntentError: Error, CustomLocalizedStringResourceConvertible {
    case disabled

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .disabled:
            return "Screen Tools is currently unavailable in this Clawix build."
        }
    }
}

@MainActor
private func ensureScreenToolsEnabled() throws {
    guard FeatureFlags.shared.isVisible(.screenTools) else {
        throw ScreenToolsIntentError.disabled
    }
}

@available(macOS 13.0, *)
struct RestoreLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Restore last capture"
    static var description = IntentDescription(
        "Reopen the most recent local capture in a Quick Access overlay."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.restoreLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct ShowLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Show last capture"
    static var description = IntentDescription(
        "Show the most recent local capture in a Quick Access overlay."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.showLastCaptureOverlay()
        return .result()
    }
}

@available(macOS 13.0, *)
struct PinLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Pin last capture"
    static var description = IntentDescription(
        "Pin the most recent local capture to the screen."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.pinLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct CopyLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy last capture"
    static var description = IntentDescription(
        "Copy the most recent local capture to the clipboard."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.copyLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct OpenLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Open last capture"
    static var description = IntentDescription(
        "Open the most recent local capture in its default app."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.openLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RevealLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Reveal last capture"
    static var description = IntentDescription(
        "Show the most recent local capture in Finder."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.revealLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RecognizeLastCaptureTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Recognize last capture text"
    static var description = IntentDescription(
        "Recognize text from the most recent local capture and copy it to the clipboard."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.recognizeLastCaptureText()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RevealCaptureFolderIntent: AppIntent {
    static var title: LocalizedStringResource = "Reveal capture folder"
    static var description = IntentDescription(
        "Show the local Screen Tools export folder in Finder."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.revealCaptureFolder()
        return .result()
    }
}
