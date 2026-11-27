import Foundation
import SwiftUI
import UIKit

// MARK: - Periods and figures

/// A month, a year or all time.
enum StatsPeriod: Hashable, Identifiable {
    case month(Int, Int)    // year, month 1–12
    case year(Int)
    case all

    var id: String {
        switch self {
        case let .month(y, m): return String(format: "%04d-%02d", y, m)
        case let .year(y): return String(y)
        case .all: return "all"
        }
    }

    static var thisMonth: StatsPeriod {
        let c = D.cal.dateComponents([.year, .month], from: Date())
        return .month(c.year ?? 2026, c.month ?? 1)
    }

    /// "yyyy-MM-dd" days of this period start with this.
    var prefix: String {
        switch self {
        case let .month(y, m): return String(format: "%04d-%02d", y, m)
        case let .year(y): return String(y)
        case .all: return ""
        }
    }

    func contains(_ day: String) -> Bool { day.hasPrefix(prefix) }

    /// "November 2026", "2026", "All time".
    var title: String {
        switch self {
        case let .month(y, m): return D.fmtCap(String(format: "%04d-%02d-01", y, m), "LLLL yyyy")
        case let .year(y): return String(y)
        case .all: return String(localized: "All time")
        }
    }

    /// "November", "2026", "all time" — for sentences.
    var name: String {
        switch self {
        case let .month(y, m): return D.fmtCap(String(format: "%04d-%02d-01", y, m), "LLLL")
        case let .year(y): return String(y)
        case .all: return String(localized: "all time")
        }
    }
}

/// One film you watched, with what the app knows about it.
struct WatchedFilm: Identifiable {
    let id: String
    let entry: SeenEntry
    let film: Film?

    var title: String { entry.t ?? film?.title ?? String(localized: "Film") }
    var poster: String? { film?.poster ?? entry.p }
    var duration: Int? { film?.duration }
    var category: Cat { film?.category ?? Cat.from(entry.c) }
    var release: String? { film?.date ?? entry.fd }
    var director: String? { (film?.dir ?? entry.dir)?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
    /// Days between release and the day you saw it (0: opening day).
    var daysAfterRelease: Int? { release.flatMap { D.daysBetween($0, entry.d) } }
}

/// How early you saw a film compared with everyone in France (CBO admissions, week by week).
struct EarlyBird {
    let title: String
    let poster: String?
    let week: Int          // 0: its first week
    let weekEntries: Int   // admissions in France the week you went
    let percent: Int       // you were among the first …% of its viewers so far
    let total: Int         // its admissions in France so far
    let weeks: Int         // weeks of figures

    /// "26%", and "74%" for those who saw it after you (kept out of the translated text).
    var pct: String { "\(percent)%" }
    var afterPct: String { "\(100 - percent)%" }

    var text: String {
        let people = weekEntries.formatted(), all = total.formatted()
        return week == 0
            ? String(localized: "You saw \(title) in its first week, one of \(people) people in France. That's the first \(pct) of its \(all) viewers so far 🐦")
            : String(localized: "You saw \(title) before \(afterPct) of the \(all) people in France who've seen it so far 🐦")
    }
}

struct StatsSummary {
    let period: StatsPeriod
    var films: [WatchedFilm] = []
    var minutes = 0
    var averageRating: Double?
    var topRated: WatchedFilm?
    var cinemas: [(name: String, count: Int)] = []
    var categories: [(cat: Cat, count: Int)] = []
    var weekdays: [(day: Int, count: Int)] = []
    var months: [(month: Int, count: Int)] = []
    var planned = 0
    var facts: [String] = []
    var early: EarlyBird?
    var buddies: [(name: String, count: Int)] = []

