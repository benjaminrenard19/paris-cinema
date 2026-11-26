import Foundation
import Observation

/// Holds the film database and your lists (favourites, watched, plans).
/// Film data comes from the export of the Claude page "Paris Cinema Weeks";
/// your lists are saved on the phone in Documents/user.json.
struct ScreeningRow {
    let cinema: String
    let times: [String]
    var sessions: [Session] = []
}

@MainActor
@Observable
final class Store {
    private(set) var films: [Film] = []
    private(set) var weeks: [String] = []
    private(set) var byWeek: [String: [Film]] = [:]
    private(set) var index: [String: Film] = [:]
    private(set) var showtimes: [String: Showtimes] = [:]
    private(set) var cinemas: [Cinema] = Cinema.defaults
    private(set) var exportedAt: String?
    private(set) var usingBundledData = true

    var favs: Set<String> = []
    var seen: [String: SeenEntry] = [:]
    var plans: [String: Plan] = [:]
    var myCinemas: [String] = []
    var extraCinemas: [Cinema] = []

    var checkIn: CheckIn?
    /// The week's releases slideshow, and a cinema, opened from a notification.
    var releasesWeek: EditTarget?
    var openCinema: EditTarget?
    var linkedFileName: String? = UserDefaults.standard.string(forKey: "linkedName")
    var message: String?
    var lastFeedCheck: Date? = UserDefaults.standard.object(forKey: "lastFeedCheck") as? Date
    var feedStatus: String?
    private var feedBusy = false

    private let bookmarkKey = "linkedBookmark"

    init() {
        loadUser()
        loadData()
        refreshFromLinkedFile()
        syncNotifications()
        scheduleReleaseAlerts()
    }

    // MARK: Files

    private var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var dataURL: URL { docs.appendingPathComponent("paris-cinema.json") }
    var userURL: URL { docs.appendingPathComponent("user.json") }

    private func decode(_ data: Data) throws -> ExportFile {
        try JSONDecoder().decode(ExportFile.self, from: data)
    }

