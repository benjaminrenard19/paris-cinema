import SwiftUI

/// How the Films page orders a week (chosen at the first launch, changed with the ⇅ button).
enum WeekSort: String, CaseIterable, Identifiable {
    case standard = "Biggest releases first"
    case az = "Name A–Z"
    case za = "Name Z–A"
    case press = "Critics rating"
    case spect = "Audience rating"
    case avg = "Average of both ratings"
    case short = "Running time, shortest first"
    case long = "Running time, longest first"
    var id: String { rawValue }
    var label: String { NSLocalizedString(rawValue, comment: "Sort order") }

    static var current: WeekSort { WeekSort(rawValue: UserDefaults.standard.string(forKey: "weekSort") ?? "") ?? .standard }

    /// Films without the value being sorted on go last.
    func apply(_ list: [Film]) -> [Film] {
        func highFirst(_ key: (Film) -> Double?) -> [Film] {
            list.sorted { a, b in
                switch (key(a), key(b)) {
                case let (x?, y?): return x > y
                case (.some, .none): return true
                default: return false
                }
            }
        }
        func lowFirst(_ key: (Film) -> Double?) -> [Film] {
            list.sorted { a, b in
                switch (key(a), key(b)) {
                case let (x?, y?): return x < y
                case (.some, .none): return true
                default: return false
                }
            }
        }
        switch self {
        case .standard: return list
        case .az: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .za: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .press: return highFirst { $0.press }
        case .spect: return highFirst { $0.spect }
        case .avg: return highFirst { $0.average }
        case .short: return lowFirst { $0.duration.map { Double($0) } }
        case .long: return highFirst { $0.duration.map { Double($0) } }
        }
    }
}

/// Which films the Films page shows (chosen at the first launch, changed with its button or in My profile).
enum FilmsShow: String, CaseIterable, Identifiable {
    case new, recent, classics, all
    var id: String { rawValue }

    static var current: FilmsShow { FilmsShow(rawValue: UserDefaults.standard.string(forKey: "filmsShow") ?? "") ?? .recent }

    var label: String {
        switch self {
        case .new: return String(localized: "New this week")
        case .recent: return String(localized: "New releases in cinemas")
        case .classics: return String(localized: "Classics & old blockbusters")
        case .all: return String(localized: "Everything")
        }
    }
    var short: String {
        switch self {
        case .new: return String(localized: "New this week")
        case .recent: return String(localized: "New releases")
        case .classics: return String(localized: "Classics")
        case .all: return String(localized: "Everything")
        }
    }
    var hint: String {
        switch self {
        case .new: return String(localized: "Out since Wednesday")
        case .recent: return String(localized: "Recent films still showing")
        case .classics: return String(localized: "Older films back on screen")
        case .all: return String(localized: "New and old, all showing this week")
        }
    }

    @MainActor
    func includes(_ f: Film, store: Store) -> Bool {
        switch self {
        case .new: return !f.isRepertory && f.date >= store.currentWeek && f.date <= D.addDays(store.currentWeek, 6)
        case .recent: return !f.isRepertory
        case .classics: return f.isRepertory
        case .all: return true
        }
    }
}

struct WeeksView: View {
    @Environment(Store.self) private var store
    @State private var week = ""
    @State private var cats: Set<Cat> = []
    @State private var genres: Set<String> = []
    @State private var path: [String] = []
    @State private var cinemasFor: Film?
    @AppStorage("filmsShow") private var showRaw = FilmsShow.recent.rawValue
    @Environment(\.openURL) private var openURL
    @State private var favOnly = false
    @State private var query = ""
    @State private var showData = false
    @State private var showStats = false
    @State private var showInbox = false
    @AppStorage("weekSort") private var sortRaw = WeekSort.standard.rawValue
    @AppStorage("userName") private var userName = ""
    @AppStorage("filmsMode") private var modeRaw = "now"
    @AppStorage("hideSeen") private var hideSeen = true
    @State private var didScroll = false
    @State private var showSeenResults = false
    @State private var slideshow: EditTarget?

    /// "now": every film with sessions this week; "week": releases of one week.
    private var nowMode: Bool { modeRaw != "week" }
    private var show: FilmsShow { FilmsShow(rawValue: showRaw) ?? .recent }
    private var source: [Film] {
        if !nowMode { return store.films(in: week) }
        return store.nowShowing.filter { show.includes($0, store: store) }.sorted { a, b in
            let ra = a.category == .R ? 1 : 0, rb = b.category == .R ? 1 : 0
            if ra != rb { return ra < rb }
            if a.releaseSize.rank != b.releaseSize.rank { return a.releaseSize.rank < b.releaseSize.rank }
            return a.date > b.date
        }
    }
    private var nowEnd: String { max(D.addDays(store.currentWeek, 6), D.addDays(D.today, 6)) }