    var count: Int { films.count }
    var hours: Int { Int((Double(minutes) / 60).rounded()) }
}

extension Store {
    func stats(_ period: StatsPeriod) -> StatsSummary {
        var s = StatsSummary(period: period)
        s.films = seen.filter { period.contains($0.value.d) }
            .map { WatchedFilm(id: $0.key, entry: $0.value, film: index[$0.key]) }
            .sorted { $0.entry.d < $1.entry.d }
        s.planned = plans.filter { period.contains($0.value.d) && seen[$0.key] == nil }.count
        s.minutes = s.films.compactMap { $0.duration }.reduce(0, +)
        let rated = s.films.filter { $0.entry.value > 0 }
        if !rated.isEmpty {
            s.averageRating = rated.map { $0.entry.value }.reduce(0, +) / Double(rated.count)
            s.topRated = rated.max { a, b in
                a.entry.value != b.entry.value ? a.entry.value < b.entry.value : (a.film?.average ?? 0) < (b.film?.average ?? 0)
            }
        }
        func ranked<K: Hashable>(_ keys: [K]) -> [(K, Int)] {
            Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        }
        s.cinemas = ranked(s.films.compactMap { $0.entry.cn?.nilIfEmpty }).map { (name: $0.0, count: $0.1) }
        s.categories = ranked(s.films.map { $0.category }).map { (cat: $0.0, count: $0.1) }
        s.weekdays = ranked(s.films.map { D.weekday($0.entry.d) }).map { (day: $0.0, count: $0.1) }
        let monthCounts = Dictionary(s.films.compactMap { Int($0.entry.d.dropFirst(5).prefix(2)) }.map { ($0, 1) }, uniquingKeysWith: +)
        s.months = (1...12).map { (month: $0, count: monthCounts[$0] ?? 0) }
        s.buddies = ranked(s.films.flatMap { $0.entry.w ?? [] }).map { (name: $0.0, count: $0.1) }
        s.early = earlyBird(s)
        s.facts = funFacts(s)
        if let e = s.early { s.facts.insert(e.text, at: 0) }
        return s
    }

    /// The film you saw earliest in its run, measured against France's weekly admissions.
    private func earlyBird(_ s: StatsSummary) -> EarlyBird? {
        var best: EarlyBird?
        var bestShare = 2.0
        for w in s.films {
            guard let weeks = boxOffice[w.id], let last = weeks.last, last.total >= 1000 else { continue }
            guard let i = weeks.firstIndex(where: { w.entry.d >= $0.start && w.entry.d <= D.addDays($0.start, 6) }) else { continue }
            let share = Double(weeks[i].total) / Double(last.total)
            if share < bestShare {
                bestShare = share
                best = EarlyBird(title: w.title, poster: w.poster, week: i, weekEntries: weeks[i].entries,
                                 percent: max(1, Int((share * 100).rounded(.up))), total: last.total, weeks: weeks.count)
            }
        }
        return bestShare <= 0.6 ? best : nil
    }

