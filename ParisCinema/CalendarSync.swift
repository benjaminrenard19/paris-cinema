import Foundation
import EventKit

struct CalendarItem {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String
    let notes: String
}

/// Keeps confirmed plans in a calendar of your choice. Any calendar on the iPhone works,
/// including Google Calendar once the Google account is added in iPhone Settings › Calendar.
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()
    let events = EKEventStore()

    var enabled: Bool { UserDefaults.standard.bool(forKey: "calSync") }
    var calendarId: String? { UserDefaults.standard.string(forKey: "calId").flatMap { $0.isEmpty ? nil : $0 } }
    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    private var eventIds: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "calEvents") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "calEvents") }
    }

    func requestAccess() async -> Bool {
        (try? await events.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [EKCalendar] {
        events.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
    }

    var defaultCalendarId: String? { events.defaultCalendarForNewEvents?.calendarIdentifier }

    /// Adds, moves or removes events so the calendar matches the plans.
    func sync(_ items: [CalendarItem]) {
        guard enabled, authorized else { return }
        guard let cal = calendarId.flatMap({ events.calendar(withIdentifier: $0) }) ?? events.defaultCalendarForNewEvents else { return }
        var ids = eventIds
        let wanted = Set(items.map { $0.id })
        for item in items {
            let ev = ids[item.id].flatMap { events.event(withIdentifier: $0) } ?? EKEvent(eventStore: events)
            if ev.calendar == nil { ev.calendar = cal }
            ev.title = item.title
            ev.startDate = item.start
            ev.endDate = item.end
            ev.timeZone = D.paris
            ev.location = item.location
            ev.notes = item.notes
            if ev.alarms?.isEmpty ?? true { ev.addAlarm(EKAlarm(relativeOffset: -2 * 3600)) }
            do {
                try events.save(ev, span: .thisEvent, commit: true)
                ids[item.id] = ev.eventIdentifier
            } catch {
                continue
            }
        }
        for (filmId, evId) in ids where !wanted.contains(filmId) {
            if let ev = events.event(withIdentifier: evId), ev.startDate > Date() {
                try? events.remove(ev, span: .thisEvent, commit: true)
            }
            ids[filmId] = nil
        }
        eventIds = ids
    }
}
