import Foundation
import SwiftUI
import CoreLocation

// MARK: - Categories and release sizes (same codes as the Claude page)

enum Cat: String, CaseIterable, Identifiable {
    case B, A, C, D, T, V, M, E, R, O

    var id: String { rawValue }

    /// Shown in the app, in the iPhone's language.
    var label: String { NSLocalizedString(englishLabel, comment: "Film category") }
    var short: String { NSLocalizedString(englishShort, comment: "Film category, short") }

    /// As written in the data files.
    var englishLabel: String {
        switch self {
        case .B: return "Blockbuster"
        case .A: return "Animation & family"
        case .C: return "Comedy"
        case .D: return "Drama"
        case .T: return "Thriller / action / sci-fi"
        case .V: return "Documentary"
        case .M: return "Biopic & music"
        case .E: return "Event screening"
        case .R: return "Re-release / classic"
        case .O: return "Other"
        }
    }

    var englishShort: String {
        switch self {
        case .B: return "Blockbuster"
        case .A: return "Animation"
        case .C: return "Comedy"
        case .D: return "Drama"
        case .T: return "Thriller"
        case .V: return "Documentary"
        case .M: return "Biopic & music"
        case .E: return "Event"
        case .R: return "Classic"
        case .O: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .B: return "sparkles"
        case .A: return "balloon.2.fill"
        case .C: return "face.smiling"
        case .D: return "theatermasks.fill"
        case .T: return "bolt.fill"
        case .V: return "globe.europe.africa.fill"
        case .M: return "music.mic"
        case .E: return "music.note.house.fill"
        case .R: return "film.stack"
        case .O: return "film"
        }
    }

    var color: Color {
        switch self {
        case .B: return Color(hex: 0x6B3FD6)
        case .A: return Color(hex: 0xD98200)
        case .C: return Color(hex: 0xE2581D)
        case .D: return Color(hex: 0x1F5FBF)
        case .T: return Color(hex: 0xC41E3A)
        case .V: return Color(hex: 0x1D8A4A)
        case .M: return Color(hex: 0xB3268A)
        case .E: return Color(hex: 0x0D8A8A)
        case .R: return Color(hex: 0x77706E)
        case .O: return Color(hex: 0x8A8480)
        }
    }

    static func from(_ s: String?) -> Cat {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return .O }
        if let c = Cat(rawValue: s) { return c }
        let low = s.lowercased()
        return Cat.allCases.first { $0.englishLabel.lowercased() == low } ?? .O
    }
}

enum ReleaseSize: String, CaseIterable, Identifiable {
    case W, M, L, X

    var id: String { rawValue }

    var label: String { NSLocalizedString(englishLabel, comment: "Release size") }

    var englishLabel: String {
        switch self {
        case .W: return "Wide"
        case .M: return "Mid"
        case .L: return "Limited"
        case .X: return "One-off / event"
        }
    }

    var rank: Int {
        switch self {
        case .W: return 0
        case .M: return 1
        case .L: return 2
        case .X: return 3
        }
    }

    static func from(_ s: String?) -> ReleaseSize {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return .L }
        if let r = ReleaseSize(rawValue: s) { return r }
        let low = s.lowercased()
        return ReleaseSize.allCases.first { $0.englishLabel.lowercased() == low } ?? .L
    }
}

// MARK: - Film

struct Film: Identifiable, Hashable, Codable {
    var id: String
    var week: String
    var date: String
    var title: String
    var cat: String
    var genre: String?
    var origin: String?
    var size: String
    var dir: String?
    var cast: String?
    var orig: String?
    var note: String?
    var syn: String?
    var prod: String?
    var poster: String?
    var press: Double?      // AlloCiné press rating out of 5
    var spect: Double?      // AlloCiné audience rating out of 5
    var duration: Int?      // minutes
    var ac: Int?            // AlloCiné film id
    var rep: Bool?          // a classic or older film still showing, not a release of the week

    enum CodingKeys: String, CodingKey {
        case id, week, date, title, cat, genre, origin, size, dir, cast, orig, note, syn, prod, poster, press, spect, duration, ac, rep
    }

