import SwiftUI

struct PlanTarget: Identifiable {
    let id = UUID()
    let day: String
    let filmId: String?
}

// MARK: - My week: where and when you'll see each film

struct WeekPlanView: View {
    @Environment(Store.self) private var store
    @State private var week = D.weekOf(D.today)
    @State private var target: PlanTarget?

    var body: some View {
        NavigationStack {
            List {
                let due = store.duePlans
                if !due.isEmpty {
                    Section("Did you go?") {
                        ForEach(due, id: \.0.id) { item in
                            Button {
                                store.checkIn = CheckIn(id: item.0.id, action: "")
                            } label: {
                                HStack(spacing: 12) {
                                    PosterTile(title: item.0.title, cat: item.0.category, width: 36, url: item.0.poster)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.0.title).font(.headline).foregroundStyle(.primary)
                                        Text("Planned \(D.fmt(item.1.d, "EEE d MMM")) · \(item.1.t) · \(item.1.cn)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("Rate").font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                    }
                }

                Section { weekHeader }

                ForEach(0..<7, id: \.self) { i in
                    let day = D.addDays(week, i)
                    Section {
                        ForEach(plans(on: day), id: \.0.id) { item in
                            NavigationLink(value: item.0.id) { planRow(item.0, item.1) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { store.removePlan(item.0.id) } label: {
                                        Label("Remove", systemImage: "calendar.badge.minus")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if item.1.ok != true {
                                        Button { store.confirmPlan(item.0.id) } label: { Label("Confirm", systemImage: "checkmark") }
                                            .tint(.green)
                                    }
                                }
                        }
                        if day >= D.today {
                            Button { target = PlanTarget(day: day, filmId: nil) } label: {
                                Label("Add a film", systemImage: "plus.circle")
                            }
                        }
                    } header: {
                        Text(dayTitle(day))
                    }
                }

                let unplanned = store.otherFavourites.filter { store.seen[$0.id] == nil }
                if !unplanned.isEmpty {
                    Section("Favourites without a plan") {
                        ForEach(unplanned) { f in
                            HStack {
                                FilmRow(film: f, showDate: true)
                                Button("Plan") {
                                    let start = f.date > D.today ? f.date : D.today
                                    target = PlanTarget(day: D.saturdayAfter(start), filmId: f.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My week")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .sheet(item: $target) { t in AddPlanView(target: t).environment(store) }
        }
    }

    private var weekHeader: some View {
        HStack {
            Button { week = D.addDays(week, -7) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(week == D.weekOf(D.today) ? "This week" : "Week of \(D.fmt(week, "d MMMM"))").font(.headline)
                Text(D.weekRange(week)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { week = D.addDays(week, 7) } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Next week")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func plans(on day: String) -> [(Film, Plan)] {
        store.plannedFilms.filter { $0.1.d == day }
    }

    private func planRow(_ f: Film, _ p: Plan) -> some View {
        HStack(spacing: 12) {
            Text(p.t).font(.headline.monospacedDigit()).frame(width: 52, alignment: .leading)
            PosterTile(title: f.title, cat: f.category, width: 34, url: f.poster)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.headline).lineLimit(2)
                HStack(spacing: 4) {
                    if store.isPreferred(p.cn) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color(hex: 0xE0A800))
                    }
                    Text(p.cn).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if p.ok != true {
                    Text("Provisional · swipe right to confirm").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private func dayTitle(_ day: String) -> String {
        let base = D.fmt(day, "EEEE d MMMM")
        if day == D.today { return "Today · " + base }
        if day == D.addDays(D.today, 1) { return "Tomorrow · " + base }
        return base
    }
}

// MARK: - Add or change a plan

struct AddPlanView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: PlanTarget

    @State private var filmId: String?
    @State private var start = Date()
    @State private var cinemaName = ""
    @State private var ready = false

    private var film: Film? { filmId.flatMap { store.index[$0] } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Film") {
                    NavigationLink {
                        FilmChooserView(selected: $filmId)
                    } label: {
                        if let f = film {
                            HStack(spacing: 12) {
                                PosterTile(title: f.title, cat: f.category, width: 40, url: f.poster)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.headline)
                                    Text("In cinemas from \(D.fmt(f.date, "d MMM"))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Choose a film", systemImage: "film")
                        }
                    }
                }

                Section {
                    DatePicker("Day and time", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, D.paris)
                    if let f = film {
                        let day = D.stampString(start).day
                        let shows = store.showings(for: f.id).filter { $0.day == day }
                        if !shows.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(shows) { s in
                                        Button {
                                            start = D.stamp(day: s.day, time: s.time) ?? start
                                            cinemaName = s.cinema
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(s.time).font(.subheadline.weight(.semibold))
                                                Text(s.cinema).font(.caption2).lineLimit(1)
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text("After the film you'll get a notification to say how it was, or to pick another day.")
                }

                Section("Where") {
                    NavigationLink {
                        CinemaPickerView(film: film, selected: $cinemaName)
                    } label: {
                        LabeledContent("Cinema", value: cinemaName.isEmpty ? "Choose" : cinemaName)
                    }
                }
            }
            .navigationTitle("Plan a film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(film == nil || cinemaName.isEmpty)
                }
            }
            .onAppear(perform: setUp)
            .onChange(of: filmId) { _, _ in
                if cinemaName.isEmpty, let f = film { cinemaName = store.defaultCinema(for: f).name }
            }
        }
    }

    private func setUp() {
        guard !ready else { return }
        ready = true
        filmId = target.filmId
        let existing = target.filmId.flatMap { store.plans[$0] }
        start = D.stamp(day: existing?.d ?? target.day, time: existing?.t ?? "20:00") ?? Date()
        if let e = existing { cinemaName = e.cn }
        else if let f = film { cinemaName = store.defaultCinema(for: f).name }
        else if let first = store.myCinemas.first { cinemaName = first }
    }

    private func save() {
        guard let f = film else { return }
        let s = D.stampString(start)
        store.planFilm(f, day: s.day, time: s.time, cinemaName: cinemaName)
        dismiss()
    }
}

// MARK: - Pick a film for a plan

struct FilmChooserView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: String?
    @State private var query = ""

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                let favs = store.favs.compactMap { store.index[$0] }
                    .filter { store.seen[$0.id] == nil }
                    .sorted { $0.date > $1.date }
                if !favs.isEmpty {
                    Section("Your favourites") { ForEach(favs) { f in choice(f) } }
                }
                Section("In cinemas now") { ForEach(outNow) { f in choice(f) } }
            } else {
                Section { ForEach(Array(store.search(query).prefix(80))) { f in choice(f) } }
            }
        }
        .navigationTitle("Choose a film")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Any film since January")
    }

    private var outNow: [Film] {
        let from = D.addDays(D.today, -35), to = D.addDays(D.today, 6)
        let list = store.films.filter { $0.date >= from && $0.date <= to && $0.category != .E }
        return Array(list.sorted { a, b in
            if a.releaseSize.rank != b.releaseSize.rank { return a.releaseSize.rank < b.releaseSize.rank }
            return a.date > b.date
        }.prefix(80))
    }

    private func choice(_ f: Film) -> some View {
        Button {
            selected = f.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                PosterTile(title: f.title, cat: f.category, width: 40, url: f.poster)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text("\(D.fmt(f.date, "d MMM")) · \(f.category.short)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected == f.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
    }
}

// MARK: - After the film: how was it, or when instead?

struct CheckInView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let checkIn: CheckIn

    @State private var watched = true
    @State private var rating = 0
    @State private var watchedOn = Date()
    @State private var newStart = Date()
    @State private var cinemaName = ""
    @State private var ready = false

    private var film: Film? { store.index[checkIn.id] }

    var body: some View {
        NavigationStack {
            Form {
                if let f = film {
                    Section {
                        HStack(spacing: 14) {
                            PosterTile(title: f.title, cat: f.category, width: 56, url: f.poster)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(f.title).font(.headline)
                                if let p = store.plans[f.id] {
                                    Text("Planned \(D.fmt(p.d, "EEE d MMM")) at \(p.t) · \(p.cn)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Picker("Did you watch it?", selection: $watched) {
                            Text("I watched it").tag(true)
                            Text("Not yet").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if watched {
                        Section("How was it?") {
                            HStack {
                                Spacer()
                                ForEach(1...5, id: \.self) { i in
                                    Button { rating = i } label: {
                                        Image(systemName: i <= rating ? "star.fill" : "star")
                                            .font(.title)
                                            .foregroundStyle(i <= rating ? Color(hex: 0xE0A800) : Color.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                                }
                                Spacer()
                            }
                            DatePicker("Watched on", selection: $watchedOn, in: ...Date(), displayedComponents: .date)
                                .environment(\.timeZone, D.paris)
                        }
                    } else {
                        Section {
                            DatePicker("New day and time", selection: $newStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .environment(\.timeZone, D.paris)
                            NavigationLink {
                                CinemaPickerView(film: f, selected: $cinemaName)
                            } label: {
                                LabeledContent("Cinema", value: cinemaName)
                            }
                        } header: {
                            Text("When will you go?")
                        } footer: {
                            Text("You'll get another notification after the new date.")
                        }
                        Section {
                            Button("I'm not going to see it", role: .destructive) {
                                store.dropPlan(f.id)
                                dismiss()
                            }
                        }
                    }
                } else {
                    Text("This film is no longer in your plans.")
                }
            }
            .navigationTitle(watched ? "How was it?" : "Plan again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(film == nil) }
            }
            .onAppear(perform: setUp)
        }
    }

    private func setUp() {
        guard !ready else { return }
        ready = true
        watched = checkIn.action != "NOT_YET"
        let p = store.plans[checkIn.id]
        let planned = p.flatMap { D.date($0.d) } ?? Date()
        watchedOn = min(planned, Date())
        newStart = D.stamp(day: D.saturdayAfter(D.addDays(D.today, 1)), time: p?.t ?? "20:00") ?? Date()
        cinemaName = p?.cn ?? film.map { store.defaultCinema(for: $0).name } ?? ""
    }

    private func save() {
        guard let f = film else { return }
        if watched {
            store.setSeen(f, rating: rating, on: D.str(watchedOn))
        } else {
            let s = D.stampString(newStart)
            store.planFilm(f, day: s.day, time: s.time, cinemaName: cinemaName)
        }
        dismiss()
    }
}
