import AppKit
import Foundation

/// Native confirm dialog gating one-off requests from the embedded app
/// that need user approval (e.g. calling an agent tool, enabling
/// internet access). Centralized so AppBridgeMessageHandler doesn't
/// have to manage NSAlert windows or threading.
@MainActor
final class AppPermissionPrompt {
    static let shared = AppPermissionPrompt()

    enum Decision {
        case denied
        case once
        case always
    }

    private init() {}

    func requestToolApproval(
        appName: String,
        tool: String,
        completion: @escaping (Decision) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "“\(appName)” wants to call agent tool"
        alert.informativeText = "The app is requesting access to the tool ‘\(tool)’.\n\nAllow this once, always for this app, or deny."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow once")
        alert.addButton(withTitle: "Always allow")
        alert.addButton(withTitle: "Deny")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:  completion(.once)
        case .alertSecondButtonReturn: completion(.always)
        default:                       completion(.denied)
        }
    }

    func requestInternetApproval(
        appName: String,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Allow “\(appName)” to access the internet?"
        alert.informativeText = "By default Clawix Apps run offline. If you grant access this app will be able to make HTTPS requests to any host."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Keep offline")
        let response = alert.runModal()
        completion(response == .alertFirstButtonReturn)
    }
}
