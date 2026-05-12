import AppIntents
import AppKit
import Foundation

@available(macOS 13.0, *)
struct RestoreLastCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Restore last capture"
    static var description = IntentDescription(
        "Reopen the most recent local capture in a Quick Access overlay."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.restoreLastCapture()
        return .result()
    }
}
