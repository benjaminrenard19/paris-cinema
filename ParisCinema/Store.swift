import Foundation
import Observation

/// Holds the film database and your lists (favourites, watched, plans).
/// Film data comes from the export of the Claude page "Paris Cinema Weeks";
/// your lists are saved on the phone in Documents/user.json.
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
        byWeek = Dictionary(grouping: list, by: { $0.week })
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
            guard !f.films.isEmpty else { message = "That file has no films in it."; return false }
            try data.write(to: dataURL, options: .atomic)
            apply(f)
            usingBundledData = false
            if let u = f.user { merge(u) }
            if link, let bm = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bm, forKey: bookmarkKey)
                UserDefaults.standard.set(url.lastPathComponent, forKey: "linkedName")
                linkedFileName = url.lastPathComponent
            }
            message = "Loaded \(films.count) films across \(weeks.count) weeks."
            return true
        } catch {
            message = "This file couldn't be read. Export it again from the Claude page."
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
            if force { message = "The linked file couldn't be opened. Import it again." }
            return
        }
        if force || (f.exportedAt ?? "") > (exportedAt ?? "") {
            try? data.write(to: dataURL, options: .atomic)
            apply(f)
            usingBundledData = false
            if let u = f.user { merge(u) }
            message = "Updated: \(films.count) films."
        } else if force {
            message = "Already up to date."
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
                feedStatus = "GitHub didn't answer. Try again later."
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
                feedStatus = "Up to date: \(films.count) films."
            } else {
                feedStatus = "Already up to date."
            }
        } catch {
            feedStatus = "Couldn't reach GitHub. Check your connection."
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

    /// Your cinemas first (one that suits the film if possible), otherwise a typical one.
    func defaultCinema(for f: Film) -> Cinema {
        let mine = myCinemas.compactMap { cinema(named: $0) }
        if let c = mine.first(where: { $0.type == f.venueType }) ?? mine.first { return c }
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

    /// A favourite you haven't seen gets a provisional Saturday-evening plan.
    func ensurePlan(_ f: Film) {
        guard seen[f.id] == nil, plans[f.id] == nil else { return }
        let start = f.date > D.today ? f.date : D.today
        let c = defaultCinema(for: f)
        plans[f.id] = Plan(d: D.saturdayAfter(start), t: "20:00", cn: c.name, ca: c.address, title: f.title, fd: f.date)
    }

    func updatePlan(_ id: String, _ p: Plan) {
        plans[id] = p
        saveUser()
    }

    func setSeen(_ f: Film, rating: Int, on day: String) {
        plans[f.id] = nil
        seen[f.id] = SeenEntry(d: day, r: max(0, min(5, rating)), t: f.title, fd: f.date, c: f.cat, dir: f.dir, o: f.origin, orig: f.orig)
        saveUser()
    }

    func addCustomSeen(title: String, day: String, rating: Int, category: Cat) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let id = "custom_" + slug(t) + "_" + day
        seen[id] = SeenEntry(d: day, r: max(0, min(5, rating)), t: t, fd: nil, c: category.rawValue, dir: nil, o: nil, orig: nil)
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

    var seenYears: [Int] {
        var ys = Set(seen.values.compactMap { Int($0.d.prefix(4)) })
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
                for t in times { out.append(Showing(day: day, time: t, cinema: c.name ?? "Cinema", address: c.address ?? "")) }
            }
        }
        return out.sorted { ($0.day + $0.time) < ($1.day + $1.time) }
    }

    var dataSummary: String {
        guard let first = weeks.first, let last = weeks.last else { return "No films loaded." }
        return "\(films.count) films · \(weeks.count) weeks · \(D.fmt(first, "d MMM yyyy")) to \(D.fmt(last, "d MMM yyyy"))"
    }
}