    var isRepertory: Bool { rep == true }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        title = try c.decode(String.self, forKey: .title)
        let rawId = try c.decodeIfPresent(String.self, forKey: .id)
        id = (rawId?.isEmpty == false) ? rawId! : date + "_" + slug(title)
        let rawWeek = try c.decodeIfPresent(String.self, forKey: .week)
        week = (rawWeek?.isEmpty == false) ? rawWeek! : D.weekOf(date)
        cat = try c.decodeIfPresent(String.self, forKey: .cat) ?? "O"
        size = try c.decodeIfPresent(String.self, forKey: .size) ?? "L"
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        dir = try c.decodeIfPresent(String.self, forKey: .dir)
        cast = try c.decodeIfPresent(String.self, forKey: .cast)
        orig = try c.decodeIfPresent(String.self, forKey: .orig)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        syn = try c.decodeIfPresent(String.self, forKey: .syn)
        prod = try c.decodeIfPresent(String.self, forKey: .prod)
        poster = try? c.decodeIfPresent(String.self, forKey: .poster)
        press = try? c.decodeIfPresent(Double.self, forKey: .press)
        spect = try? c.decodeIfPresent(Double.self, forKey: .spect)
        duration = try? c.decodeIfPresent(Int.self, forKey: .duration)
        ac = try? c.decodeIfPresent(Int.self, forKey: .ac)
        rep = try? c.decodeIfPresent(Bool.self, forKey: .rep)
    }

    /// Average of the press and audience ratings that exist.
    var average: Double? {
        let r = [press, spect].compactMap { $0 }
        return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
    }

    var durationText: String? {
        guard let d = duration else { return nil }
        return d >= 60 ? "\(d / 60)h \(String(format: "%02d", d % 60))" : "\(d) min"
    }

    var year: String { String(date.prefix(4)) }

    /// Every genre of the film, as lowercase keys: "Comedy-drama, thriller" gives comedy, drama, thriller.
    var genres: [String] {
        guard let g = genre else { return [] }
        var out: [String] = []
        for raw in g.components(separatedBy: CharacterSet(charactersIn: ",/")) {
            let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !t.isEmpty else { continue }
            var parts = [t]
            if t == "comedy-drama" { parts = ["comedy", "drama"] }
            else if t.hasSuffix(" drama") { parts = [String(t.dropLast(6)), "drama"] }
            for p in parts where !out.contains(p) { out.append(p) }
        }
        return out
    }

    /// A genre key in the app's language, capitalised.
    static func genreLabel(_ key: String) -> String {
        let s = D.isFrench ? NSLocalizedString(key, tableName: "Data", value: key, comment: "Genre or country") : key
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Genres and countries in the app's language (the data is written in English).
    var genreText: String? { genre.map { Film.localizedList($0, lowerAfterFirst: true) } }
    var originText: String? { origin.map { Film.localizedList($0, lowerAfterFirst: false) } }

    static func localizedList(_ s: String, lowerAfterFirst: Bool) -> String {
        guard D.isFrench else { return s }
        var out: [String] = []
        for raw in s.components(separatedBy: CharacterSet(charactersIn: ",/")) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let fr = NSLocalizedString(t.lowercased(), tableName: "Data", value: t, comment: "Genre or country")
            if out.isEmpty || !lowerAfterFirst {
                out.append(fr.prefix(1).uppercased() + fr.dropFirst())
            } else {
                out.append(fr.lowercased())
            }
        }
        return out.joined(separator: ", ")
    }

    var category: Cat { Cat.from(cat) }
    var releaseSize: ReleaseSize { ReleaseSize.from(size) }

    /// French (or French-language Belgian) films don't need subtitles.
    var isFrench: Bool {
        let o = origin ?? ""
        return o.hasPrefix("France") || (o.hasPrefix("Belgium") && (orig ?? "").isEmpty)
    }

    /// Where this kind of film usually plays in Paris (same rule as the page).
    var venueType: String {
        if category == .R { return "Repertory" }
        switch releaseSize {
        case .W, .M: return "Multiplex"
        default: return category == .E ? "Multiplex" : "Art-house"
        }
    }

    var searchText: String {
        [title, orig, dir, cast, genre, origin].compactMap { $0 }.joined(separator: " ").folded
    }

    var trailerURL: URL? {
        let suffix: String
        if category == .E || isFrench { suffix = " bande annonce" } else { suffix = " bande annonce VOST" }
        return URL.with("https://www.youtube.com/results", ["search_query": title + suffix])
    }

    var allocineURL: URL? {
        if let ac { return URL(string: "https://www.allocine.fr/film/fichefilm_gen_cfilm=\(ac).html") }
        return URL.with("https://www.allocine.fr/rechercher/", ["q": title])
    }

    var showtimesSearchURL: URL? { URL.with("https://www.google.com/search", ["q": title + " séances Paris"]) }
}

