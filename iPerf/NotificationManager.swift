import AppKit
import UserNotifications

enum NotificationManager {
    /// Asks for permission; returns whether notifications are allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Posts a completion notification if the user enabled it and the app isn't frontmost.
    static func notifyTestCompleted(_ result: TestResult) async {
        guard UserDefaults.standard.bool(forKey: ClientPrefs.notifyOnCompletion), !NSApp.isActive else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "iPerf test complete"
        content.body = "\(result.serverAddress) · \(result.direction) · \(result.formattedThroughput)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: result.id.uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