    /// Fun facts from your own outings and AlloCiné's ratings.
    private func funFacts(_ s: StatsSummary) -> [String] {
        var out: [String] = []
        if let first = s.films.first(where: { $0.daysAfterRelease == 0 && $0.film != nil }) {
            out.append(String(localized: "First day out for \(first.title): you saw it on opening day! 🎟️ Most people wait weeks, nicely done 😉"))
        }
        let early = s.films.filter { ($0.daysAfterRelease ?? 99) >= 0 && ($0.daysAfterRelease ?? 99) <= 6 }
        if early.count >= 2 {
            out.append(String(localized: "\(early.count) films seen in their first week in cinemas. You don't hang around 🏃"))
        }
        let gaps: [(WatchedFilm, Double, Double)] = s.films.compactMap { w in
            guard w.entry.value > 0, let p = w.film?.press else { return nil }
            return (w, w.entry.value, p)
        }
        if let rebel = gaps.max(by: { abs($0.1 - $0.2) < abs($1.1 - $1.2) }), abs(rebel.1 - rebel.2) >= 1.5 {
            let critics = String(format: "%.1f", rebel.2)
            out.append(String(localized: "You gave \(rebel.0.title) \(Int(rebel.1))★ when critics gave it \(critics). You know what you like 😎"))
        } else if let twin = gaps.min(by: { abs($0.1 - $0.2) < abs($1.1 - $1.2) }), abs(twin.1 - twin.2) <= 0.3 {
            out.append(String(localized: "You and the critics agreed on \(twin.0.title) 🤝"))
        }
        if let longest = s.films.filter({ $0.duration != nil }).max(by: { ($0.duration ?? 0) < ($1.duration ?? 0) }),
           let d = longest.duration, d >= 140 {
            out.append(String(localized: "Longest sit: \(longest.title), \(d / 60)h\(String(format: "%02d", d % 60)). Popcorn refill needed 🍿"))
        }
        let byDay = Dictionary(grouping: s.films, by: { $0.entry.d })
        if let double = byDay.filter({ $0.value.count >= 2 }).max(by: { $0.value.count < $1.value.count }) {
            out.append(String(localized: "Double feature on \(D.fmt(double.key, "EEEE d MMMM")): \(double.value.count) films in one day 🎬"))
        }
        if let wd = s.weekdays.first, s.count >= 3 {
            out.append(String(localized: "\(D.fmtCap(D.addDays("2026-11-29", wd.day - 1), "EEEE")) is your cinema day 📅"))
        }
        let directors = Dictionary(s.films.compactMap { $0.director }.map { ($0, 1) }, uniquingKeysWith: +)
        if let fan = directors.max(by: { $0.value < $1.value }), fan.value >= 2 {
            out.append(String(localized: "Big fan of \(fan.key): \(fan.value) of their films 🎥"))
        }
        if let b = s.buddies.first, b.count >= 2 {
            out.append(String(localized: "Best cinema buddy: \(b.name), \(b.count) films together 🍿"))
        }
        if s.cinemas.count >= 3 {
            out.append(String(localized: "\(s.cinemas.count) different cinemas. A true Paris explorer 🗺️"))
        }
        if s.hours >= 10 {
            out.append(String(localized: "\(s.hours) hours in front of the big screen 🍿"))
        }
        return out
    }

