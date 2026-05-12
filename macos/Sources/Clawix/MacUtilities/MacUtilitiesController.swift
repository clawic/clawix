import AppKit
import Foundation
import IOKit.pwr_mgt

enum MacUtilityGroup: String, CaseIterable, Identifiable {
    case windows
    case system
    case toggles
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows:  return "Windows"
        case .system:   return "System"
        case .toggles:  return "Toggles"
        case .settings: return "System Settings"
        }
    }
}

enum MacUtilityActionID: String, CaseIterable, Identifiable {
    case hideAllWindows
    case minimizeAllWindows
    case minimizeAllWindowsExceptFrontmost
    case minimizeAppWindowsExceptFrontmost
    case isolateWindow
    case unminimizeAllWindows
    case showDesktop
    case clearClipboard
    case sleepDisplays
    case toggleDarkMode
    case toggleMuteSound
    case toggleKeepAwake
    case toggleDesktopIcons
    case openVPNSettings
    case openPrivateRelaySettings
    case openHideMyEmailSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hideAllWindows: return "Hide All Windows"
        case .minimizeAllWindows: return "Minimize All Windows"
        case .minimizeAllWindowsExceptFrontmost: return "Minimize All Windows Except Frontmost"
        case .minimizeAppWindowsExceptFrontmost: return "Minimize App Windows Except Frontmost"
        case .isolateWindow: return "Isolate Window"
        case .unminimizeAllWindows: return "Unminimize All Windows"
        case .showDesktop: return "Show Desktop"
        case .clearClipboard: return "Clear Clipboard"
        case .sleepDisplays: return "Sleep Displays"
        case .toggleDarkMode: return "Dark Mode"
        case .toggleMuteSound: return "Mute Sound"
        case .toggleKeepAwake: return "Keep Awake"
        case .toggleDesktopIcons: return "Desktop Icons"
        case .openVPNSettings: return "VPN & Filters"
        case .openPrivateRelaySettings: return "Private Relay"
        case .openHideMyEmailSettings: return "Hide My Email"
        }
    }

    var detail: String {
        switch self {
        case .hideAllWindows: return "Hide visible app windows without quitting apps."
        case .minimizeAllWindows: return "Minimize all visible windows in the current space."
        case .minimizeAllWindowsExceptFrontmost: return "Keep the active window visible and minimize the rest."
        case .minimizeAppWindowsExceptFrontmost: return "Minimize the other windows of the active app."
        case .isolateWindow: return "Hide other apps and minimize the active app's other windows."
        case .unminimizeAllWindows: return "Restore minimized windows across visible apps."
        case .showDesktop: return "Use the system Show Desktop shortcut."
        case .clearClipboard: return "Remove all current pasteboard contents."
        case .sleepDisplays: return "Put connected displays to sleep immediately."
        case .toggleDarkMode: return "Switch the system appearance between light and dark."
        case .toggleMuteSound: return "Toggle the default output mute state."
        case .toggleKeepAwake: return "Prevent idle sleep until disabled or Clawix quits."
        case .toggleDesktopIcons: return "Show or hide Finder desktop items."
        case .openVPNSettings: return "Open Network VPN settings."
        case .openPrivateRelaySettings: return "Open iCloud Private Relay settings."
        case .openHideMyEmailSettings: return "Open iCloud Hide My Email settings."
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .clearClipboard:
            return true
        default:
            return false
        }
    }

    var group: MacUtilityGroup {
        switch self {
        case .hideAllWindows,
             .minimizeAllWindows,
             .minimizeAllWindowsExceptFrontmost,
             .minimizeAppWindowsExceptFrontmost,
             .isolateWindow,
             .unminimizeAllWindows,
             .showDesktop:
            return .windows
        case .clearClipboard, .sleepDisplays:
            return .system
        case .toggleDarkMode, .toggleMuteSound, .toggleKeepAwake, .toggleDesktopIcons:
            return .toggles
        case .openVPNSettings, .openPrivateRelaySettings, .openHideMyEmailSettings:
            return .settings
        }
    }

    var systemImage: String {
        switch self {
        case .hideAllWindows: return "eye.slash"
        case .minimizeAllWindows: return "minus.square"
        case .minimizeAllWindowsExceptFrontmost: return "rectangle.on.rectangle.slash"
        case .minimizeAppWindowsExceptFrontmost: return "rectangle.stack"
        case .isolateWindow: return "scope"
        case .unminimizeAllWindows: return "plus.square.on.square"
        case .showDesktop: return "desktopcomputer"
        case .clearClipboard: return "clipboard"
        case .sleepDisplays: return "display"
        case .toggleDarkMode: return "moon"
        case .toggleMuteSound: return "speaker.slash"
        case .toggleKeepAwake: return "cup.and.saucer"
        case .toggleDesktopIcons: return "square.grid.3x3"
        case .openVPNSettings: return "network"
        case .openPrivateRelaySettings: return "icloud"
        case .openHideMyEmailSettings: return "envelope.badge.shield.half.filled"
        }
    }

    static func actions(in group: MacUtilityGroup) -> [MacUtilityActionID] {
        allCases.filter { $0.group == group }
    }
}

@MainActor
final class MacUtilitiesController: ObservableObject {
    static let shared = MacUtilitiesController()

    @Published private(set) var keepAwakeEnabled = false

    private var keepAwakeAssertion: IOPMAssertionID = 0

    private init() {}

