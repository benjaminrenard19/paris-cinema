import Foundation
import UserNotifications

/// One notification per confirmed plan, about when the film ends (start + 2 h 30).
struct PlanAlert {
    let id: String
    let title: String
    let cinema: String
    let end: Date
}

/// What the app should ask after a plan: rate the film, or pick a new day.
struct CheckIn: Identifiable, Equatable {
    let id: String       // film id
    let action: String   // "WATCHED", "NOT_YET" or "" (opened from the notification itself)
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let category = "PLAN_CHECKIN"

    private var onOpen: ((String, String) -> Void)?
    private var pending: (String, String)?

    /// Called once at launch, so taps on a notification reach the app even when it was closed.
    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let watched = UNNotificationAction(identifier: "WATCHED", title: "I watched it: rate it", options: [.foreground])
        let notYet = UNNotificationAction(identifier: "NOT_YET", title: "Not yet: pick a new day", options: [.foreground])
        let cat = UNNotificationCategory(identifier: Self.category, actions: [watched, notYet], intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
    }

    func attach(_ handler: @escaping (String, String) -> Void) {
        onOpen = handler
        if let p = pending {
            pending = nil
            handler(p.0, p.1)
        }
    }

    /// Asks once; iOS doesn't show the prompt again after you've answered.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Replaces all scheduled reminders with one per plan in the list.
    func schedule(_ alerts: [PlanAlert]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        for a in alerts where a.end > now {
            let content = UNMutableNotificationContent()
            content.title = "How was \(a.title)?"
            content.body = "Did you watch it at \(a.cinema)? Rate it, or pick another day."
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = ["film": a.id]
            let parts = D.cal.dateComponents([.timeZone, .year, .month, .day, .hour, .minute], from: a.end)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: "plan-" + a.id, content: content, trigger: trigger))
        }
    }

    // Show the banner even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["film"] as? String ?? ""
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if let h = self.onOpen { h(id, action) } else { self.pending = (id, action) }
            completionHandler()
        }
    }
}
