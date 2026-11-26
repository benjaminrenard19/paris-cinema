import SwiftUI
import UniformTypeIdentifiers

// MARK: - My list (favourites and watch plans)

struct MyListView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            List {
                let planned = store.plannedFilms
                let others = store.otherFavourites
                if planned.isEmpty && others.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "star",
                                           description: Text("Tap the star on a film. Films you haven't seen get a provisional day to watch them, which you can send to your calendar."))
                }
                if !planned.isEmpty {
                    Section("Planned") {
                        ForEach(planned, id: \.0.id) { item in
                            NavigationLink(value: item.0.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    FilmRow(film: item.0, showDate: true)
                                    Label("\(D.fmt(item.1.d, "EEE d MMM")) · \(item.1.t) · \(item.1.cn)", systemImage: "calendar")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(item.1.d < D.today ? Color.red : Color.accentColor)
                                }
                            }
                            .swipeActions { unfav(item.0) }
                        }
                    }
                }
                if !others.isEmpty {
                    Section("Other favourites") {
                        ForEach(others) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f, showDate: true) }
                                .swipeActions { unfav(f) }
                        }
                    }
                }
            }
            .navigationTitle("My list")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
        }
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

    var body: some View {
        NavigationStack {
            List {
                let items = store.watched(inYear: year)
                Section {
                    Picker("Year", selection: $year) {
                        ForEach(store.seenYears, id: \.self) { y in Text(String(y)).tag(y) }
                    }
                    let rated = items.map { $0.1.r }.filter { $0 > 0 }
                    LabeledContent("Films watched", value: "\(items.count)")
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
                            watchedRow(item.0, item.1)
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
        }
    }

    private func watchedRow(_ id: String, _ s: SeenEntry) -> some View {
        let cat = Cat.from(s.c)
        let title = s.t ?? store.index[id]?.title ?? "Film"
        return HStack(spacing: 12) {
            PosterTile(title: title, cat: cat, width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).lineLimit(2)
                Text("Watched \(D.fmt(s.d, "d MMM"))" + (s.dir.map { " · \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Stars(rating: s.r)
            }
        }
    }
}

struct AddWatchedView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var day = Date()
    @State private var rating = 0
    @State private var cat: Cat = .D

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
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
            .navigationTitle("Add a film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addCustomSeen(title: title, day: D.str(day), rating: rating, category: cat)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Data: import the export from the Claude page

struct DataView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Loaded") {
                    Text(store.dataSummary)
                    if let e = D.when(store.exportedAt) { LabeledContent("Last change", value: e) }
                }

                Section {
                    Button {
                        Task { await store.refreshFromFeed(force: true) }
                    } label: {
                        Label("Check for new films now", systemImage: "arrow.clockwise")
                    }
                    if let d = store.lastFeedCheck {
                        LabeledContent("Last checked", value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let m = store.feedStatus { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    Link(destination: Feed.page) { Label("Open the data on GitHub", systemImage: "link") }
                } header: {
                    Text("Automatic updates")
                } footer: {
                    Text("Every Tuesday evening Claude adds the new weeks, producers and showtimes for your planned films to GitHub. The app downloads them when you open it, or when you pull down on the Films list.")
                }

                Section {
                    Button { importing = true } label: { Label("Import paris-cinema.json", systemImage: "square.and.arrow.down") }
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Bring over your lists from the Claude page")
                } footer: {
                    Text("On claude.ai, open Paris Cinema Weeks, tap Export for iPhone app, save the file to iCloud Drive and import it here. Your favourites, watched films and plans from the page are added to the app. Nothing is deleted.")
                }

                if FileManager.default.fileExists(atPath: store.userURL.path) {
                    Section("Backup") {
                        ShareLink(item: store.userURL) { Label("Share my lists (favourites, watched, plans)", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Films data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { store.importFile(at: url, link: false) }
            }
        }
    }
}
