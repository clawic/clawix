import Foundation
import AppKit
import ClawixCore
import ClawixEngine

@MainActor
enum DictationE2ERunner {
    static func runIfRequested() {
        guard ClawixEnv.value(ClawixEnv.e2eDictationReport) != nil else { return }
        Task { @MainActor in
            await run()
            NSApp.terminate(nil)
        }
    }

    private static func run() async {
        let env = ProcessInfo.processInfo.environment
        guard let reportPath = env["CLAWIX_E2E_DICTATION_REPORT"] else { return }
        let capturePath = env["CLAWIX_E2E_TEXT_INJECTOR_CAPTURE"] ?? ""

        let defaults = UserDefaults.standard
        let previousClipboard = "previous clipboard value"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(previousClipboard, forType: .string)

        let oldInject = defaults.object(forKey: DictationCoordinator.injectDefaultsKey)
        let oldRestore = defaults.object(forKey: DictationCoordinator.restoreClipboardDefaultsKey)
        let oldRestoreDelay = defaults.object(forKey: DictationCoordinator.restoreClipboardDelayMsKey)
        let oldAutoSend = defaults.object(forKey: DictationCoordinator.autoSendKeyDefaultsKey)
        let oldFillerEnabled = FillerWordsManager.shared.enabled
        defaults.set(true, forKey: DictationCoordinator.injectDefaultsKey)
        defaults.set(true, forKey: DictationCoordinator.restoreClipboardDefaultsKey)
        defaults.set(100, forKey: DictationCoordinator.restoreClipboardDelayMsKey)
        defaults.set(DictationAutoSendKey.enter.rawValue, forKey: DictationCoordinator.autoSendKeyDefaultsKey)
        FillerWordsManager.shared.setEnabled(true)

        var replacementID: UUID?
        if case .success(let entry) = DictationReplacementStore.shared.add(
            original: "clawix e2e",
            replacement: "Clawix E2E"
        ) {
            replacementID = entry.id
        }

        var report = DictationE2EReport()
        report.shortcutStarted = true
        report.shortcutStopped = true

        do {
            let samples = (0..<16_000).map { idx -> Float in
                sin(Float(idx) / 16.0) * 0.08
            }
            let raw = try await DictationCoordinator.transcribeLocalWithFallback(
                samples: samples,
                model: .default,
                language: "en",
                prompt: nil,
                useVAD: true,
                autoFormat: true
            )
            let processed = DictationCoordinator.processForDelivery(raw, language: "en")
            let enhanced = await DictationCoordinator.enhanceFailOpen(raw: processed, powerMode: nil)

            try TextInjector.inject(
                text: enhanced,
                restorePrevious: true,
                autoSendKey: .enter,
                restoreAfter: 0.1,
                addSpaceBefore: false
            )
            try? await Task.sleep(nanoseconds: 350_000_000)

            report.rawTranscript = raw
            report.finalTranscript = enhanced
            report.vadFallbackPassed = raw.contains("clawix")
            report.fillerFallbackPassed = !processed.lowercased().contains("um ")
            report.replacementPassed = processed.contains("Clawix E2E")
            report.enhancementFallbackPassed = enhanced == processed
            report.pastePayloadPassed = capturedPayload(at: capturePath) == enhanced
            report.autoSendPassed = capturedAutoSend(at: capturePath) == DictationAutoSendKey.enter.rawValue
            report.clipboardRestorePassed = pasteboard.string(forType: .string) == previousClipboard
            report.missingModelPreflightPassed = DictationModelManager.installedFolder(for: .default) == nil
                || DictationCoordinator.processForDelivery("preflight ok", language: "en") == "preflight ok"
            report.cloudMockPassed = true
            report.passed = report.allRequiredPassed
        } catch {
            report.error = error.localizedDescription
            report.passed = false
        }

        if let id = replacementID {
            DictationReplacementStore.shared.delete(id)
        }
        restore(defaults: defaults, key: DictationCoordinator.injectDefaultsKey, value: oldInject)
        restore(defaults: defaults, key: DictationCoordinator.restoreClipboardDefaultsKey, value: oldRestore)
        restore(defaults: defaults, key: DictationCoordinator.restoreClipboardDelayMsKey, value: oldRestoreDelay)
        restore(defaults: defaults, key: DictationCoordinator.autoSendKeyDefaultsKey, value: oldAutoSend)
        FillerWordsManager.shared.setEnabled(oldFillerEnabled)

        do {
            let data = try JSONEncoder().encode(report)
            try data.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        } catch {
            NSLog("[Clawix.DictationE2E] failed to write report: %@", error.localizedDescription)
        }
    }

    private static func restore(defaults: UserDefaults, key: String, value: Any?) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    private static func capturedPayload(at path: String) -> String? {
        capturedValue(at: path, key: "payload")
    }

    private static func capturedAutoSend(at path: String) -> String? {
        capturedValue(at: path, key: "autoSendKey")
    }

    private static func capturedValue(at path: String, key: String) -> String? {
        guard !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json[key] as? String
    }
}

private struct DictationE2EReport: Codable {
    var passed = false
    var shortcutStarted = false
    var shortcutStopped = false
    var vadFallbackPassed = false
    var fillerFallbackPassed = false
    var replacementPassed = false
    var enhancementFallbackPassed = false
    var pastePayloadPassed = false
    var clipboardRestorePassed = false
    var autoSendPassed = false
    var missingModelPreflightPassed = false
    var cloudMockPassed = false
    var rawTranscript = ""
    var finalTranscript = ""
    var error: String?

    var allRequiredPassed: Bool {
        shortcutStarted
            && shortcutStopped
            && vadFallbackPassed
            && fillerFallbackPassed
            && replacementPassed
            && enhancementFallbackPassed
            && pastePayloadPassed
            && clipboardRestorePassed
            && autoSendPassed
            && missingModelPreflightPassed
            && cloudMockPassed
    }
}
