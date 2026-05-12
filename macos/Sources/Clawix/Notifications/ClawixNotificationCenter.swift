import Foundation
import UserNotifications

/// Light wrapper over `UNUserNotificationCenter` used by the P2P stack to
/// surface mailbox messages, interest expressions, capability grants and
/// match-receipt signings to macOS while the app is in the background.
@MainActor
final class ClawixNotificationCenter {

    static let shared = ClawixNotificationCenter()

    private init() {}

    enum Trigger: String {
        case newMessage = "p2p.message"
        case newInterest = "p2p.interest"
        case newPost = "p2p.post"
        case capabilityGranted = "p2p.capability.granted"
        case capabilityRevoked = "p2p.capability.revoked"
        case matchReceiptSigned = "p2p.match.signed"
        case restoreConfirmed = "p2p.recovery.confirmed"
    }

    struct Payload {
        let trigger: Trigger
        let title: String
        let body: String
        let userInfo: [String: String]
    }

    func requestAuthorisationIfNeeded() async {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await centre.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func post(_ payload: Payload) async {
        await requestAuthorisationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.threadIdentifier = payload.trigger.rawValue
        content.userInfo = payload.userInfo
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