// MARK: - Showtimes, cinemas, user data

struct ShowCinema: Codable, Hashable {
    var name: String?
    var address: String?
    var times: [String: [String]]?
    /// Version of each session when the source says it: [day: ["20:30": "VOST"]].
    var ver: [String: [String: String]]?
}

/// One session: its time and, when known, its version ("VF", "VOST" or "VO").
struct Session: Hashable, Identifiable {
    let time: String
    let version: String?
    var id: String { time }
    var isOriginal: Bool { version == "VOST" || version == "VO" }
}

/// Which version you like to see (asked at the first launch, changed in My profile).
enum VersionPrefs {
    /// "vo" (original, subtitled), "vf" (dubbed in French) or "any".
    static var pref: String { UserDefaults.standard.string(forKey: "versionPref") ?? "any" }
    /// true: only your version for foreign films; false: yours first, the other one too.
    static var must: Bool { UserDefaults.standard.bool(forKey: "versionMust") }

    static func label(_ v: String?) -> String? {
        switch v {
        case "VOST": return "VOST"
        case "VO": return "VO"
        case "VF": return "VF"
        default: return nil
        }
    }
}

struct Showtimes: Codable, Hashable {
    var week: String?
    var updatedAt: String?
    var cinemas: [ShowCinema]?
    var note: String?
}

struct Showing: Hashable, Identifiable {
    var day: String
    var time: String
    var cinema: String
    var address: String
    var id: String { day + time + cinema }
}

struct Cinema: Codable, Hashable, Identifiable {
    var name: String
    var type: String
    var address: String
    var lat: Double
    var lng: Double

    var id: String { name }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    /// The company running the cinema (Gaumont cinemas are Pathé's), or Independent.
    var company: String {
        let n = name.folded
        if n.hasPrefix("ugc") { return "UGC" }
        if n.hasPrefix("pathe") || n.hasPrefix("gaumont") { return "Pathé" }
        if n.hasPrefix("mk2") { return "mk2" }
        return "Independent"
    }
    static let companies = ["UGC", "Pathé", "mk2", "Independent"]

    var directionsURL: URL? {
        URL.with("https://maps.apple.com/", ["daddr": "\(lat),\(lng)", "q": name, "dirflg": "r"])
    }

    var typeColor: Color {
        switch type {
        case "Multiplex": return Cat.D.color
        case "Art-house": return Cat.T.color
        case "Repertory": return Cat.A.color
        case "Landmark": return Cat.B.color
        default: return Cat.O.color
        }
    }
}

struct SeenEntry: Codable, Hashable {
    var d: String          // date watched
    var r: Int             // rating 0–5
    var t: String?         // title
    var fd: String?        // release date
    var c: String?         // category code
    var dir: String?
    var o: String?
    var orig: String?
    var p: String?         // poster, for films added by hand
    var cn: String?        // cinema where you saw it (from your plan)
    var tm: String?        // session time, HH:mm (from your plan)
    var h: Bool?           // half a star more than r (3 + h = 3.5)
    var w: [String]?       // who you went with

    enum CodingKeys: String, CodingKey { case d, r, t, fd, c, dir, o, orig, p, cn, tm, h, w }

    init(d: String, r: Int, t: String?, fd: String?, c: String?, dir: String?, o: String?, orig: String?,
         p: String? = nil, cn: String? = nil, tm: String? = nil, h: Bool? = nil, w: [String]? = nil) {
        self.d = d; self.r = r; self.t = t; self.fd = fd; self.c = c; self.dir = dir; self.o = o; self.orig = orig; self.p = p
        self.cn = cn; self.tm = tm; self.h = h; self.w = w
    }