    private var sort: WeekSort { WeekSort(rawValue: sortRaw) ?? .standard }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List {
                if query.isEmpty {
                    // Above the fold: scroll up to see the stage and the week.
                    Section {
                        StageHeader(name: userName)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        Picker("Show", selection: $modeRaw) {
                            Text("Showing this week").tag("now")
                            Text("Releases by week").tag("week")
                        }
                        .pickerStyle(.segmented)
                        if nowMode { nowHeader } else {
                            weekHeader
                            if !store.releases(in: week).isEmpty {
                                Button { slideshow = EditTarget(id: week) } label: {
                                    Label("Swipe through this week's posters", systemImage: "play.rectangle.on.rectangle")
                                }
                            }
                        }
                    }
                    Section {
                        filterBar
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .id("filters")
                    }
                    Section {
                        if visible.isEmpty {
                            Text(source.isEmpty ? (nowMode ? "No session times loaded yet. Pull down to refresh." : "No films loaded for this week yet.") : "No films match these filters.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(visible) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f, showDate: nowMode) }
                                .swipeActions(edge: .trailing) { favButton(f) }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button { cinemasFor = f } label: { Label("Cinemas", systemImage: "mappin.and.ellipse") }
                                        .tint(Color.theme)
                                    if let u = f.trailerURL {
                                        Button { openURL(u) } label: { Label("Trailer", systemImage: "play.rectangle.fill") }
                                            .tint(.indigo)
                                    }
                                    Button { path.append(f.id) } label: { Label("Info", systemImage: "info.circle") }
                                        .tint(.gray)
                                }
                        }
                    } header: {
                        Text((visible.count == 1 ? String(localized: "1 film") : String(localized: "\(visible.count) films")) + (sort == .standard ? "" : " · " + sort.label))
                    } footer: {
                        if nowMode && hideSeen {
                            Text("Films you've seen are hidden. Change this in My profile.")
                        }
                    }
                } else {
                    let all = store.search(query)
                    let hidden = hideSeen && !showSeenResults ? all.filter { store.seen[$0.id] != nil } : []
                    let results = hidden.isEmpty ? all : all.filter { store.seen[$0.id] == nil }
                    Section(results.count == 1 ? String(localized: "1 result") : String(localized: "\(results.count) results")) {
                        ForEach(results.prefix(150)) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f, showDate: true) }
                        }
                        if !hidden.isEmpty {
                            Button(hidden.count == 1 ? String(localized: "Show 1 film you've seen") : String(localized: "Show \(hidden.count) films you've seen")) {
                                showSeenResults = true
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .task {
                // Open on the filters, with the stage and week just above.
                guard !didScroll else { return }
                didScroll = true
                try? await Task.sleep(for: .milliseconds(120))
                proxy.scrollTo("filters", anchor: .top)
            }
            .onChange(of: query) { _, q in if q.isEmpty { showSeenResults = false } }
            }
            .refreshable { await store.refreshFromFeed(force: true) }
            .navigationTitle("Sloth Cinema")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Title, director, actor")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort films", selection: $sortRaw) {
                            ForEach(WeekSort.allCases) { s in Text(s.label).tag(s.rawValue) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Sort")
                }
                ToolbarItem(placement: .principal) {
                    Button { showStats = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chart.bar.fill").font(.caption)
                            Text(String(localized: "My \(D.monthShort(D.today)) Stats"))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.theme.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.theme)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Your month at the cinema, as a story to share")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    InboxButton(count: store.inboxBadge) { showInbox = true }
                    Button { showData = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showData) { DataView().environment(store) }
            .sheet(item: $cinemasFor) { f in FilmCinemasSheet(film: f).environment(store) }
            .sheet(isPresented: $showInbox) { InboxView().environment(store) }
            .fullScreenCover(isPresented: $showStats) { StoryView(period: .thisMonth).environment(store) }
            .fullScreenCover(item: $slideshow) { t in ReleasesSlideshowView(week: t.id).environment(store) }
            .onAppear { if week.isEmpty || store.byWeek[week] == nil { week = store.defaultWeek } }
            .onChange(of: store.weeks) { _, _ in if store.byWeek[week] == nil { week = store.defaultWeek } }
        }
    }