    private func loadData() {
        if let data = try? Data(contentsOf: dataURL), let f = try? decode(data), !f.films.isEmpty {
            apply(f); usingBundledData = false
        } else if let url = Bundle.main.url(forResource: "paris-cinema", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let f = try? decode(data) {
            apply(f); usingBundledData = true
            // A full export dropped into the Xcode project also brings your lists.
            if favs.isEmpty && seen.isEmpty && plans.isEmpty, let u = f.user { merge(u) }
        }
    }

    private func apply(_ f: ExportFile) {
        var seenIds = Set<String>()
        var list: [Film] = []
        for film in f.films where D.isDay(film.date) && !film.title.isEmpty {
            if seenIds.insert(film.id).inserted { list.append(film) }
        }
        list.sort { a, b in
            let ra = a.category == .R ? 1 : 0, rb = b.category == .R ? 1 : 0
            if ra != rb { return ra < rb }
            if a.releaseSize.rank != b.releaseSize.rank { return a.releaseSize.rank < b.releaseSize.rank }
            if a.date != b.date { return a.date < b.date }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        films = list
        byWeek = Dictionary(grouping: list.filter { !$0.isRepertory }, by: { $0.week })
        weeks = byWeek.keys.sorted()
        index = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        showtimes = f.showtimes ?? [:]
        if let c = f.cinemas, !c.isEmpty { cinemas = c }
        exportedAt = f.exportedAt
    }

    // MARK: Import

    @discardableResult
    func importFile(at url: URL, link: Bool) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let f = try decode(data)
            guard !f.films.isEmpty else { message = String(localized: "That file has no films in it."); return false }
            try data.write(to: dataURL, options: .atomic)
            apply(f)
            usingBundledData = false
            if let u = f.user { merge(u) }
            if link, let bm = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bm, forKey: bookmarkKey)
                UserDefaults.standard.set(url.lastPathComponent, forKey: "linkedName")
                linkedFileName = url.lastPathComponent
            }
            message = String(localized: "Loaded \(films.count) films across \(weeks.count) weeks.")
            return true
        } catch {
            message = String(localized: "This file couldn't be read. Export it again from the Claude page.")
            return false
        }
    }

    /// Re-reads the linked export (e.g. in iCloud Drive) if it is newer than what's loaded.
    func refreshFromLinkedFile(force: Bool = false) {
        guard let bm = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var readError: NSError?
        var raw: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readError) { u in
            raw = try? Data(contentsOf: u)
        }
        guard let data = raw, let f = try? decode(data), !f.films.isEmpty else {
            if force { message = String(localized: "The linked file couldn't be opened. Import it again.") }
            return
        }
        if force || (f.exportedAt ?? "") > (exportedAt ?? "") {
            try? data.write(to: dataURL, options: .atomic)
            apply(f)
            usingBundledData = false
            if let u = f.user { merge(u) }
            message = String(localized: "Updated: \(films.count) films.")
        } else if force {
            message = String(localized: "Already up to date.")
        }
        if stale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
    }

    // MARK: GitHub feed

    /// Downloads the latest films from GitHub (at most every 20 minutes unless forced).
    func refreshFromFeed(force: Bool = false) async {
        if feedBusy { return }
        if !force, let last = lastFeedCheck, Date().timeIntervalSince(last) < 20 * 60 { return }
        feedBusy = true
        defer { feedBusy = false }
        var req = URLRequest(url: Feed.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                feedStatus = String(localized: "GitHub didn't answer. Try again later.")
                return
            }
            let f = try decode(data)
            guard !f.films.isEmpty else { return }
            let now = Date()
            lastFeedCheck = now
            UserDefaults.standard.set(now, forKey: "lastFeedCheck")
            if force || usingBundledData || (f.exportedAt ?? "") > (exportedAt ?? "") {
                try? data.write(to: dataURL, options: .atomic)
                apply(f)
                usingBundledData = false
                feedStatus = String(localized: "Up to date: \(films.count) films.")
                updateDoneCinemas(notify: true)
            } else {
                feedStatus = String(localized: "Already up to date.")
            }
            scheduleReleaseAlerts()
        } catch {
            feedStatus = String(localized: "Couldn't reach GitHub. Check your connection.")
        }
    }

    func unlinkFile() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: "linkedName")
        linkedFileName = nil
    }

    // MARK: Your lists

    private func loadUser() {
        guard let data = try? Data(contentsOf: userURL), let u = try? JSONDecoder().decode(UserData.self, from: data) else { return }
        favs = Set(u.favs ?? [])
        seen = u.seen ?? [:]
        plans = u.plans ?? [:]
        myCinemas = u.myCinemas ?? []
        extraCinemas = u.extraCinemas ?? []
    }

    /// Adds anything from the page's lists that the phone doesn't have yet.
    private func merge(_ u: UserData) {
        for id in u.favs ?? [] { favs.insert(id) }
        for (k, v) in u.seen ?? [:] where seen[k] == nil && D.isDay(v.d) { seen[k] = v }
        for (k, v) in u.plans ?? [:] where plans[k] == nil && seen[k] == nil && D.isDay(v.d) { plans[k] = v }
        saveUser()
    }

    func saveUser() {
        let u = UserData(favs: favs.sorted(), seen: seen, plans: plans, myCinemas: myCinemas, extraCinemas: extraCinemas)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(u) { try? data.write(to: userURL, options: .atomic) }
        syncNotifications()
        syncCalendar()
    }

    // MARK: Plans and notifications

    /// When the film should be over: its running time (or 2 h 10) plus 20 minutes of trailers.
    func planEnd(_ id: String, _ p: Plan) -> Date? {
        let minutes = (index[id]?.duration ?? 130) + 20
        return D.stamp(day: p.d, time: p.t)?.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func syncNotifications() {
        let alerts: [PlanAlert] = plans.compactMap { entry -> PlanAlert? in
            let p = entry.value
            guard p.ok == true, let end = planEnd(entry.key, p) else { return nil }
            return PlanAlert(id: entry.key, title: p.title ?? index[entry.key]?.title ?? String(localized: "your film"), cinema: p.cn, end: end)
        }
        Notifier.shared.schedule(alerts)
    }

    /// Mirrors confirmed plans into the calendar chosen in Settings (when turned on).
    func syncCalendar() {
        let items: [CalendarItem] = plans.compactMap { entry -> CalendarItem? in
            let p = entry.value
            guard p.ok == true, seen[entry.key] == nil, let start = D.stamp(day: p.d, time: p.t) else { return nil }
            let film = index[entry.key]
            let address = p.ca ?? cinema(named: p.cn)?.address ?? ""
            let minutes = (film?.duration ?? 130) + 20
            return CalendarItem(id: entry.key,
                                title: "🎬 " + (p.title ?? film?.title ?? "Cinema"),
                                start: start,
                                end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                location: address.isEmpty ? p.cn : p.cn + ", " + address,
                                notes: [film?.dir.map { String(localized: "Directed by \($0)") }, film?.syn, String(localized: "Planned in Sloth Cinema")].compactMap { $0 }.joined(separator: "\n\n"))
        }
        CalendarSync.shared.sync(items)
    }

    // MARK: Showtimes

    func sameCinema(_ a: String, _ b: String) -> Bool {
        let x = a.folded, y = b.folded
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.contains(y) || y.contains(x)
    }

    /// Showtimes of a film at one cinema, from today on: [day: [times]].
    func showtimes(for id: String, at cinemaName: String) -> [String: [String]] {
        guard let list = showtimes[id]?.cinemas else { return [:] }
        let today = D.today
        var out: [String: Set<String>] = [:]
        for c in list where sameCinema(c.name ?? "", cinemaName) {
            for (day, times) in c.times ?? [:] where day >= today {
                out[day, default: []].formUnion(times)
            }
        }
        return out.mapValues { $0.sorted() }
    }

    /// The film's sessions at a cinema on a day, from now on, in the order you like them: your
    /// version first (or only, for foreign films, when you said it's a must).
    func sessions(_ id: String, at cinemaName: String, on day: String) -> [Session] {
        guard let list = showtimes[id]?.cinemas, !cinemaName.isEmpty, day >= D.today else { return [] }
        let now = D.stampString(Date()).time
        var times = Set<String>()
        var versions: [String: String] = [:]
        for c in list where sameCinema(c.name ?? "", cinemaName) {
            for t in c.times?[day] ?? [] where day > D.today || t >= now {
                times.insert(t)
                if let v = c.ver?[day]?[t] { versions[t] = v }
            }
        }
        let all = times.sorted().map { Session(time: $0, version: versions[$0]) }
        return ordered(all, for: id)
    }

    /// Applies your version preference to a film's sessions.
    func ordered(_ all: [Session], for id: String) -> [Session] {
        let pref = VersionPrefs.pref
        guard pref != "any", index[id]?.isFrench != true else { return all }
        func wanted(_ s: Session) -> Bool { pref == "vo" ? s.isOriginal : s.version == "VF" }
        if VersionPrefs.must {
            return all.filter { $0.version == nil || wanted($0) }
        }
        return all.filter { wanted($0) } + all.filter { !wanted($0) }
    }

    /// Sessions in the version you prefer when there are some, otherwise all of them.
    func preferredPool(_ all: [Session], for id: String) -> [Session] {
        let pref = VersionPrefs.pref
        guard pref != "any", index[id]?.isFrench != true else { return all }
        let mine = all.filter { pref == "vo" ? $0.isOriginal : $0.version == "VF" }
        return mine.isEmpty ? all : mine
    }

    /// The version of one session, when known.
    func version(_ id: String, at cinemaName: String, day: String, time: String) -> String? {
        for c in showtimes[id]?.cinemas ?? [] where sameCinema(c.name ?? "", cinemaName) {
            if let v = c.ver?[day]?[time] { return v }
        }
        return nil
    }

    /// Hide films you've seen from Films, cinemas and search (My profile).
    var hideSeen: Bool { UserDefaults.standard.object(forKey: "hideSeen") as? Bool ?? true }

    /// Every film with a session in the coming days (today to next Tuesday), for the Films page.
    var nowShowing: [Film] {
        let end = D.addDays(currentWeek, 6)
        let today = D.today
        let ids = showtimes.compactMap { entry -> String? in
            let days = (entry.value.cinemas ?? []).flatMap { ($0.times ?? [:]).keys }
            return days.contains { $0 >= today && $0 <= max(end, D.addDays(today, 6)) } ? entry.key : nil
        }
        let set = Set(ids)
        return films.filter { set.contains($0.id) && !(hideSeen && seen[$0.id] != nil) }
    }

    /// Films showing at a cinema, with their next day of sessions.
    func filmsShowing(at cinemaName: String) -> [Film] {
        let today = D.today
        return showtimes.compactMap { entry -> Film? in
            let shows = (entry.value.cinemas ?? []).contains { c in
                sameCinema(c.name ?? "", cinemaName) && (c.times ?? [:]).keys.contains { $0 >= today }
            }
            return shows ? index[entry.key] : nil
        }
    }

    /// The first day (from today) a film has sessions at a cinema, with them.
    func nextSessions(_ id: String, at cinemaName: String) -> (day: String, sessions: [Session])? {
        for i in 0..<14 {
            let d = D.addDays(D.today, i)
            let s = sessions(id, at: cinemaName, on: d)
            if !s.isEmpty { return (d, s) }
        }
        return nil
    }

    /// Today's remaining screenings of a film, at your cinemas if any show it, else anywhere.
    func todayScreenings(_ id: String) -> (rows: [ScreeningRow], mine: Bool) {
        guard let list = showtimes[id]?.cinemas else { return ([], false) }
        let today = D.today
        let now = D.stampString(Date()).time
        let rows: [ScreeningRow] = list.compactMap { c -> ScreeningRow? in
            guard let name = c.name, let times = c.times?[today] else { return nil }
            let left = ordered(times.filter { $0 >= now }.sorted().map { Session(time: $0, version: c.ver?[today]?[$0]) }, for: id)
            return left.isEmpty ? nil : ScreeningRow(cinema: name, times: left.map { $0.time }, sessions: left)
        }
        let mine = rows.filter { r in myCinemas.contains { sameCinema($0, r.cinema) } }
        return mine.isEmpty ? (Array(rows.prefix(8)), false) : (mine, true)
    }

    /// Plans you confirmed whose film has finished: time to say how it was.
    var duePlans: [(Film, Plan)] {
        let now = Date()
        return plannedFilms.filter { item in
            guard item.1.ok == true, let end = planEnd(item.0.id, item.1) else { return false }
            return end < now
        }
    }

    func planFilm(_ f: Film, day: String, time: String, cinemaName: String) {
        favs.insert(f.id)
        plans[f.id] = Plan(d: day, t: time, cn: cinemaName, ca: cinema(named: cinemaName)?.address, title: f.title, fd: f.date, ok: true)
        saveUser()
        Notifier.shared.requestPermission()
    }

    func confirmPlan(_ id: String) {
        guard var p = plans[id] else { return }
        p.ok = true
        plans[id] = p
        saveUser()
        Notifier.shared.requestPermission()
    }

    func removePlan(_ id: String) {
        plans[id] = nil
        saveUser()
    }

    /// "I'm not going to see it": drops the plan and the favourite.
    func dropPlan(_ id: String) {
        plans[id] = nil
        favs.remove(id)
        saveUser()
    }

    func openCheckIn(_ id: String, action: String) {
        guard index[id] != nil else { return }
        checkIn = CheckIn(id: id, action: action)
    }

    func setSeenDate(_ id: String, _ day: String) {
        guard var s = seen[id] else { return }
        s.d = day
        seen[id] = s
        saveUser()
    }

    func updateCustomSeen(_ id: String, title: String, day: String, rating: Int, category: Cat, poster: String? = nil) {
        guard var s = seen[id] else { return }
        s.t = title; s.d = day; s.r = max(0, min(5, rating)); s.c = category.rawValue
        if let poster { s.p = poster }
        seen[id] = s
        saveUser()
    }

    func isFav(_ id: String) -> Bool { favs.contains(id) }

    func toggleFav(_ f: Film) {
        if favs.contains(f.id) {
            favs.remove(f.id)
            plans[f.id] = nil
        } else {
            favs.insert(f.id)
            ensurePlan(f)
        }
        saveUser()
    }

    /// Your cinemas first (one that suits the film if possible), then the ones you go to most,
    /// otherwise a typical one.
    func defaultCinema(for f: Film) -> Cinema {
        let mine = myCinemas.compactMap { cinema(named: $0) }
        if let c = mine.first(where: { $0.type == f.venueType }) ?? mine.first { return c }
        if let c = habits.cinemas.lazy.compactMap({ self.cinema(named: $0) }).first { return c }
        return cinemas.first { $0.type == f.venueType } ?? cinemas.first ?? Cinema.defaults[0]
    }

    /// The built-in cinemas plus any you added from Apple Maps.
    var allCinemas: [Cinema] {
        let names = Set(cinemas.map { $0.name })
        return cinemas + extraCinemas.filter { !names.contains($0.name) }
    }

    func cinema(named n: String) -> Cinema? { allCinemas.first { $0.name == n } }

    func isPreferred(_ name: String) -> Bool { myCinemas.contains(name) }

    func togglePreferred(_ c: Cinema) {
        if let i = myCinemas.firstIndex(of: c.name) {
            myCinemas.remove(at: i)
        } else {
            if cinema(named: c.name) == nil { extraCinemas.append(c) }
            myCinemas.append(c.name)
        }
        saveUser()
    }

    /// Remembers a cinema found on Apple Maps so plans and directions can use it.
    func addExtra(_ c: Cinema) {
        guard cinema(named: c.name) == nil else { return }
        extraCinemas.append(c)
        saveUser()
    }

    /// A favourite you haven't seen gets a provisional plan: the day and time you usually go
    /// (Saturday evening until the app knows your habits), at your usual cinema.
    func ensurePlan(_ f: Film) {
        guard seen[f.id] == nil, plans[f.id] == nil else { return }
        let start = f.date > D.today ? f.date : D.today
        let c = defaultCinema(for: f)
        let h = habits
        let day = h.nextUsualDay(from: start)
        var time = h.usualTime ?? "20:00"
        // A known session close to your usual time beats a guess.
        let times = showtimes(for: f.id, at: c.name)[day] ?? []
        if let best = Habits.closest(times, to: time) { time = best }
        plans[f.id] = Plan(d: day, t: time, cn: c.name, ca: c.address, title: f.title, fd: f.date)
    }

    /// Any change you make to a plan confirms it.
    func updatePlan(_ id: String, _ p: Plan) {
        var np = p
        np.ok = true
        plans[id] = np
        saveUser()
        Notifier.shared.requestPermission()
    }

    func setSeen(_ f: Film, rating: Int, on day: String) {
        // Where and when you went (from your plan) teaches the app your habits.
        let p = plans[f.id]
        let old = seen[f.id]
        plans[f.id] = nil
        seen[f.id] = SeenEntry(d: day, r: max(0, min(5, rating)), t: f.title, fd: f.date, c: f.cat, dir: f.dir, o: f.origin, orig: f.orig,
                               cn: p?.cn ?? old?.cn, tm: p?.t ?? old?.tm)
        saveUser()
        updateDoneCinemas(notify: false)
    }

    /// Records where you saw a film (from its page, when there was no plan).
    func setSeenCinema(_ id: String, _ name: String?) {
        guard var s = seen[id] else { return }
        s.cn = name?.nilIfEmpty
        seen[id] = s
        saveUser()
    }

    func addCustomSeen(title: String, day: String, rating: Int, category: Cat, poster: String? = nil) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let id = "custom_" + slug(t) + "_" + day
        seen[id] = SeenEntry(d: day, r: max(0, min(5, rating)), t: t, fd: nil, c: category.rawValue, dir: nil, o: nil, orig: nil, p: poster)
        saveUser()
    }

    func removeSeen(_ id: String) {
        seen[id] = nil
        if let f = index[id], favs.contains(id) { ensurePlan(f) }
        saveUser()
    }

    // MARK: Lookups

    var currentWeek: String { D.weekOf(D.today) }

    /// This week if loaded, otherwise the nearest loaded week.
    var defaultWeek: String {
        let w = currentWeek
        if byWeek[w] != nil { return w }
        return weeks.first { $0 >= w } ?? weeks.last ?? w
    }

    func films(in week: String) -> [Film] { byWeek[week] ?? [] }

    func search(_ q: String) -> [Film] {
        let words = q.folded.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return films.filter { f in
            let t = f.searchText
            return words.allSatisfy { t.contains($0) }
        }.sorted { $0.date > $1.date }
    }

    var plannedFilms: [(Film, Plan)] {
        plans.compactMap { k, p in index[k].map { ($0, p) } }
            .sorted { ($0.1.d + $0.1.t) < ($1.1.d + $1.1.t) }
    }

    var otherFavourites: [Film] {
        favs.compactMap { index[$0] }.filter { plans[$0.id] == nil }.sorted { $0.date > $1.date }
    }

    /// For a year: films watched, and watched plus films still planned that year ("25 (28)").
    func yearCounts(_ y: Int) -> (watched: Int, total: Int) {
        let prefix = String(y)
        let watched = seen.values.filter { $0.d.hasPrefix(prefix) }.count
        let planned = plans.filter { $0.value.d.hasPrefix(prefix) && seen[$0.key] == nil }.count
        return (watched, watched + planned)
    }

    var seenYears: [Int] {
        var ys = Set(seen.values.compactMap { Int($0.d.prefix(4)) })
        ys.formUnion(plans.values.compactMap { Int($0.d.prefix(4)) })
        ys.insert(D.cal.component(.year, from: Date()))
        return ys.sorted(by: >)
    }

    func watched(inYear y: Int) -> [(String, SeenEntry)] {
        seen.filter { $0.value.d.hasPrefix(String(y)) }
            .map { ($0.key, $0.value) }
            .sorted { $0.1.d > $1.1.d }
    }

    /// Showtimes from today on, earliest first.
    func showings(for id: String) -> [Showing] {
        guard let s = showtimes[id], let list = s.cinemas else { return [] }
        let today = D.today
        var out: [Showing] = []
        for c in list {
            for (day, times) in c.times ?? [:] where day >= today {
                for t in times { out.append(Showing(day: day, time: t, cinema: c.name ?? String(localized: "Cinema"), address: c.address ?? "")) }
            }
        }
        return out.sorted { ($0.day + $0.time) < ($1.day + $1.time) }
    }

    var dataSummary: String {
        guard let first = weeks.first, let last = weeks.last else { return String(localized: "No films loaded.") }
        return String(localized: "\(films.count) films · \(weeks.count) weeks · \(D.fmt(first, "d MMM yyyy")) to \(D.fmt(last, "d MMM yyyy"))")
    }
}
