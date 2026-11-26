import SwiftUI
import UserNotifications
import BackgroundTasks

// MARK: - Weekly releases and "new film at a cinema you've finished"

enum AlertPrefs {
    static var releasesOn: Bool { UserDefaults.standard.object(forKey: "releasesOn") as? Bool ?? true }
    /// 1 = Sunday … 7 = Saturday. Tuesday by default.
    static var releasesDay: Int { UserDefaults.standard.object(forKey: "releasesDay") as? Int ?? 3 }
    /// Minutes after midnight. 20:00 by default.
    static var releasesTime: Int { UserDefaults.standard.object(forKey: "releasesTime") as? Int ?? 20 * 60 }
    static var cinemasOn: Bool { UserDefaults.standard.object(forKey: "doneCinemasOn") as? Bool ?? true }

    static let refreshTask = "com.benjaminrenard.pariscinema.refresh"

    /// What you hear about each of your cinemas: 0 nothing, 1 new films you haven't seen,
    /// 2 every change of programme (for cinemas that show one film at a time). Starred cinemas start at 1.
    static func cinemaMode(_ name: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: "cinemaAlerts") as? [String: Int])?[name] ?? 1
    }

    static func setCinemaMode(_ name: String, _ mode: Int) {
        var all = UserDefaults.standard.dictionary(forKey: "cinemaAlerts") as? [String: Int] ?? [:]
        all[name] = mode
        UserDefaults.standard.set(all, forKey: "cinemaAlerts")
    }
}

extension Store {
    /// The week a releases notification is about: from Wednesday to Saturday the week that just
    /// started; from Sunday to Tuesday the one that starts next Wednesday.
    func releaseWeek(for date: Date) -> String {
        let day = D.str(date)
        let wd = D.weekday(day)
        let wednesday = D.weekOf(day)
        return wd >= 4 ? wednesday : D.addDays(wednesday, 7)
    }

    /// New films of a week, biggest releases first (event screenings left out).
    func releases(in week: String) -> [Film] {
        films(in: week).filter { $0.category != .E }
    }

    /// Schedules the next four weekly notifications, each naming that week's films when known.
    func scheduleReleaseAlerts(ask: Bool = false) {
        guard AlertPrefs.releasesOn else {
            Notifier.shared.scheduleReleases([])
            return
        }
        var comps = DateComponents()
        comps.weekday = AlertPrefs.releasesDay
        comps.hour = AlertPrefs.releasesTime / 60
        comps.minute = AlertPrefs.releasesTime % 60
        var after = Date()
        var items: [ReleaseAlert] = []
        for _ in 0..<4 {
            guard let next = D.cal.nextDate(after: after, matching: comps, matchingPolicy: .nextTime) else { break }
            let week = releaseWeek(for: next)
            items.append(ReleaseAlert(week: week, date: next, titles: releases(in: week).map(\.title)))
            after = next
        }
        if ask { Notifier.shared.requestPermission() }
        Notifier.shared.scheduleReleases(items)
    }

