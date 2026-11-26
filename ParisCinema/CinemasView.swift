import SwiftUI
import MapKit

struct CinemasView: View {
    @Environment(Store.self) private var store
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.8600, longitude: 2.3400),
        span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)))
    @State private var selected: String?
    @State private var type: String = ""
    @State private var showList = false
    @State private var query = ""
    @State private var askToAdd = false
    @State private var adding = false
    @State private var open: EditTarget?

    private var shown: [Cinema] {
        store.allCinemas.filter { c in
            type.isEmpty || c.type == type || (type == "My cinemas" && store.isPreferred(c.name))
        }
    }
    private var typeChoices: [String] {
        Cinema.types + (store.extraCinemas.isEmpty ? [] : ["Other"])
    }

    var body: some View {
        NavigationStack {
            Group {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty { searchResults }
                else if showList { list } else { map }
            }
            .searchable(text: $query, prompt: "Find a cinema to add to My cinemas")
            .navigationTitle("Cinemas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Type", selection: $type) {
                            Text("All cinemas").tag("")
                            Text("My cinemas").tag("My cinemas")
                            ForEach(typeChoices, id: \.self) { t in Text(LocalizedStringKey(t)).tag(t) }
                        }
                    } label: {
                        Label(type.isEmpty ? String(localized: "All") : NSLocalizedString(type, comment: "Cinema type"), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showList.toggle() } label: {
                        Image(systemName: showList ? "map" : "list.bullet")
                    }
                    .accessibilityLabel(showList ? String(localized: "Show map") : String(localized: "Show list"))
                }
            }
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .onChange(of: type) { _, t in
                if t == "My cinemas" && store.myCinemas.isEmpty { askToAdd = true }
            }
            .onChange(of: selected) { _, name in
                if let name { open = EditTarget(id: name) }
            }
            .alert("No cinemas yet", isPresented: $askToAdd) {
                Button("Yes") { adding = true }
                Button("No", role: .cancel) { type = "" }
            } message: {
                Text("Would you like to add the cinemas you go to now?")
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    FavouriteCinemasList(intro: String(localized: "Search or scroll, and star the cinemas you go to."))
                        .navigationTitle("My cinemas")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { adding = false } } }
                }
                .environment(store)
            }
            .sheet(item: $open, onDismiss: { selected = nil }) { t in
                CinemaSheet(name: t.id)
                    .environment(store)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Cinemas matching the search, to star or open.
    private var searchResults: some View {
        let q = query.folded
        let found = store.allCinemas.filter { $0.name.folded.contains(q) || $0.address.folded.contains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return List {
            if found.isEmpty {
                Text("No cinema with that name. Try another word, or a postcode.").foregroundStyle(.secondary)
            }
            ForEach(found) { c in
                HStack {
                    Button { open = EditTarget(id: c.name) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.headline).foregroundStyle(.primary)
                            Text(c.address).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    starButton(c)
                }
            }
        }
    }

    private var map: some View {
        Map(position: $position, selection: $selected) {
            ForEach(shown) { c in
                Marker(c.name, systemImage: store.isPreferred(c.name) ? "star.fill" : "film", coordinate: c.coordinate)
                    .tint(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : c.typeColor)
                    .tag(c.name)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onAppear { LocationFinder.shared.askPermission() }
        .safeAreaInset(edge: .bottom) {
            if LocationFinder.shared.denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Location is off: allow it in Settings", systemImage: "location.slash")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var list: some View {
        List {
            let mine = store.myCinemas.compactMap { store.cinema(named: $0) }
            if (type.isEmpty || type == "My cinemas") {
                Section {
                    if mine.isEmpty {
                        Text("Tap the star on a cinema to add it here. New plans use your cinemas first.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(mine) { c in listRow(c) }
                } header: {
                    Text("My cinemas")
                }
            }
            ForEach(typeChoices.filter { type.isEmpty || $0 == type }, id: \.self) { t in
                Section {
                    ForEach(store.allCinemas.filter { $0.type == t }) { c in listRow(c) }
                } header: {
                    Text(LocalizedStringKey(t))
                } footer: {
                    Text(LocalizedStringKey(Cinema.typeBlurb(t)))
                }
            }
        }
    }

    private func listRow(_ c: Cinema) -> some View {
        HStack(alignment: .top) {
            Button { open = EditTarget(id: c.name) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.name).font(.headline).foregroundStyle(.primary)
                    Text(c.address).font(.subheadline).foregroundStyle(.secondary)
                    let n = store.filmsShowing(at: c.name).count
                    if n > 0 {
                        Text(n == 1 ? String(localized: "1 film showing") : String(localized: "\(n) films showing"))
                            .font(.caption).foregroundStyle(Color.theme)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            starButton(c)
        }
        .padding(.vertical, 2)
    }

    private func starButton(_ c: Cinema) -> some View {
        Button { store.togglePreferred(c) } label: {
            Image(systemName: store.isPreferred(c.name) ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(store.isPreferred(c.name) ? String(localized: "Remove from My cinemas") : String(localized: "Add to My cinemas"))
    }
}

// MARK: - One cinema: its films, sorted like the Films page, with the sessions left today

struct CinemaSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let name: String
    @AppStorage("weekSort") private var sortRaw = WeekSort.standard.rawValue
    @AppStorage("hideSeen") private var hideSeen = true

    private var cinema: Cinema? { store.cinema(named: name) }

    var body: some View {
        let all = store.filmsShowing(at: name)
        let unseen = all.filter { store.seen[$0.id] == nil }
        let sort = WeekSort(rawValue: sortRaw) ?? .standard
        let shown = sort.apply((hideSeen ? unseen : all).sorted { a, b in
            a.releaseSize.rank != b.releaseSize.rank ? a.releaseSize.rank < b.releaseSize.rank : a.date > b.date
        })
        let today = shown.filter { !store.sessions($0.id, at: name, on: D.today).isEmpty }
        let later = shown.filter { store.sessions($0.id, at: name, on: D.today).isEmpty }
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let c = cinema {
                                Text(verbatim: "\(NSLocalizedString(c.type, comment: "Cinema type")) · \(c.address)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(all.count == 1 ? String(localized: "1 film showing") : String(localized: "\(all.count) films showing"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let c = cinema {
                            Button { store.togglePreferred(c) } label: {
                                Image(systemName: store.isPreferred(c.name) ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(store.isPreferred(c.name) ? String(localized: "Remove from My cinemas") : String(localized: "Add to My cinemas"))
                        }
                    }
                    if let u = cinema?.directionsURL {
                        Link(destination: u) { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    }
                    ForEach(store.plannedFilms.filter { store.sameCinema($0.1.cn, name) }, id: \.0.id) { item in
                        NavigationLink(value: item.0.id) {
                            Label("\(item.0.title) · \(D.fmt(item.1.d, "EEE d MMM")) \(item.1.t)", systemImage: "calendar")
                                .font(.subheadline)
                        }
                    }
                }

                if !all.isEmpty && unseen.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Text("🎉").font(.system(size: 56))
                            Text("Congrats, you have seen them all!").font(.title3.weight(.bold))
                            Text("You'll get a notification when a new film comes to this cinema.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                if !today.isEmpty {
                    Section("Today") {
                        ForEach(today) { f in filmRow(f, day: D.today) }
                    }
                }
                if !later.isEmpty {
                    Section("Coming days") {
                        ForEach(later) { f in
                            if let next = store.nextSessions(f.id, at: name) { filmRow(f, day: next.day) }
                        }
                    }
                }
                if all.isEmpty {
                    Text("No session times known for this cinema yet.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    /// Poster, title and the day's sessions; tap a time to plan it.
    private func filmRow(_ f: Film, day: String) -> some View {
        let list = store.sessions(f.id, at: name, on: day)
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: f.id) {
                HStack(spacing: 12) {
                    PosterTile(title: f.title, cat: f.category, width: 58, url: f.poster)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Text([f.durationText, f.press.map { String(localized: "Critics \(String(format: "%.1f", $0))") },
                              f.spect.map { String(localized: "Audience \(String(format: "%.1f", $0))") }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if day != D.today {
                            Text(D.fmtCap(day, "EEEE d MMMM")).font(.caption.weight(.semibold)).foregroundStyle(Color.theme)
                        }
                        if store.seen[f.id] != nil {
                            Label("Seen", systemImage: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list) { s in
                        Button {
                            store.planFilm(f, day: day, time: s.time, cinemaName: name)
                        } label: {
                            TimeChip(time: s.time, selected: store.plans[f.id].map { $0.d == day && $0.t == s.time && store.sameCinema($0.cn, name) } ?? false,
                                     version: s.version)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