    func perform(_ action: MacUtilityActionID) {
        do {
            switch action {
            case .hideAllWindows:
                try runAppleScript(Self.hideAllWindowsScript)
            case .minimizeAllWindows:
                try runAppleScript(Self.minimizeWindowsScript(mode: "all"))
            case .minimizeAllWindowsExceptFrontmost:
                try runAppleScript(Self.minimizeWindowsScript(mode: "allExceptFrontmost"))
            case .minimizeAppWindowsExceptFrontmost:
                try runAppleScript(Self.minimizeWindowsScript(mode: "frontmostExceptFirst"))
            case .isolateWindow:
                try runAppleScript(Self.isolateWindowScript)
            case .unminimizeAllWindows:
                try runAppleScript(Self.unminimizeAllWindowsScript)
            case .showDesktop:
                try runAppleScript(Self.showDesktopScript)
            case .clearClipboard:
                NSPasteboard.general.clearContents()
            case .sleepDisplays:
                try runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
            case .toggleDarkMode:
                try runAppleScript(Self.toggleDarkModeScript)
            case .toggleMuteSound:
                try runAppleScript(Self.toggleMuteSoundScript)
            case .toggleKeepAwake:
                try setKeepAwake(!keepAwakeEnabled)
            case .toggleDesktopIcons:
                try toggleDesktopIcons()
            case .openVPNSettings:
                openSystemSettings("x-apple.systempreferences:com.apple.Network-Settings.extension?VPN")
            case .openPrivateRelaySettings:
                openSystemSettings("x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?PRIVATERELAY")
            case .openHideMyEmailSettings:
                openSystemSettings("x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?HIDE_MY_EMAIL")
            }
            ToastCenter.shared.show("\(action.title) done")
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func setKeepAwake(_ enabled: Bool) throws {
        if enabled {
            guard !keepAwakeEnabled else { return }
            var assertionID: IOPMAssertionID = 0
            let reason = "Clawix Keep Awake" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            guard result == kIOReturnSuccess else {
                throw MacUtilityError.message("Could not keep the Mac awake")
            }
            keepAwakeAssertion = assertionID
            keepAwakeEnabled = true
        } else {
            if keepAwakeAssertion != 0 {
                IOPMAssertionRelease(keepAwakeAssertion)
                keepAwakeAssertion = 0
            }
            keepAwakeEnabled = false
        }
    }

    private func toggleDesktopIcons() throws {
        let current = try runProcess(
            "/usr/bin/defaults",
            arguments: ["read", "com.apple.finder", "CreateDesktop"],
            allowFailure: true
        )
        let showsDesktop = current.trimmingCharacters(in: .whitespacesAndNewlines) != "false"
        try runProcess(
            "/usr/bin/defaults",
            arguments: ["write", "com.apple.finder", "CreateDesktop", showsDesktop ? "false" : "true"]
        )
        try runProcess("/usr/bin/killall", arguments: ["Finder"], allowFailure: true)
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw MacUtilityError.message("Could not prepare action")
        }
        script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Action failed"
            throw MacUtilityError.message(message)
        }
    }

    @discardableResult
    private func runProcess(
        _ executable: String,
        arguments: [String],
        allowFailure: Bool = false
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !allowFailure {
            throw MacUtilityError.message(err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Command failed" : err)
        }
        return out
    }
}

private enum MacUtilityError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

private extension MacUtilitiesController {
    static let hideAllWindowsScript = """
    tell application "System Events"
        repeat with appProcess in application processes
            try
                if background only of appProcess is false then
                    set visible of appProcess to false
                end if
            end try
        end repeat
    end tell
    """

    static func minimizeWindowsScript(mode: String) -> String {
        """
        tell application "System Events"
            set frontName to name of first application process whose frontmost is true
            repeat with appProcess in application processes
                try
                    set windowIndex to 0
                    repeat with appWindow in windows of appProcess
                        set windowIndex to windowIndex + 1
                        set shouldMinimize to true
                        if "\(mode)" is "allExceptFrontmost" and name of appProcess is frontName and windowIndex is 1 then
                            set shouldMinimize to false
                        end if
                        if "\(mode)" is "frontmostExceptFirst" and name of appProcess is not frontName then
                            set shouldMinimize to false
                        end if
                        if "\(mode)" is "frontmostExceptFirst" and name of appProcess is frontName and windowIndex is 1 then
                            set shouldMinimize to false
                        end if
                        if shouldMinimize then
                            try
                                set value of attribute "AXMinimized" of appWindow to true
                            end try
                        end if
                    end repeat
                end try
            end repeat
        end tell
        """
    }

    static let isolateWindowScript = """
    tell application "System Events"
        set frontName to name of first application process whose frontmost is true
        repeat with appProcess in application processes
            try
                if background only of appProcess is false and name of appProcess is not frontName then
                    set visible of appProcess to false
                end if
                if name of appProcess is frontName then
                    set windowIndex to 0
                    repeat with appWindow in windows of appProcess
                        set windowIndex to windowIndex + 1
                        if windowIndex is greater than 1 then
                            try
                                set value of attribute "AXMinimized" of appWindow to true
                            end try
                        end if
                    end repeat
                end if
            end try
        end repeat
    end tell
    """

    static let unminimizeAllWindowsScript = """
    tell application "System Events"
        repeat with appProcess in application processes
            try
                repeat with appWindow in windows of appProcess
                    try
                        set value of attribute "AXMinimized" of appWindow to false
                    end try
                end repeat
            end try
        end repeat
    end tell
    """

    static let showDesktopScript = """
    tell application "System Events"
        key code 103
    end tell
    """

    static let toggleDarkModeScript = """
    tell application "System Events"
        tell appearance preferences
            set dark mode to not dark mode
        end tell
    end tell
    """

    static let toggleMuteSoundScript = """
    set currentMute to output muted of (get volume settings)
    set volume output muted (not currentMute)
    """
}