    /// Cinemas where you've seen everything showing, with the films that were showing then.
    var doneCinemas: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: "doneCinemas") as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "doneCinemas") }
    }

    /// True when a cinema has films showing and you've seen them all.
    func seenAll(at name: String) -> Bool {
        let showing = filmsShowing(at: name)
        return !showing.isEmpty && showing.allSatisfy { seen[$0.id] != nil }
    }

    /// Remembers the cinemas you've finished, and after new session times arrive, tells you
    /// when one of them shows a film you haven't seen. Only your cinemas, and others with
    /// at least three films, count, so a one-film cinema doesn't ping you.
    func updateDoneCinemas(notify: Bool) {
        var done = doneCinemas
        for c in allCinemas {
            let showing = filmsShowing(at: c.name)
            guard !showing.isEmpty else { continue }
            let unseen = showing.filter { seen[$0.id] == nil }
            if unseen.isEmpty {
                if isPreferred(c.name) || showing.count >= 3 { done[c.name] = showing.map(\.id) }
            } else if let was = done[c.name] {
                let fresh = unseen.filter { !was.contains($0.id) }
                let coveredByMine = isPreferred(c.name) && AlertPrefs.cinemaMode(c.name) > 0
                if notify, AlertPrefs.cinemasOn, !coveredByMine, let first = fresh.first {
                    let n = fresh.count - 1
                    let body = n == 0
                        ? String(localized: "\(first.title) is showing there, and you haven't seen it yet.")
                        : String(localized: "\(first.title) and \(n) more you haven't seen are showing there.")
                    Notifier.shared.notifyNow(id: "cinema-" + c.name,
                                              title: String(localized: "New at \(c.name)"),
                                              body: body,
                                              info: ["type": "cinema", "cinema": c.name])
                }
                done[c.name] = nil
            }
        }
        doneCinemas = done
    }

    /// Films seen showing at each of your cinemas, with the last day they were (kept 30 days).
    var cinemaKnown: [String: [String: String]] {
        get { UserDefaults.standard.dictionary(forKey: "cinemaKnown") as? [String: [String: String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "cinemaKnown") }
    }

    /// After new session times arrive: tells you about new films at your cinemas, as set in Settings
    /// (new films you haven't seen, or every change). A cinema just starred is only remembered.
    func updateCinemaAlerts(notify: Bool) {
        var known = cinemaKnown
        let today = D.today
        let cutoff = D.addDays(today, -30)
        for name in myCinemas {
            let showing = filmsShowing(at: name)
            guard !showing.isEmpty else { continue }
            let isNew = known[name] == nil
            var k = (known[name] ?? [:]).filter { $0.value >= cutoff }
            let fresh = showing.filter { k[$0.id] == nil }
            let mode = AlertPrefs.cinemaMode(name)
            if notify, !isNew, mode > 0 {
                let list = mode == 1 ? fresh.filter { seen[$0.id] == nil } : fresh
                if let f = list.first {
                    let day = D.fmt(nextSessions(f.id, at: name)?.day ?? today, "EEEE d MMMM")
                    let n = list.count - 1
                    let title = mode == 1 ? String(localized: "New at \(name)") : String(localized: "Programme change at \(name)")
                    let body: String
                    if n > 0 {
                        body = mode == 1 ? String(localized: "\(f.title) and \(n) more you haven't seen, from \(day).")
                                         : String(localized: "\(f.title) and \(n) other films, from \(day).")
                    } else if mode == 1 || seen[f.id] == nil {
                        body = String(localized: "\(f.title) from \(day). You haven't seen it yet.")
                    } else {
                        body = String(localized: "\(f.title) from \(day). You've seen it.")
                    }
                    Notifier.shared.notifyNow(id: "mine-" + name, title: title, body: body,
                                              info: ["type": "cinema", "cinema": name])
                }
            }
            for f in showing { k[f.id] = today }
            known[name] = k
        }
        cinemaKnown = known.filter { myCinemas.contains($0.key) }
    }

    /// Runs when iOS wakes the app in the background: new times, then the alerts that depend on them.
    func backgroundRefresh() async {
        await refreshFromFeed(force: true)
        scheduleBackgroundRefresh()
    }

    /// Asks iOS to wake the app in a few hours to check for new times.
    nonisolated func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: AlertPrefs.refreshTask)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// What a tap on a notification opens.
    func handle(_ tap: NotificationTap) {
        switch tap.type {
        case "releases":
            releasesWeek = EditTarget(id: tap.value.isEmpty ? releaseWeek(for: Date()) : tap.value)
        case "cinema":
            if !tap.value.isEmpty { openCinema = EditTarget(id: tap.value) }
        default:
            if !tap.film.isEmpty { openCheckIn(tap.film, action: tap.action) }
        }
    }
}

struct ReleaseAlert {
    let week: String
    let date: Date
    let titles: [String]
}

// MARK: - The week's releases, one poster at a time

