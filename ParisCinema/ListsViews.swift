import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - My list (favourites and watch plans)

struct MyListView: View {
    @Environment(Store.self) private var store
    @State private var expanded: Set<Int> = [Calendar.current.component(.year, from: Date())]
    @State private var showAll: Set<Int> = []
    private static let preview = 6

    var body: some View {
        NavigationStack {
            List {
                let groups = yearGroups
                if groups.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "star",
                                           description: Text("Tap the star on a film. Films you haven't seen get a provisional day to watch them, which you can send to your calendar."))
                }
                ForEach(groups, id: \.year) { g in
                    let c = store.yearCounts(g.year)
                    let open = expanded.contains(g.year)
                    let limit = showAll.contains(g.year) ? Int.max : Self.preview
                    let planned = Array(g.planned.prefix(open ? limit : 0))
                    let unplanned = Array(g.unplanned.prefix(open ? max(0, limit - planned.count) : 0))
                    let watched = Array(g.watched.prefix(open ? max(0, limit - planned.count - unplanned.count) : 0))
                    let total = g.planned.count + g.unplanned.count + g.watched.count
                    Section {
                        ForEach(planned, id: \.0.id) { item in
                            NavigationLink(value: item.0.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    FilmRow(film: item.0, showDate: true)
                                    Label("\(D.fmt(item.1.d, "EEE d MMM")) · \(item.1.t) · \(item.1.cn)", systemImage: "calendar")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(item.1.d < D.today ? Color.red : Color.theme)
                                }
                            }
                            .swipeActions { unfav(item.0) }
                        }
                        ForEach(unplanned) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f, showDate: true) }
                                .swipeActions { unfav(f) }
                        }
                        ForEach(watched) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f, showDate: true) }
                                .swipeActions { unfav(f) }
                        }
                        if open && total > Self.preview {
                            Button(showAll.contains(g.year) ? String(localized: "Show fewer") : String(localized: "Show all \(total) films")) {
                                withAnimation {
                                    if showAll.contains(g.year) { showAll.remove(g.year) } else { showAll.insert(g.year) }
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    } header: {
                        Button {
                            withAnimation {
                                if open { expanded.remove(g.year) } else { expanded.insert(g.year) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.bold))
                                    .rotationEffect(.degrees(open ? 90 : 0))
                                Text(String(g.year)).font(.title3.weight(.bold))
                                Spacer()
                                Text("\(c.watched) (\(c.total))").font(.headline.monospacedDigit())
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .textCase(nil)
                        .accessibilityHint(open ? String(localized: "Hides this year") : String(localized: "Shows this year"))
                    } footer: {
                        Text(String(localized: "\(c.watched) watched in \(String(g.year)), \(c.total - c.watched) more planned.") + " "
                             + (total == 1 ? String(localized: "1 favourite.") : String(localized: "\(total) favourites.")))
                    }
                }
            }
            .navigationTitle("My list")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
        }
    }

    private struct YearGroup {
        let year: Int
        var planned: [(Film, Plan)] = []
        var unplanned: [Film] = []
        var watched: [Film] = []
    }

    /// Favourites by year: planned films by the planned day, unplanned ones by release date,
    /// and watched favourites by the day you watched them. Newest year first.
    private var yearGroups: [YearGroup] {
        var byYear: [Int: YearGroup] = [:]
        func year(_ day: String) -> Int { Int(day.prefix(4)) ?? D.cal.component(.year, from: Date()) }
        for item in store.plannedFilms where store.seen[item.0.id] == nil {
            let y = year(item.1.d)
            byYear[y, default: YearGroup(year: y)].planned.append(item)
        }
        for f in store.favs.compactMap({ store.index[$0] }).sorted(by: { $0.date > $1.date }) {
            if let s = store.seen[f.id] {
                let y = year(s.d)
                byYear[y, default: YearGroup(year: y)].watched.append(f)
            } else if store.plans[f.id] == nil {
                let y = year(f.date)
                byYear[y, default: YearGroup(year: y)].unplanned.append(f)
            }
        }
        return byYear.values.sorted { $0.year > $1.year }
    }

    private func unfav(_ f: Film) -> some View {
        Button(role: .destructive) { store.toggleFav(f) } label: { Label("Remove", systemImage: "star.slash") }
    }
}