    /// Your rating out of 5, in half stars.
    var value: Double { Double(r) + (h == true && r < 5 ? 0.5 : 0) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        d = try c.decode(String.self, forKey: .d)
        var half = false
        if let n = try? c.decode(Int.self, forKey: .r) { r = n }
        else if let x = try? c.decode(Double.self, forKey: .r) { r = Int(x); half = x - Double(Int(x)) >= 0.5 }
        else { r = 0 }
        r = max(0, min(5, r))
        h = (try? c.decodeIfPresent(Bool.self, forKey: .h)) ?? (half ? true : nil)
        w = try? c.decodeIfPresent([String].self, forKey: .w)
        t = try? c.decodeIfPresent(String.self, forKey: .t)
        fd = try? c.decodeIfPresent(String.self, forKey: .fd)
        self.c = try? c.decodeIfPresent(String.self, forKey: .c)
        dir = try? c.decodeIfPresent(String.self, forKey: .dir)
        o = try? c.decodeIfPresent(String.self, forKey: .o)
        orig = try? c.decodeIfPresent(String.self, forKey: .orig)
        p = try? c.decodeIfPresent(String.self, forKey: .p)
        cn = try? c.decodeIfPresent(String.self, forKey: .cn)
        tm = try? c.decodeIfPresent(String.self, forKey: .tm)
    }
}

struct Plan: Codable, Hashable {
    var d: String          // planned day yyyy-MM-dd
    var t: String          // HH:mm
    var cn: String         // cinema name
    var ca: String?        // cinema address
    var title: String?
    var fd: String?        // release date
    var ok: Bool? = nil    // confirmed by you (provisional plans get no notification)
    var w: [String]? = nil // who's coming
}

/// Decodes what it can and skips a malformed entry instead of failing the whole file.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct UserData: Codable {
    var favs: [String]?
    var seen: [String: SeenEntry]?
    var plans: [String: Plan]?
    var myCinemas: [String]?
    var extraCinemas: [Cinema]?

    enum CodingKeys: String, CodingKey { case favs, seen, plans, myCinemas, extraCinemas }

    init(favs: [String]?, seen: [String: SeenEntry]?, plans: [String: Plan]?, myCinemas: [String]? = nil, extraCinemas: [Cinema]? = nil) {
        self.favs = favs; self.seen = seen; self.plans = plans
        self.myCinemas = myCinemas; self.extraCinemas = extraCinemas
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favs = (try? c.decodeIfPresent([Lossy<String>].self, forKey: .favs))?.compactMap { $0.value }
        seen = (try? c.decodeIfPresent([String: Lossy<SeenEntry>].self, forKey: .seen))?.compactMapValues { $0.value }
        plans = (try? c.decodeIfPresent([String: Lossy<Plan>].self, forKey: .plans))?.compactMapValues { $0.value }
        myCinemas = (try? c.decodeIfPresent([Lossy<String>].self, forKey: .myCinemas))?.compactMap { $0.value }
        extraCinemas = (try? c.decodeIfPresent([Lossy<Cinema>].self, forKey: .extraCinemas))?.compactMap { $0.value }
    }
}

/// One week of France admissions (CBO Box-Office, via AlloCiné): ["week start", that week, total so far].
struct BOWeek: Decodable, Hashable {
    let start: String
    let entries: Int
    let total: Int

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        start = try c.decode(String.self)
        entries = try c.decode(Int.self)
        total = try c.decode(Int.self)
    }
}

struct ExportFile: Decodable {
    var format: String?
    var exportedAt: String?
    var films: [Film]
    var showtimes: [String: Showtimes]?
    var cinemas: [Cinema]?
    var user: UserData?
    var boxoffice: [String: [BOWeek]]?

    enum CodingKeys: String, CodingKey { case format, exportedAt, films, showtimes, cinemas, user, boxoffice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try? c.decodeIfPresent(String.self, forKey: .format)
        exportedAt = try? c.decodeIfPresent(String.self, forKey: .exportedAt)
        films = try c.decode([Lossy<Film>].self, forKey: .films).compactMap { $0.value }
        showtimes = (try? c.decodeIfPresent([String: Lossy<Showtimes>].self, forKey: .showtimes))?.compactMapValues { $0.value }
        cinemas = (try? c.decodeIfPresent([Lossy<Cinema>].self, forKey: .cinemas))?.compactMap { $0.value }
        user = try? c.decodeIfPresent(UserData.self, forKey: .user)
        boxoffice = try? c.decodeIfPresent([String: [BOWeek]].self, forKey: .boxoffice)
    }
}

// MARK: - Helpers

