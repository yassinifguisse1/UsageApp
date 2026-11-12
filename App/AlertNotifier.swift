import UserNotifications
import UsageCore

@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        center.delegate = self
    }

    /// Returns false when the person has turned notifications off for UsageApp.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ alerts: [UsageAlert]) {
        for alert in alerts {
            let content = UNMutableNotificationContent()
            switch alert.kind {
            case .reached(let threshold) where threshold >= 100:
                content.title = "\(alert.provider.name) limit reached"
                content.body = alert.window.label + resetText(alert.window)
                content.sound = .default
            case .reached(let threshold):
                content.title = "\(alert.provider.name) at \(UsageFormat.percent(alert.window.usedPercent))"
                content.body = "\(alert.window.label) passed \(UsageFormat.percent(threshold))" + resetText(alert.window)
            case .reset:
                content.title = "\(alert.provider.name) allowance reset"
                content.body = "\(alert.window.label) has started a new period."
            }
            content.threadIdentifier = alert.provider.rawValue
            let id = "\(alert.provider.rawValue)/\(alert.window.id)"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    private func resetText(_ window: UsageWindow) -> String {
        window.resetsAt.map { " · resets \(UsageFormat.date($0))" } ?? ""
    }

    // UsageApp is an accessory app, so show alerts even while its settings window is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