// MARK: - Watched films by year

struct WatchedView: View {
    @Environment(Store.self) private var store
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var adding = false
    @State private var editing: String?

    var body: some View {
        NavigationStack {
            List {
                let items = store.watched(inYear: year)
                Section {
                    Picker("Year", selection: $year) {
                        ForEach(store.seenYears, id: \.self) { y in
                            let c = store.yearCounts(y)
                            Text("\(String(y)) — \(c.watched) (\(c.total))").tag(y)
                        }
                    }
                    let rated = items.map { $0.1.r }.filter { $0 > 0 }
                    let counts = store.yearCounts(year)
                    LabeledContent("Films watched", value: "\(counts.watched) (\(counts.total))")
                    if !rated.isEmpty {
                        LabeledContent("Average rating", value: String(format: "%.1f ★", Double(rated.reduce(0, +)) / Double(rated.count)))
                    }
                }
                if items.isEmpty {
                    ContentUnavailableView("Nothing watched in \(String(year))", systemImage: "popcorn",
                                           description: Text("Open a film and mark it as watched, or add one with +."))
                }
                ForEach(items, id: \.0) { item in
                    Group {
                        if store.index[item.0] != nil {
                            NavigationLink(value: item.0) { watchedRow(item.0, item.1) }
                        } else {
                            Button { editing = item.0 } label: { watchedRow(item.0, item.1) }
                                .foregroundStyle(.primary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.removeSeen(item.0) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Watched")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add a film you watched")
                }
            }
            .sheet(isPresented: $adding) { AddWatchedView().environment(store) }
            .sheet(item: Binding(get: { editing.map { EditTarget(id: $0) } }, set: { editing = $0?.id })) { t in
                AddWatchedView(editingId: t.id).environment(store)
            }
        }
    }

    private func watchedRow(_ id: String, _ s: SeenEntry) -> some View {
        let cat = Cat.from(s.c)
        let title = s.t ?? store.index[id]?.title ?? String(localized: "Film")
        return HStack(spacing: 12) {
            PosterTile(title: title, cat: cat, width: 40, url: store.index[id]?.poster ?? s.p)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).lineLimit(2)
                Text(String(localized: "Watched \(D.fmt(s.d, "d MMM"))") + (s.cn.map { " · \($0)" } ?? s.dir.map { " · \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Stars(rating: s.r)
            }
        }
    }
}

struct EditTarget: Identifiable { let id: String }

/// Adds a film you saw elsewhere, or edits one you added (title, date, rating).
struct AddWatchedView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var editingId: String? = nil
    @State private var title = ""
    @State private var day = Date()
    @State private var rating = 0
    @State private var cat: Cat = .D
    @State private var ready = false
    @State private var poster: String?
    @State private var hits: [ArtworkHit] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .onSubmit { Task { await findPosters() } }
                Section {
                    HStack(spacing: 14) {
                        PosterTile(title: title.isEmpty ? "?" : title, cat: cat, width: 64, url: poster)
                        VStack(alignment: .leading, spacing: 8) {
                            Button { Task { await findPosters() } } label: {
                                Label(searching ? String(localized: "Searching…") : String(localized: "Find the poster"), systemImage: "magnifyingglass")
                            }
                            .disabled(title.trimmingCharacters(in: .whitespaces).count < 2 || searching)
                            if poster != nil {
                                Button("Remove poster", role: .destructive) { poster = nil }.font(.footnote)
                            }
                        }
                    }
                    if !hits.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(hits) { h in
                                    Button {
                                        poster = h.poster
                                    } label: {
                                        VStack(spacing: 4) {
                                            PosterTile(title: h.title, cat: cat, width: 70, url: h.poster)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(poster == h.poster ? Color.theme : .clear, lineWidth: 3))
                                            Text(h.year).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Poster")
                } footer: {
                    Text("Posters come from Apple's film catalogue. Tap one to use it.")
                }
                DatePicker("Watched on", selection: $day, in: ...Date(), displayedComponents: .date)
                Picker("Category", selection: $cat) {
                    ForEach(Cat.allCases) { c in Text(c.label).tag(c) }
                }
                HStack {
                    Text("Rating")
                    Spacer()
                    ForEach(1...5, id: \.self) { i in
                        Button { rating = rating == i ? 0 : i } label: {
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .foregroundStyle(i <= rating ? Color(hex: 0xE0A800) : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle(editingId == nil ? String(localized: "Add a film") : String(localized: "Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingId == nil ? String(localized: "Add") : String(localized: "Save")) {
                        if let id = editingId {
                            store.updateCustomSeen(id, title: title, day: D.str(day), rating: rating, category: cat, poster: poster)
                        } else {
                            store.addCustomSeen(title: title, day: D.str(day), rating: rating, category: cat, poster: poster)
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !ready else { return }
                ready = true
                if let id = editingId, let s = store.seen[id] {
                    title = s.t ?? ""
                    day = D.date(s.d) ?? Date()
                    rating = s.r
                    cat = Cat.from(s.c)
                    poster = s.p
                }
            }
        }
    }

    private func findPosters() async {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        searching = true
        hits = await Artwork.shared.search(t)
        searching = false
        if poster == nil { poster = hits.first?.poster }
    }
}

// MARK: - Settings

struct DataView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @AppStorage("calSync") private var calOn = false
    @AppStorage("calId") private var calId = ""
    @AppStorage("tutorialSeen") private var tutorialSeen = true
    @AppStorage("welcomeDone") private var welcomeDone = true
    @AppStorage("userName") private var userName = ""
    @AppStorage("versionPref") private var versionPref = "any"
    @AppStorage("versionMust") private var versionMust = false
    @AppStorage("hideSeen") private var hideSeen = true
    @State private var calendarNote: String?

    private var versionSummary: String {
        switch (versionPref, versionMust) {
        case ("vo", true): return String(localized: "Original version only")
        case ("vo", false): return String(localized: "Original version first")
        case ("vf", true): return String(localized: "VF only")
        case ("vf", false): return String(localized: "VF first")
        default: return String(localized: "No preference")
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // My profile
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack(spacing: 12) {
                            Text("🦥").font(.largeTitle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(userName.isEmpty ? String(localized: "My profile") : userName).font(.headline)
                                Text("Name, cinemas, habits and all-time stats").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("My profile")
                }

                // Watching
                Section {
                    NavigationLink {
                        List { VersionQuestions() }
                            .navigationTitle("VO or VF")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Version", value: versionSummary)
                    }
                    Toggle("Hide films I've seen", isOn: $hideSeen)
                } header: {
                    Text("Watching")
                } footer: {
                    Text("Seen films leave the Films list, the search and the cinema pages. Search still offers to show them.")
                }

                NotificationSettings()

                // Manual refreshing
                Section {
                    Button {
                        Task { await store.refreshFromFeed(force: true) }
                    } label: {
                        Label("Check for new films and times now", systemImage: "arrow.clockwise")
                    }
                    if let d = store.lastFeedCheck {
                        LabeledContent("Last checked", value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let m = store.feedStatus { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    Text(store.dataSummary)
                    if let e = D.when(store.exportedAt) { LabeledContent("Last change", value: e) }
                } header: {
                    Text("Refresh")
                } footer: {
                    Text("Every morning before 7, Claude collects the session times from the cinemas' websites and AlloCiné, with posters, ratings and running times. Every Tuesday evening it adds the new weeks. The app downloads them when you open it, or when you pull down on the Films list.")
                }

                // Calendar
                Section {
                    Toggle("Save plans to my calendar", isOn: Binding(get: { calOn }, set: { on in
                        if on {
                            Task {
                                let ok = await CalendarSync.shared.requestAccess()
                                if ok {
                                    if calId.isEmpty { calId = CalendarSync.shared.defaultCalendarId ?? "" }
                                    calOn = true
                                    store.syncCalendar()
                                    calendarNote = nil
                                } else {
                                    calOn = false
                                    calendarNote = String(localized: "Calendar access is off. Allow it in iPhone Settings › Apps › Sloth Cinema › Calendars.")
                                }
                            }
                        } else {
                            calOn = false
                        }
                    }))
                    if calOn && CalendarSync.shared.authorized {
                        Picker("Calendar", selection: Binding(get: { calId }, set: { calId = $0; store.syncCalendar() })) {
                            ForEach(CalendarSync.shared.calendars(), id: \.calendarIdentifier) { c in
                                Text("\(c.title) · \(c.source.title)").tag(c.calendarIdentifier)
                            }
                        }
                    }
                    if let n = calendarNote { Text(n).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Confirmed plans are added, moved and removed automatically, with a reminder 2 hours before. For Google Calendar: on your iPhone go to Settings › Apps › Calendar › Calendar Accounts › Add Account › Google, then choose your Google calendar here.")
                }

                // Colours
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Theme.presets.indices, id: \.self) { i in
                                let preset = Theme.presets[i]
                                Button { Theme.shared.hex = preset.hex } label: {
                                    Circle().fill(Color(hex: preset.hex))
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().stroke(Color.primary, lineWidth: Theme.shared.hex == preset.hex ? 3 : 0).padding(-4))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(LocalizedStringKey(preset.name))
                            }
                        }
                        .padding(.vertical, 8).padding(.horizontal, 4)
                    }
                    ColorPicker("Any colour", selection: Theme.shared.binding, supportsOpacity: false)
                    Picker("Appearance", selection: Binding(get: { Theme.shared.appearance }, set: { Theme.shared.appearance = $0 })) {
                        Text("Automatic").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if Theme.shared.hex != Theme.slothRed {
                        Button("Back to Sloth red") { Theme.shared.hex = Theme.slothRed }
                    }
                } header: {
                    Text("Colours")
                } footer: {
                    Text("The colour of buttons, the stage curtains and your stats.")
                }

                // Tutorial
                Section {
                    Button { tutorialSeen = false; dismiss() } label: {
                        Label("Show the tutorial again", systemImage: "questionmark.circle")
                    }
                    Button { welcomeDone = false; dismiss() } label: {
                        Label("Set up again (name, cinemas, sorting)", systemImage: "sparkles")
                    }
                } header: {
                    Text("Tutorial")
                }

                // Information
                Section {
                    LabeledContent("Version", value: version)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        Label("Language and notifications", systemImage: "globe")
                    }
                    Link(destination: Feed.page) { Label("The data on GitHub", systemImage: "link") }
                } header: {
                    Text("Information")
                } footer: {
                    Text("Films, posters and ratings come from AlloCiné; session times from the cinemas' own websites (UGC, Le Grand Rex, Max Linder, Luminor, Le Louxor, Les 7 Parnassiens, Les 5 Caumartin, Elysées Lincoln, Le Grand Action, Le Balzac, Studio 28) and AlloCiné, with the classics the independent cinemas show; extra posters from Apple's film catalogue. The app follows your iPhone's language, English or French; change it in Settings › Apps › Sloth Cinema › Language.")
                }

                // Import
                Section {
                    Button { importing = true } label: { Label("Import paris-cinema.json", systemImage: "square.and.arrow.down") }
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Import")
                } footer: {
                    Text("On claude.ai, open Paris Cinema Weeks, tap Export for iPhone app, save the file to iCloud Drive and import it here. Your favourites, watched films and plans from the page are added to the app. Nothing is deleted.")
                }

                // Share
                Section {
                    if FileManager.default.fileExists(atPath: store.userURL.path) {
                        ShareLink(item: store.userURL) { Label("Share my lists (favourites, watched, plans)", systemImage: "square.and.arrow.up") }
                    }
                    ShareLink(item: Feed.page, subject: Text("Sloth Cinema"),
                              message: Text("Sloth Cinema: every film in Paris cinemas with today's session times, VO or VF. It's a free iPhone app you can install from this page with a Mac and Xcode.")) {
                        Label("Share this app with…", systemImage: "person.2")
                    }
                } header: {
                    Text("Share")
                } footer: {
                    Text("Your lists are a file you can keep as a backup or open on another iPhone. To install the app on a friend's iPhone without a Mac, Apple requires TestFlight or the App Store, which need a paid Apple Developer account (99 € a year). Until then, the link points to the code on GitHub.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { store.importFile(at: url, link: false) }
            }
        }
    }
}