func slug(_ s: String) -> String {
    let base = s.lowercased().decomposedStringWithCanonicalMapping
        .unicodeScalars.filter { !(0x0300...0x036F).contains($0.value) }
    var out = ""
    var dash = false
    for u in base {
        if (97...122).contains(u.value) || (48...57).contains(u.value) {
            out.append(Character(u)); dash = false
        } else if !dash {
            out.append("-"); dash = true
        }
    }
    return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

extension String {
    var folded: String { folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension URL {
    static func with(_ base: String, _ items: [String: String]) -> URL? {
        guard var c = URLComponents(string: base) else { return nil }
        c.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Dates are handled as "yyyy-MM-dd" strings in Paris time, like the page.
enum D {
    static let paris = TimeZone(identifier: "Europe/Paris") ?? .current

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = paris
        return c
    }()

    /// "fr" when the app runs in French, otherwise "en".
    static let lang: String = (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("fr") ? "fr" : "en"
    static var isFrench: Bool { lang == "fr" }

    private static func formatter(_ pattern: String, locale: String = D.lang == "fr" ? "fr_FR" : "en_GB") -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = paris
        f.locale = Locale(identifier: locale)
        f.dateFormat = pattern
        return f
    }

    private static let isoF = formatter("yyyy-MM-dd", locale: "en_US_POSIX")
    private static let stampF = formatter("yyyy-MM-dd HH:mm", locale: "en_US_POSIX")
    private static let gcalF = formatter("yyyyMMdd'T'HHmmss", locale: "en_US_POSIX")
    private static var cache: [String: DateFormatter] = [:]

    static func date(_ s: String) -> Date? { isoF.date(from: s) }
    static func str(_ d: Date) -> String { isoF.string(from: d) }
    static var today: String { str(Date()) }

    static func isDay(_ s: String?) -> Bool {
        guard let s, s.count == 10 else { return false }
        return date(s) != nil
    }

    static func addDays(_ s: String, _ n: Int) -> String {
        guard let d = date(s), let r = cal.date(byAdding: .day, value: n, to: d) else { return s }
        return str(r)
    }

    /// The Wednesday that starts the French cinema week containing this day.
    static func weekOf(_ s: String) -> String {
        guard let d = date(s) else { return s }
        let wd = cal.component(.weekday, from: d)          // 1 = Sunday … 7 = Saturday
        return addDays(s, -((wd + 3) % 7))
    }

    /// The first Saturday on or after this day.
    static func saturdayAfter(_ s: String) -> String {
        guard let d = date(s) else { return s }
        let wd = cal.component(.weekday, from: d)
        return addDays(s, (7 - wd) % 7)
    }

    static func fmt(_ s: String, _ pattern: String) -> String {
        guard let d = date(s) else { return s }
        let f: DateFormatter
        if let x = cache[pattern] { f = x } else { f = formatter(pattern); cache[pattern] = f }
        return f.string(from: d)
    }

    /// Day name with a capital ("Samedi 28 novembre"), as at the top of a list.
    static func fmtCap(_ s: String, _ pattern: String) -> String {
        let t = fmt(s, pattern)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Short month name without the trailing dot French adds ("nov", "Nov").
    static func monthShort(_ s: String) -> String {
        fmt(s, "LLL").replacingOccurrences(of: ".", with: "")
    }

    /// Weekday number, 1 = Sunday … 7 = Saturday.
    static func weekday(_ s: String) -> Int {
        guard let d = date(s) else { return 1 }
        return cal.component(.weekday, from: d)
    }

    /// The name of a weekday number (1 = Sunday), in the app's language.
    static func weekdayName(_ n: Int) -> String {
        let f = formatter("EEEE")
        let names = f.weekdaySymbols ?? []
        guard names.indices.contains(n - 1) else { return "" }
        return names[n - 1]
    }

    /// Days between two "yyyy-MM-dd" strings (b − a).
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let x = date(a), let y = date(b) else { return nil }
        return cal.dateComponents([.day], from: x, to: y).day
    }

    static func stamp(day: String, time: String) -> Date? { stampF.date(from: day + " " + time) }
    static func stampString(_ d: Date) -> (day: String, time: String) {
        let s = stampF.string(from: d)
        return (String(s.prefix(10)), String(s.suffix(5)))
    }
    static func gcal(_ d: Date) -> String { gcalF.string(from: d) }

    static func weekRange(_ w: String) -> String {
        let end = addDays(w, 6)
        return fmt(w, "EEE d MMM") + " – " + fmt(end, "EEE d MMM")
    }

    static func when(_ isoStamp: String?) -> String? {
        guard let s = isoStamp else { return nil }
        let p = ISO8601DateFormatter()
        p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let parsed = p.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return nil }
        return formatter("d MMM, HH:mm").string(from: parsed)
    }
}