    private var visible: [Film] {
        sort.apply(source.filter { f in
            (cats.isEmpty || cats.contains(f.category)) && (!favOnly || store.isFav(f.id))
                && (genres.isEmpty || !genres.isDisjoint(with: f.genres))
        })
    }

    /// Genres of the films on the page, most common first.
    private var genreChoices: [(String, Int)] {
        var count: [String: Int] = [:]
        for f in source { for g in f.genres { count[g, default: 0] += 1 } }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private var nowHeader: some View {
        VStack(spacing: 2) {
            Text("This week").font(.title2.weight(.bold))
            Text(String(localized: "Every film with sessions, today to \(D.fmt(nowEnd, "EEEE d MMMM"))"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var position: Int? { store.weeks.firstIndex(of: week) }

    private var weekHeader: some View {
        HStack(spacing: 8) {
            Button { step(-1) } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                .disabled((position ?? 0) <= 0)
                .accessibilityLabel("Previous week")
            Menu {
                if store.byWeek[store.currentWeek] != nil {
                    Button("This week") { week = store.currentWeek }
                }
                ForEach(months, id: \.0) { item in
                    Menu(item.0) {
                        ForEach(item.1, id: \.self) { w in
                            Button(String(localized: "\(D.fmt(w, "d MMM")) · \(store.films(in: w).count) films")) { week = w }
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text(week == store.currentWeek ? String(localized: "This week") : String(localized: "Week of \(D.fmt(week, "d MMMM yyyy"))"))
                        .font(.title2.weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(D.weekRange(week)).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            Button { step(1) } label: { Image(systemName: "chevron.right").font(.title3.weight(.semibold)) }
                .disabled(position == nil || position! >= store.weeks.count - 1)
                .accessibilityLabel("Next week")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private var months: [(String, [String])] {
        var out: [(String, [String])] = []
        for w in store.weeks {
            let m = D.fmt(w, "MMMM yyyy")
            if out.last?.0 == m { out[out.count - 1].1.append(w) } else { out.append((m, [w])) }
        }
        return out
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if nowMode {
                    Menu {
                        Picker("Show", selection: $showRaw) {
                            ForEach(FilmsShow.allCases) { m in
                                Text("\(m.label) (\(store.nowShowing.filter { m.includes($0, store: store) }.count))\n\(m.hint)").tag(m.rawValue)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(show.short).font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.theme, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .accessibilityLabel(String(localized: "Films to show: \(show.label)"))
                }
                let choices = genreChoices
                if choices.count > 1 {
                    Menu {
                        ForEach(choices, id: \.0) { item in
                            Button {
                                if genres.contains(item.0) { genres.remove(item.0) } else { genres.insert(item.0) }
                            } label: {
                                if genres.contains(item.0) {
                                    Label("\(Film.genreLabel(item.0)) \(item.1)", systemImage: "checkmark")
                                } else {
                                    Text("\(Film.genreLabel(item.0)) \(item.1)")
                                }
                            }
                        }
                        if !genres.isEmpty {
                            Divider()
                            Button("All genres") { genres = [] }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "theatermasks").font(.caption)
                            Text(genres.isEmpty ? String(localized: "Genres") : genres.map { Film.genreLabel($0) }.sorted().joined(separator: ", "))
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(genres.isEmpty ? Color.secondary.opacity(0.12) : Color.primary, in: Capsule())
                        .foregroundStyle(genres.isEmpty ? Color.primary : Color(.systemBackground))
                    }
                }
                chip("Favourites", symbol: "star.fill", on: favOnly, color: Color(hex: 0xE0A800)) { favOnly.toggle() }
                ForEach(Cat.allCases) { c in
                    let n = source.filter { $0.category == c }.count
                    if n > 0 {
                        chip("\(c.short) \(n)", symbol: nil, on: cats.contains(c), color: c.color) {
                            if cats.contains(c) { cats.remove(c) } else { cats.insert(c) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ text: String, symbol: String?, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                Text(text).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? color : color.opacity(0.12), in: Capsule())
            .foregroundStyle(on ? Color.white : color)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func favButton(_ f: Film) -> some View {
        Button { store.toggleFav(f) } label: {
            Label(store.isFav(f.id) ? "Unfavourite" : "Favourite", systemImage: store.isFav(f.id) ? "star.slash" : "star")
        }
        .tint(Color(hex: 0xE0A800))
    }

    private func step(_ d: Int) {
        guard let i = position else { week = store.defaultWeek; return }
        let j = i + d
        if store.weeks.indices.contains(j) { week = store.weeks[j] }
    }
}
