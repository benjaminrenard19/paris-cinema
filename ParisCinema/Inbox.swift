import SwiftUI
import UIKit
import UserNotifications

/// What's waiting for you, behind the 🎥 button on the Films page.
struct InboxItem: Identifiable {
    enum Kind { case rate, today, soon, confirm, showing, week }
    let id: String
    let kind: Kind
    let filmId: String?
    let title: String
    let detail: String
}

extension Store {
    /// The same number as the 🎥 button, on the app icon.
    func updateIconBadge(_ n: Int? = nil) {
        UNUserNotificationCenter.current().setBadgeCount(n ?? inboxBadge) { _ in }
    }

    /// Items you hid from the list (the week's releases), by id.
    var hiddenInbox: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "inboxHidden") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(60)), forKey: "inboxHidden") }
    }

    /// "Mark as seen" on a film in What's new (or on its notification): watched, on the planned day.
    func markSeenFromInbox(_ id: String) {
        guard let f = index[id], seen[id] == nil else { return }
        let day = min(plans[id]?.d ?? D.today, D.today)
        setSeen(f, rating: 0, on: day)
        updateIconBadge()
    }

    func hideInboxItem(_ id: String) {
        var h = hiddenInbox
        h.insert(id)
        hiddenInbox = h
        updateIconBadge()
    }

    var inbox: [InboxItem] {
        var out: [InboxItem] = []
        let today = D.today
        let now = D.stampString(Date()).time
        for (f, p) in duePlans {
            out.append(InboxItem(id: "rate-" + f.id, kind: .rate, filmId: f.id,
                                 title: String(localized: "How was \(f.title)?"),
                                 detail: String(localized: "Planned \(D.fmt(p.d, "EEE d MMM")) · \(p.t) · \(p.cn). Rate it, or pick another day.")))
        }
        for (f, p) in plannedFilms where seen[f.id] == nil {
            if p.ok == true, p.d == today, (planEnd(f.id, p) ?? Date()) > Date() {
                out.append(InboxItem(id: "today-" + f.id, kind: .today, filmId: f.id,
                                     title: String(localized: "Today: \(f.title)"),
                                     detail: String(localized: "\(p.t) at \(p.cn)")))
            } else if p.ok == true, p.d > today, p.d <= D.addDays(today, 7) {
                out.append(InboxItem(id: "soon-" + f.id, kind: .soon, filmId: f.id,
                                     title: f.title,
                                     detail: String(localized: "\(D.fmt(p.d, "EEEE d MMMM")) at \(p.t) · \(p.cn)")))
            } else if p.ok != true, p.d >= today, p.d <= D.addDays(today, 7) {
                out.append(InboxItem(id: "confirm-" + f.id, kind: .confirm, filmId: f.id,
                                     title: String(localized: "Confirm your plan for \(f.title)"),
                                     detail: String(localized: "Provisional: \(D.fmt(p.d, "EEEE d MMMM")) at \(p.t) · \(p.cn)")))
            }
        }
        // Favourites you haven't planned that are on today.
        for f in otherFavourites where seen[f.id] == nil && f.date <= today {
            let rows = todayScreenings(f.id)
            if let r = rows.rows.first {
                let times = r.times.filter { $0 >= now }.prefix(4).joined(separator: ", ")
                guard !times.isEmpty else { continue }
                out.append(InboxItem(id: "showing-" + f.id, kind: .showing, filmId: f.id,
                                     title: String(localized: "\(f.title) is on today"),
                                     detail: String(localized: "\(r.cinema): \(times)")))
            }
        }
        let week = releaseWeek(for: Date())
        let fresh = releases(in: week).count
        if fresh > 0 {
            out.append(InboxItem(id: "week-" + week, kind: .week, filmId: nil,
                                 title: week > today ? String(localized: "\(fresh) films out \(D.fmt(week, "EEEE d MMMM"))")
                                                     : String(localized: "\(fresh) films out this week"),
                                 detail: String(localized: "Swipe through the posters")))
        }
        let hidden = hiddenInbox
        return out.filter { !hidden.contains($0.id) }
    }

    /// The number on the 🎥 button: films to rate, plans today and plans to confirm.
    var inboxBadge: Int {
        inbox.filter { [InboxItem.Kind.rate, InboxItem.Kind.today, InboxItem.Kind.confirm].contains($0.kind) }.count
    }
}

struct InboxView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let items = store.inbox
                section(String(localized: "To rate"), items.filter { $0.kind == .rate }, emoji: "⭐️")
                section(String(localized: "Today"), items.filter { $0.kind == .today }, emoji: "🎟️")
                section(String(localized: "To confirm"), items.filter { $0.kind == .confirm }, emoji: "✍️")
                section(String(localized: "Coming up"), items.filter { $0.kind == .soon }, emoji: "🗓️")
                section(String(localized: "Your favourites on today"), items.filter { $0.kind == .showing }, emoji: "🍿")
                section(String(localized: "This week"), items.filter { $0.kind == .week }, emoji: "🆕")
                if items.isEmpty {
                    ContentUnavailableView("Nothing new", systemImage: "film",
                                           description: Text("Plans, films to rate and your favourites showing today appear here."))
                }
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Label("Notification settings", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("After each confirmed plan, Sloth Cinema sends a notification when the film should be over, to ask how it was. Choose the day of the weekly releases notification in Settings.")
                }
            }
            .navigationTitle("🎥 What's new")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [InboxItem], emoji: String) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    entry(item, emoji: emoji)
                        .swipeActions(edge: .trailing) {
                            if let id = item.filmId {
                                Button { store.markSeenFromInbox(id) } label: { Label("Mark as seen", systemImage: "checkmark.circle") }
                                    .tint(.green)
                            } else {
                                Button { store.hideInboxItem(item.id) } label: { Label("Hide", systemImage: "eye.slash") }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func entry(_ item: InboxItem, emoji: String) -> some View {
                    if item.kind == .rate, let id = item.filmId {
                        Button {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                store.checkIn = CheckIn(id: id, action: "")
                            }
                        } label: { row(item, emoji: emoji) }
                    } else if let id = item.filmId {
                        NavigationLink(value: id) { row(item, emoji: emoji) }
                    } else if item.kind == .week {
                        Button {
                            dismiss()
                            let week = String(item.id.dropFirst(5))
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                store.releasesWeek = EditTarget(id: week)
                            }
                        } label: { row(item, emoji: emoji) }
                    } else {
                        row(item, emoji: emoji)
                    }
    }

    private func row(_ item: InboxItem, emoji: String) -> some View {
        HStack(spacing: 12) {
            if let id = item.filmId, let f = store.index[id] {
                PosterTile(title: f.title, cat: f.category, width: 36, url: f.poster)
            } else {
                Text(emoji).font(.title2).frame(width: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).foregroundStyle(.primary)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let id = item.filmId, item.kind != .rate {
                Button { store.markSeenFromInbox(id) } label: {
                    Text("Mark as seen")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// The 🎥 button with the number of things waiting.
struct InboxButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("🎥")
                .font(.title3)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 9, y: -7)
                    }
                }
        }
        .accessibilityLabel(count > 0 ? String(localized: "What's new, \(count) waiting") : String(localized: "What's new"))
    }
}
