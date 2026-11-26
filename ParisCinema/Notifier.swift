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

/// A tapped notification: a plan check-in (film + action), the week's releases or a cinema.
struct NotificationTap {
    var film = ""
    var action = ""
    var type = ""
    var value = ""
}

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let category = "PLAN_CHECKIN"

    private var onOpen: ((NotificationTap) -> Void)?
    private var pending: NotificationTap?

    /// Called once at launch, so taps on a notification reach the app even when it was closed.
    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let watched = UNNotificationAction(identifier: "WATCHED", title: String(localized: "I watched it: rate it"), options: [.foreground])
        let notYet = UNNotificationAction(identifier: "NOT_YET", title: String(localized: "Not yet: pick a new day"), options: [.foreground])
        let cat = UNNotificationCategory(identifier: Self.category, actions: [watched, notYet], intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
    }

    func attach(_ handler: @escaping (NotificationTap) -> Void) {
        onOpen = handler
        if let p = pending {
            pending = nil
            handler(p)
        }
    }

    /// Asks once; iOS doesn't show the prompt again after you've answered.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Replaces all scheduled reminders with one per plan in the list.
    func schedule(_ alerts: [PlanAlert]) {
        let now = Date()
        let requests: [UNNotificationRequest] = alerts.filter { $0.end > now }.map { a in
            let content = UNMutableNotificationContent()
            content.title = String(localized: "How was \(a.title)?")
            content.body = String(localized: "Did you watch it at \(a.cinema)? Rate it, or pick another day.")
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = ["film": a.id]
            let parts = D.cal.dateComponents([.timeZone, .year, .month, .day, .hour, .minute], from: a.end)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            return UNNotificationRequest(identifier: "plan-" + a.id, content: content, trigger: trigger)
        }
        replace(prefix: "plan-") { center in
            for r in requests { center.add(r) }
        }
    }

    /// Removes the pending notifications whose id starts with a prefix, then adds the new ones.
    private func replace(prefix: String, then add: @escaping (UNUserNotificationCenter) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            add(center)
        }
    }

    /// The weekly "new films" notifications, replacing the previous ones.
    func scheduleReleases(_ items: [ReleaseAlert]) {
        // Built here (on the main thread), added once the old ones are gone.
        let requests: [UNNotificationRequest] = items.map { item in
            let content = UNMutableNotificationContent()
            let day = D.fmt(item.week, "EEEE d MMMM")
            content.title = String(localized: "New in cinemas 🍿")
            if item.titles.isEmpty {
                content.body = String(localized: "See the films out on \(day).")
            } else {
                let names = item.titles.prefix(3).joined(separator: ", ")
                content.body = item.titles.count > 3
                    ? String(localized: "\(item.titles.count) films out \(day): \(names)… Swipe through the posters.")
                    : String(localized: "Out \(day): \(names). Swipe through the posters.")
            }
            content.sound = .default
            content.userInfo = ["type": "releases", "week": item.week]
            let parts = D.cal.dateComponents([.timeZone, .year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            return UNNotificationRequest(identifier: "releases-" + D.str(item.date), content: content, trigger: trigger)
        }
        replace(prefix: "releases-") { center in
            for r in requests { center.add(r) }
        }
    }

    /// A notification shown straight away (or as soon as iOS allows).
    func notifyNow(id: String, title: String, body: String, info: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // Show the banner even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        var tap = NotificationTap()
        tap.film = info["film"] as? String ?? ""
        tap.action = response.actionIdentifier
        tap.type = info["type"] as? String ?? ""
        tap.value = (info["week"] as? String) ?? (info["cinema"] as? String) ?? ""
        DispatchQueue.main.async {
            if let h = self.onOpen { h(tap) } else { self.pending = tap }
            completionHandler()
        }
    }
}
