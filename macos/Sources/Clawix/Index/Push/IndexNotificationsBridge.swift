import Foundation
import UserNotifications

/// Posts macOS user notifications when Index alerts fire. Subscribes to
/// the IndexManager's alert stream — when a new alert arrives, it asks
/// `UNUserNotificationCenter` to render it. Permission is requested
/// lazily on first call so the user only sees the prompt after they've
/// actually used Index. iOS APNs registration is symmetrical: the
/// daemon (in a follow-up) calls a parallel sink and pushes through
/// the iOS bridge.
@MainActor
final class IndexNotificationsBridge {
    static let shared = IndexNotificationsBridge()

    private var permissionGranted = false
    private var seenAlertIds = Set<String>()

    private init() {}

    func requestPermissionIfNeeded() {
        guard !permissionGranted else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                self?.permissionGranted = granted
            }
        }
    }

    func surface(_ alert: ClawJSIndexClient.Alert, entityTitle: String?) {
        guard !seenAlertIds.contains(alert.id) else { return }
        seenAlertIds.insert(alert.id)
        requestPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = headline(for: alert)
        content.body = body(for: alert, entityTitle: entityTitle)
        content.sound = .default
        content.userInfo = [
            "alertId": alert.id,
            "entityId": alert.entityId ?? "",
            "monitorId": alert.monitorId ?? "",
        ]
        let request = UNNotificationRequest(
            identifier: "clawix.index.alert.\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func headline(for alert: ClawJSIndexClient.Alert) -> String {
        switch alert.ruleKind {
        case "field_decrease":
            let pct = alert.payload["deltaPct"]?.asNumber ?? 0
            let field = alert.payload["field"]?.asString ?? "field"
            return "\(field.capitalized) dropped \(Int(pct))%"
        case "field_increase":
            let pct = alert.payload["deltaPct"]?.asNumber ?? 0
            let field = alert.payload["field"]?.asString ?? "field"
            return "\(field.capitalized) rose \(Int(pct))%"
        case "new_entity":
            return "New entity captured"
        case "rating_drop":
            return "Rating dropped"
        default:
            return "Index alert"
        }
    }

    private func body(for alert: ClawJSIndexClient.Alert, entityTitle: String?) -> String {
        if let entityTitle = entityTitle { return entityTitle }
        if let before = alert.payload["before"]?.asNumber, let after = alert.payload["after"]?.asNumber {
            return "from \(before) to \(after)"
        }
        return alert.ruleId
    }
}
