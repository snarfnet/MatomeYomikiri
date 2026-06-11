import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notification.enabled") }
    }
    @Published var hour: Int {
        didSet {
            UserDefaults.standard.set(hour, forKey: "notification.hour")
            reschedule()
        }
    }
    @Published var minute: Int {
        didSet {
            UserDefaults.standard.set(minute, forKey: "notification.minute")
            reschedule()
        }
    }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "notification.enabled") as? Bool ?? false
        hour = UserDefaults.standard.object(forKey: "notification.hour") as? Int ?? 20
        minute = UserDefaults.standard.object(forKey: "notification.minute") as? Int ?? 0
    }

    func requestPermissionAndEnable() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                self.isEnabled = granted
                if granted { self.reschedule() }
            }
        }
    }

    func disable() {
        isEnabled = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func reschedule() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduleDailyNotification()
    }

    func scheduleWithArticles(_ articles: [SharedArticle]) {
        guard isEnabled else { return }

        let top3 = Array(articles.sorted { $0.heat > $1.heat }.prefix(3))
        guard !top3.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "今日のバズ記事 TOP3"
        content.body = top3.enumerated().map { i, a in
            "\(i + 1). \(a.title)"
        }.joined(separator: "\n")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: "daily-buzz", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleDailyNotification() {
        let content = UNMutableNotificationContent()
        content.title = "まとめ・よみきり"
        content.body = "今日のバズ記事をチェック！"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: "daily-buzz", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
