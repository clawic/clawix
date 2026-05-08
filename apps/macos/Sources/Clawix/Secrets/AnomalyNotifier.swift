import Foundation
import UserNotifications
import SecretsModels
import SecretsVault

/// Best-effort macOS notification surface for anomaly detection results.
/// Requests authorization on first run; subsequent calls dispatch
/// `UNNotificationRequest` per anomaly through `UNUserNotificationCenter`.
/// If the user denies authorization, the helper degrades to silently
/// auditing the anomaly without a notification banner.
enum AnomalyNotifier {

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        default:
            break
        }
    }

    static func deliver(_ anomaly: Anomaly) {
        let content = UNMutableNotificationContent()
        content.title = title(for: anomaly.kind)
        content.body = anomaly.summary
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "clawix.anomaly.\(anomaly.id)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func title(for kind: Anomaly.Kind) -> String {
        switch kind {
        case .newHost:           return "Secrets · new host detected"
        case .newAgent:          return "Secrets · new agent detected"
        case .usageSpike:        return "Secrets · usage spike"
        case .failedUnlockSpike: return "Secrets · failed unlock attempts"
        case .offHoursAccess:    return "Secrets · off-hours access"
        }
    }
}
