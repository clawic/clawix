import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

/// Lightweight wrapper around the three TCC permissions the dictation
/// flow needs:
///
/// - **Microphone** — capturing audio from the input device.
/// - **Input Monitoring** — required by `NSEvent.addGlobalMonitorForEvents`
///   when the hotkey listener watches modifier keys system-wide. Without
///   it, calling `addGlobalMonitorForEvents(matching: .flagsChanged)` on
///   macOS 26 (Tahoe) freezes event delivery to the app until the TCC
///   flow resolves — the "frozen-input bug" we hit when registering the
///   monitor eagerly from `App.init()` without first checking the grant.
/// - **Accessibility** — required by `TextInjector` to post the
///   synthetic Cmd+V that pastes the transcribed text into the
///   foreground app once recording stops.
///
/// The check helpers never throw and never block — they read the TCC
/// state and return it. The "open" helpers send the user to the right
/// pane in System Settings; macOS Sequoia's URL scheme is
/// stable enough to use directly.
@MainActor
enum DictationPermissions {

    enum Status {
        case granted
        case denied
        case notDetermined
    }

    // MARK: - Microphone

    static func microphone() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { ok in cont.resume(returning: ok) }
        }
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    // MARK: - Accessibility (AXUIElement)

    /// `AXIsProcessTrusted` only reports trusted/untrusted; there is no
    /// system-level "not determined" bit. To still distinguish a fresh
    /// install (where the right CTA is "Request Access") from an
    /// explicit denial (where only "Open Settings" makes sense), we
    /// remember whether the OS prompt has ever been triggered for this
    /// process and treat the pre-prompt state as `.notDetermined`.
    private static let hasRequestedAccessibilityKey = "dictation.accessibility.hasRequested"

    static func accessibility() -> Status {
        if AXIsProcessTrusted() { return .granted }
        if UserDefaults.standard.bool(forKey: hasRequestedAccessibilityKey) { return .denied }
        return .notDetermined
    }

    /// Triggers the standard accessibility prompt. The OS dialog is
    /// non-blocking; the actual grant is reflected on the next call to
    /// `accessibility()` once the user toggles the switch in System
    /// Settings. Marks the permission as "asked" so subsequent calls
    /// fall into the `.denied` bucket and the UI surfaces "Open
    /// Settings" instead of asking again (the prompt is one-shot).
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        UserDefaults.standard.set(true, forKey: hasRequestedAccessibilityKey)
        return trusted
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: - Input Monitoring

    /// IOKit reports a tri-state directly, so unlike `accessibility()`
    /// we don't need to remember whether a prompt has been shown.
    static func inputMonitoring() -> Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        default:                      return .notDetermined
        }
    }

    /// Triggers the system "would like to monitor your keyboard" prompt.
    /// The grant takes effect immediately on the next call but does not
    /// re-arm previously-installed monitors — call `register()` again
    /// afterwards.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    // MARK: - Helpers

    private static func open(_ url: String) {
        guard let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}