    /// Periods for the list: this year's months back to January, this year, then each past year
    /// (a finished year shows its year stats only).
    var statsPeriods: (thisYear: [StatsPeriod], pastYears: [StatsPeriod]) {
        let c = D.cal.dateComponents([.year, .month], from: Date())
        let y = c.year ?? 2026, m = c.month ?? 1
        let months = (1...m).reversed().map { StatsPeriod.month(y, $0) }
        let years = Set(seen.values.compactMap { Int($0.d.prefix(4)) }).filter { $0 < y }.sorted(by: >)
        return (months + [StatsPeriod.year(y)], years.map { StatsPeriod.year($0) } + [StatsPeriod.all])
    }
}

// MARK: - Story (Instagram story format, 9:16)

enum StoryPage: Hashable {
    case intro, numbers, topFilm, earlyBird, buddy, cinemas, genres, fact(Int), months, recap
}

/// One 9:16 card of the story. Posters are passed as images so the card can be saved as a picture.
struct StoryCard: View {
    let page: StoryPage
    let stats: StatsSummary
    let name: String
    let posters: [String: UIImage]
    let accent: Color
    let deep: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [accent, deep, .black], startPoint: .topLeading, endPoint: .bottom)
            content
                .padding(.horizontal, 26)
                .padding(.vertical, 40)
            VStack {
                Spacer()
                Text("🦥 Sloth Cinema").font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.75)
                    .padding(.bottom, 16)
            }
        }
        .foregroundStyle(.white)
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .intro:
            VStack(spacing: 18) {
                Spacer()
                Text("🦥🎭").font(.system(size: 80))
                Text(name.isEmpty ? stats.period.title : String(localized: "\(name)'s \(stats.period.name)"))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(stats.period.prefix.isEmpty ? String(localized: "at the cinema, since the start") : String(localized: "at the cinema"))
                    .font(.system(size: 22, weight: .medium, design: .serif)).opacity(0.9)
                Spacer()
                Text(stats.period.title).font(.headline).opacity(0.8)
                Spacer()
            }
        case .numbers:
            VStack(spacing: 22) {
                Spacer()
                big("\(stats.count)", stats.count == 1 ? String(localized: "film watched") : String(localized: "films watched"))
                if stats.hours > 0 { big("\(stats.hours)", String(localized: "hours in the dark")) }
                if let a = stats.averageRating { big(String(format: "%.1f★", a), String(localized: "your average rating")) }
                if stats.planned > 0 { big("+\(stats.planned)", String(localized: "planned, still to see")) }
                Spacer()
            }
        case .topFilm:
            VStack(spacing: 16) {
                Text("Your favourite").font(.system(size: 26, weight: .heavy, design: .rounded))
                if let top = stats.topRated {
                    poster(top, width: 190)
                    Text(top.title).font(.system(size: 24, weight: .bold, design: .serif)).multilineTextAlignment(.center)
                    RatingStars(value: top.entry.value, size: 30)
                } else {
                    Text("Rate the films you watch to find out 😉").multilineTextAlignment(.center)
                }
            }
        case .cinemas:
            VStack(spacing: 18) {
                Spacer()
                Text("🍿").font(.system(size: 70))
                if let top = stats.cinemas.first {
                    Text("Your cinema").font(.system(size: 22, weight: .medium, design: .serif)).opacity(0.9)
                    Text(top.name).font(.system(size: 30, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                    Text(top.count == 1 ? String(localized: "1 visit") : String(localized: "\(top.count) visits")).font(.title3)
                    if stats.cinemas.count > 1 {
                        Text(String(localized: "\(stats.cinemas.count) cinemas in all")).font(.headline).opacity(0.8)
                    }
                } else {
                    Text("Plan your films in the app and it will remember where you went.")
                        .font(.title3).multilineTextAlignment(.center)
                }
                Spacer()
            }
        case .genres:
            VStack(alignment: .leading, spacing: 14) {
                Text("What you watched").font(.system(size: 26, weight: .heavy, design: .rounded))
                let top = Array(stats.categories.prefix(5))
                let most = max(1, top.first?.count ?? 1)
                ForEach(top.indices, id: \.self) { i in
                    let item = top[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.cat.label) · \(item.count)").font(.headline)
                        GeometryReader { g in
                            Capsule().fill(.white.opacity(0.9))
                                .frame(width: max(18, g.size.width * CGFloat(item.count) / CGFloat(most)))
                        }
                        .frame(height: 12)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .earlyBird:
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text("Early bird").font(.system(size: 16, weight: .bold)).textCase(.uppercase).tracking(3)
                    .foregroundStyle(Color(hex: 0xFFD27A))
                if let e = stats.early {
                    Text(e.week == 0 ? String(localized: "You saw \(e.title) in its first week") : String(localized: "You saw \(e.title) early"))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.weekEntries.formatted()).font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: 0xFFD27A)).minimumScaleFactor(0.5)
                        Text(e.week == 0 ? String(localized: "people in France saw it that week. You were one of them.")
                                         : String(localized: "people in France saw it the week you did."))
                            .font(.system(size: 17, weight: .medium)).opacity(0.9)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "first \(e.pct)")).font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: 0xFFD27A)).minimumScaleFactor(0.5)
                        Text(String(localized: "of the \(e.total.formatted()) people who've seen it in France so far"))
                            .font(.system(size: 17, weight: .medium)).opacity(0.9)
                    }
                    Text("Admissions: CBO Box-Office, via AlloCiné").font(.caption).opacity(0.7)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .buddy:
            VStack(spacing: 18) {
                Spacer()
                Text("Best cinema buddy").font(.system(size: 18, weight: .semibold)).textCase(.uppercase).tracking(3).opacity(0.85)
                if let b = stats.buddies.first {
                    Text(b.name).font(.system(size: 54, weight: .black, design: .rounded)).minimumScaleFactor(0.5)
                    Text(b.count == 1 ? String(localized: "1 film together") : String(localized: "\(b.count) films together"))
                        .font(.system(size: 22, weight: .medium))
                    if stats.buddies.count > 1 {
                        Text(stats.buddies.dropFirst().prefix(3).map { "\($0.name) · \($0.count)" }.joined(separator: "   "))
                            .font(.subheadline).opacity(0.8)
                    }
                }
                Spacer()
            }
        case .fact(let i):
            VStack(spacing: 20) {
                Spacer()
                Text("Fun fact").font(.system(size: 18, weight: .semibold)).textCase(.uppercase).tracking(3).opacity(0.85)
                Text(stats.facts.indices.contains(i) ? stats.facts[i] : "")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Spacer()
            }
        case .months:
            VStack(alignment: .leading, spacing: 10) {
                Text("Month by month").font(.system(size: 26, weight: .heavy, design: .rounded))
                let most = max(1, stats.months.map { $0.count }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(stats.months.indices, id: \.self) { i in
                        let m = stats.months[i]
                        VStack(spacing: 4) {
                            if m.count > 0 { Text("\(m.count)").font(.system(size: 10, weight: .bold)) }
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(m.count > 0 ? 0.9 : 0.25))
                                .frame(height: max(4, 220 * CGFloat(m.count) / CGFloat(most)))
                            Text(D.fmt(String(format: "2026-%02d-01", m.month), "LLLLL")).font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 260, alignment: .bottom)
                Spacer()
            }
        case .recap:
            VStack(spacing: 14) {
                Text(name.isEmpty ? stats.period.title : String(localized: "\(name)'s \(stats.period.name)"))
                    .font(.system(size: 26, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                let shown = Array(stats.films.suffix(6).reversed())
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(shown) { w in poster(w, width: 88) }
                }
                HStack(spacing: 18) {
                    small("\(stats.count)", String(localized: "films"))
                    small("\(stats.hours)", String(localized: "hours"))
                    if let a = stats.averageRating { small(String(format: "%.1f★", a), String(localized: "average")) }
                }
                if let c = stats.cinemas.first { Text("📍 \(c.name)").font(.subheadline.weight(.semibold)) }
                Spacer()
            }
        }
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 64, weight: .black, design: .rounded)).minimumScaleFactor(0.5)
            Text(label).font(.system(size: 18, weight: .medium)).opacity(0.9)
        }
    }

    private func small(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 26, weight: .black, design: .rounded))
            Text(label).font(.caption).opacity(0.85)
        }
    }

    @ViewBuilder
    private func poster(_ w: WatchedFilm, width: CGFloat) -> some View {
        if let url = w.poster, let img = posters[url] {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: width, height: width * 1.45)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
                .shadow(radius: 8)
        } else {
            PosterTile(title: w.title, cat: w.category, width: width)
        }
    }
}