struct ReleasesSlideshowView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let week: String
    @State private var page = 0
    @State private var open: EditTarget?

    var body: some View {
        let list = store.releases(in: week)
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if list.isEmpty {
                    ContentUnavailableView("No releases yet", systemImage: "film",
                                           description: Text("The films out on \(D.fmt(week, "EEEE d MMMM")) arrive on Tuesday evening."))
                        .foregroundStyle(.white)
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                            slide(f).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: list.count <= 20 ? .always : .never))
                }
            }
            .navigationTitle(String(localized: "Out \(D.fmt(week, "EEEE d MMMM"))"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !list.isEmpty {
                        Text("\(min(page + 1, list.count)) / \(list.count)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .sheet(item: $open) { t in
                NavigationStack {
                    FilmDetailView(id: t.id)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Back to the slideshow") { open = nil } } }
                }
                .environment(store)
            }
        }
        .onAppear { UserDefaults.standard.set(week, forKey: "releasesSeenWeek") }
    }

    private func slide(_ f: Film) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                PosterTile(title: f.title, cat: f.category, width: 230, url: f.poster)
                    .shadow(color: f.category.color.opacity(0.5), radius: 24, y: 8)
                    .padding(.top, 12)
                    .onTapGesture { open = EditTarget(id: f.id) }
                VStack(spacing: 6) {
                    Text(f.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text([D.fmtCap(f.date, "EEEE d MMMM"), f.durationText, f.dir].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        CatBadge(cat: f.category)
                        Text(f.releaseSize.label).font(.caption2).foregroundStyle(.white.opacity(0.6))
                        if let p = f.press { Text(String(localized: "Critics \(String(format: "%.1f", p))")).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.8)) }
                    }
                    if let syn = f.syn, !syn.isEmpty {
                        Text(syn).font(.callout).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(5).multilineTextAlignment(.center).padding(.top, 4)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                HStack(spacing: 12) {
                    Button { store.toggleFav(f) } label: {
                        Label(store.isFav(f.id) ? "In my list" : "Add to my list", systemImage: store.isFav(f.id) ? "star.fill" : "star")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(hex: 0xE0A800).opacity(store.isFav(f.id) ? 1 : 0.25), in: Capsule())
                            .foregroundStyle(store.isFav(f.id) ? .black : Color(hex: 0xE0A800))
                    }
                    Button { open = EditTarget(id: f.id) } label: {
                        Label("More", systemImage: "info.circle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Settings: notifications

struct NotificationSettings: View {
    @Environment(Store.self) private var store
    @State private var modes: [String: Int] = [:]
    @AppStorage("releasesOn") private var releasesOn = true
    @AppStorage("releasesDay") private var releasesDay = 3
    @AppStorage("releasesTime") private var releasesTime = 20 * 60
    @AppStorage("doneCinemasOn") private var cinemasOn = true
    @State private var preview: EditTarget?

    private var time: Binding<Date> {
        Binding(get: {
            D.cal.date(bySettingHour: releasesTime / 60, minute: releasesTime % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = D.cal.dateComponents([.hour, .minute], from: d)
            releasesTime = (c.hour ?? 20) * 60 + (c.minute ?? 0)
        })
    }

    private func mode(_ name: String) -> Binding<Int> {
        Binding(get: { modes[name] ?? AlertPrefs.cinemaMode(name) },
                set: { modes[name] = $0; AlertPrefs.setCinemaMode(name, $0) })
    }

    var body: some View {
        Section {
            Toggle("This week's releases", isOn: $releasesOn)
                .onChange(of: releasesOn) { _, on in store.scheduleReleaseAlerts(ask: on) }
                .onChange(of: releasesDay) { _, _ in store.scheduleReleaseAlerts() }
                .onChange(of: releasesTime) { _, _ in store.scheduleReleaseAlerts() }
            if releasesOn {
                Picker("Day", selection: $releasesDay) {
                    ForEach([4, 5, 6, 7, 1, 2, 3], id: \.self) { d in Text(D.weekdayName(d).capitalized).tag(d) }
                }
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            Button {
                preview = EditTarget(id: store.releaseWeek(for: Date()))
            } label: {
                Label("See this week's releases", systemImage: "play.rectangle.on.rectangle")
            }
            .fullScreenCover(item: $preview) { t in ReleasesSlideshowView(week: t.id).environment(store) }
        } header: {
            Text("Notifications")
        } footer: {
            Text("A slideshow of the posters out on Wednesday. Turn it off to hear only about your cinemas.")
        }
        Section {
            if store.myCinemas.isEmpty {
                NavigationLink {
                    FavouriteCinemasList(intro: String(localized: "Star the cinemas you go to. They come first everywhere, with their session times."))
                        .navigationTitle("My cinemas")
                } label: {
                    Text("Star the cinemas you go to: they appear here.")
                }
            }
            ForEach(store.myCinemas, id: \.self) { name in
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.headline)
                    Picker(name, selection: mode(name)) {
                        Text("Off").tag(0)
                        Text("New films").tag(1)
                        Text("Film changes").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 2)
            }
            Toggle("New film at a cinema you've finished", isOn: $cinemasOn)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Label("Allow notifications in iPhone Settings", systemImage: "bell.badge")
            }
        } header: {
            Text("Your cinemas")
        } footer: {
            Text("Every cinema you star joins this list, set to New films. New films: a film you haven't seen starts there. Film changes: for cinemas like the Max Linder that show one film at a time, you hear when it changes. After each confirmed plan, a notification asks how the film was.")
        }
    }
}

// MARK: - VO or VF

/// Which version you prefer, and whether it's a must. Used at first launch and in Settings.
struct VersionQuestions: View {
    @AppStorage("versionPref") private var pref = "any"
    @AppStorage("versionMust") private var must = false

    var body: some View {
        Section {
            option(String(localized: "Original version"), String(localized: "VO or VOST: the actors' own voices, with French subtitles"), on: pref == "vo") { pref = "vo" }
            option(String(localized: "French version"), String(localized: "VF: dubbed in French"), on: pref == "vf") { pref = "vf" }
            option(String(localized: "No preference"), String(localized: "Every session, in time order"), on: pref == "any") { pref = "any"; must = false }
        } header: {
            Text("Which version do you prefer?")
        }
        if pref != "any" {
            Section {
                option(pref == "vo" ? String(localized: "Yes, only the original version") : String(localized: "Yes, only VF"),
                       String(localized: "Other sessions are hidden"), on: must) { must = true }
                option(pref == "vo" ? String(localized: "No, VF is fine too") : String(localized: "No, the original version is fine too"),
                       String(localized: "Your version comes first, the others after"), on: !must) { must = false }
            } header: {
                Text(pref == "vo" ? "For an English-language film, is VO a must?" : "For a foreign film, is VF a must?")
            } footer: {
                Text("French films always show every session. VF, VO and VOST appear under each time. You can change this in Settings.")
            }
        }
    }

    private func option(_ title: String, _ detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(Color.theme).fontWeight(.semibold) }
            }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Asked once to people who set the app up before versions existed.
struct VersionSetupView: View {
    let onDone: () -> Void
    var body: some View {
        NavigationStack {
            List { VersionQuestions() }
                .navigationTitle("VO or VF?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
                .safeAreaInset(edge: .top) {
                    Text("Session times now show VF, VO or VOST. Tell Sloth Cinema what you like to watch.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 24).padding(.top, 8)
                }
        }
    }
}