/// The story for a period: swipe through the cards, share one or all as pictures (1080 × 1920).
struct StoryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    @State var period: StatsPeriod
    @State private var page = 0
    @State private var posters: [String: UIImage] = [:]
    @State private var images: [Image] = []
    @State private var choosing = false

    private var stats: StatsSummary { store.stats(period) }

    private var pages: [StoryPage] {
        let s = stats
        var out: [StoryPage] = [.intro, .numbers]
        if s.count > 0 {
            out.append(.topFilm)
            if s.early != nil { out.append(.earlyBird) }
            if (s.buddies.first?.count ?? 0) >= 2 { out.append(.buddy) }
            out.append(.cinemas)
            if s.categories.count > 1 { out.append(.genres) }
            if case .month = period {} else if s.count > 2 { out.append(.months) }
            for i in s.facts.indices.filter({ s.facts[$0] != s.early?.text && !s.facts[$0].contains("🍿") }).prefix(3) { out.append(.fact(i)) }
            out.append(.recap)
        }
        return out
    }

    var body: some View {
        let s = stats
        NavigationStack {
            VStack(spacing: 12) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        card(pages[i], s)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(.horizontal, 22)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                if s.count == 0 {
                    Text(s.planned > 0 ? String(localized: "Nothing watched yet, \(s.planned) planned. See you at the cinema!")
                                       : String(localized: "Nothing watched in this period yet."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !images.isEmpty {
                    ShareLink(items: images, preview: { img in SharePreview(Text(period.title), image: img) }) {
                        Label("Share all as story pictures", systemImage: "square.and.arrow.up.on.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.theme, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 8)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Button { choosing = true } label: {
                        HStack(spacing: 4) {
                            Text(period.title).font(.headline)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }
                    }
                    .accessibilityLabel("Choose another month or year")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if images.indices.contains(page) {
                        ShareLink(item: images[page], preview: SharePreview(Text(period.title), image: images[page])) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share this card")
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .sheet(isPresented: $choosing) {
                PeriodListView(selected: $period).environment(store)
            }
            .task(id: period.id) { await prepare() }
        }
        .environment(\.colorScheme, .dark)
    }

    private func card(_ p: StoryPage, _ s: StatsSummary) -> StoryCard {
        StoryCard(page: p, stats: s, name: userName, posters: posters, accent: Theme.shared.color, deep: Theme.shared.deep)
    }

    /// Loads the posters, then draws each card as a 1080 × 1920 picture for sharing.
    @MainActor
    private func prepare() async {
        page = 0
        images = []
        let s = stats
        let urls = Set(s.films.compactMap { $0.poster }).subtracting(posters.keys)
        for u in urls {
            guard let url = URL(string: u) else { continue }
            if let result = try? await URLSession.shared.data(from: url), let img = UIImage(data: result.0) {
                posters[u] = img
            }
        }
        var out: [Image] = []
        for p in pages {
            let renderer = ImageRenderer(content: card(p, s).frame(width: 360, height: 640).environment(\.colorScheme, .dark))
            renderer.scale = 3
            if let ui = renderer.uiImage { out.append(Image(uiImage: ui)) }
        }
        images = out
    }
}

/// This year's months back to January and the whole year; earlier years show their year stats only.
struct PeriodListView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: StatsPeriod

    var body: some View {
        NavigationStack {
            List {
                let periods = store.statsPeriods
                Section("This year") {
                    ForEach(periods.thisYear) { p in row(p) }
                }
                Section("Earlier") {
                    ForEach(periods.pastYears) { p in row(p) }
                }
            }
            .navigationTitle("My stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ p: StatsPeriod) -> some View {
        let n = store.stats(p).count
        return Button {
            selected = p
            dismiss()
        } label: {
            HStack {
                Text(p.title).foregroundStyle(.primary)
                Spacer()
                Text(n == 1 ? String(localized: "1 film") : String(localized: "\(n) films")).foregroundStyle(.secondary)
                if p == selected { Image(systemName: "checkmark").foregroundStyle(Color.theme) }
            }
        }
    }
}

// MARK: - Stats as a list (Settings › My profile)

struct StatsList: View {
    let stats: StatsSummary

    var body: some View {
        Group {
            Section {
                LabeledContent("Films watched", value: "\(stats.count)")
                LabeledContent("Hours at the cinema", value: "\(stats.hours)")
                if let a = stats.averageRating { LabeledContent("Average rating", value: String(format: "%.1f ★", a)) }
                if stats.planned > 0 { LabeledContent("Planned, still to see", value: "\(stats.planned)") }
                if let t = stats.topRated { LabeledContent("Favourite", value: t.title) }
                if let c = stats.cinemas.first { LabeledContent("Your cinema", value: c.name) }
                if let b = stats.buddies.first { LabeledContent("Best cinema buddy", value: "\(b.name) · \(b.count)") }
                if let g = stats.categories.first { LabeledContent("Favourite genre", value: g.cat.label) }
                if let w = stats.weekdays.first, stats.count >= 3 {
                    LabeledContent("Your cinema day", value: D.fmtCap(D.addDays("2026-11-29", w.day - 1), "EEEE"))
                }
            } header: {
                Text(stats.period.title)
            }
            if !stats.facts.isEmpty {
                Section("Fun facts") {
                    ForEach(stats.facts, id: \.self) { Text($0) }
                }
            }
        }
    }
}
