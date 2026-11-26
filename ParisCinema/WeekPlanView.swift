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

// MARK: - Add or change a plan: film, then day, then cinema and session

struct AddPlanView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: PlanTarget

    @State private var filmId: String?
    @State private var day = D.today
    @State private var time = "20:00"
    @State private var cinemaName = ""
    @State private var showCalendar = false
    @State private var ready = false

    private var film: Film? { filmId.flatMap { store.index[$0] } }
    private var days: [String] { (0..<14).map { D.addDays(D.today, $0) } }

    /// Your first three starred cinemas, then the chosen cinema if it's another one.
    private var suggested: [Cinema] {
        var list = Array(store.myCinemas.compactMap { store.cinema(named: $0) }.prefix(3))
        if list.count < 3, let f = film {
            // Fill up with cinemas that show the film, then typical ones.
            let showing = (store.showtimes[f.id]?.cinemas ?? []).compactMap { $0.name }.compactMap { store.cinema(named: $0) }
            for c in showing + [store.defaultCinema(for: f)] where list.count < 3 && !list.contains(c) { list.append(c) }
        }
        if !cinemaName.isEmpty, !list.contains(where: { $0.name == cinemaName }), let c = store.cinema(named: cinemaName) {
            list.append(c)
        }
        return list
    }

    private func sessions(_ c: Cinema, _ d: String) -> [String] {
        guard let f = film else { return [] }
        let now = D.stampString(Date()).time
        return (store.showtimes(for: f.id, at: c.name)[d] ?? []).filter { d > D.today || $0 >= now }
    }

    private func hasSessions(_ d: String) -> Bool { suggested.contains { !sessions($0, d).isEmpty } }

    private var chosenHasSessions: Bool {
        guard let c = store.cinema(named: cinemaName) else { return false }
        return !sessions(c, day).isEmpty
    }

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
                                    Text([("In cinemas from " + D.fmt(f.date, "d MMM")), f.durationText].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Choose a film", systemImage: "film")
                        }
                    }
                }

                if film != nil {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(days, id: \.self) { d in
                                    Button { pickDay(d) } label: {
                                        DayChip(day: d, selected: d == day, available: hasSessions(d))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        DisclosureGroup("Calendar", isExpanded: $showCalendar) {
                            DatePicker("Day", selection: Binding(get: { D.date(day) ?? Date() }, set: { pickDay(D.str($0)) }),
                                       in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .environment(\.timeZone, D.paris)
                        }
                    } header: {
                        Text("1. Day · \(D.fmt(day, "EEEE d MMMM"))")
                    } footer: {
                        Text("A green dot means one of your cinemas below shows the film that day.")
                    }

                    Section {
                        ForEach(suggested) { c in cinemaRow(c) }
                        NavigationLink {
                            CinemaPickerView(film: film, selected: $cinemaName)
                        } label: {
                            Label("Another cinema", systemImage: "magnifyingglass")
                        }
                    } header: {
                        Text("2. Cinema and session")
                    } footer: {
                        if store.myCinemas.isEmpty {
                            Text("Star your cinemas in the Cinemas tab: your first three appear here, with their session times.")
                        } else {
                            Text("Tap a session time to choose it. Session times come from the daily check at 7 am.")
                        }
                    }

                    if !chosenHasSessions {
                        Section {
                            DatePicker("Time", selection: Binding(get: { D.stamp(day: day, time: time) ?? Date() },
                                                                  set: { time = D.stampString($0).time }),
                                       displayedComponents: .hourAndMinute)
                                .environment(\.timeZone, D.paris)
                        } header: {
                            Text("3. Time")
                        } footer: {
                            Text("No session times known for \(cinemaName.isEmpty ? "this cinema" : cinemaName) that day, so pick a time yourself.")
                        }
                    }

                    Section {
                        Label("\(D.fmt(day, "EEE d MMM")) at \(time)\(cinemaName.isEmpty ? "" : " · " + cinemaName)", systemImage: "ticket")
                            .font(.headline)
                    } footer: {
                        Text("After the film you'll get a notification to say how it was, or to pick another day.")
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
            .onChange(of: filmId) { old, _ in
                // The first change is the film this sheet opened with; setUp already handled it.
                if old != nil || target.filmId == nil { suggestDay() }
            }
        }
    }

    private func cinemaRow(_ c: Cinema) -> some View {
        let times = sessions(c, day)
        let chosen = c.name == cinemaName
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                cinemaName = c.name
                if let first = times.first, !times.contains(time) { time = times.first { $0 >= "18:00" } ?? first }
            } label: {
                HStack(spacing: 6) {
                    if store.isPreferred(c.name) {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Color(hex: 0xE0A800))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.headline).foregroundStyle(.primary)
                        Text(c.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if times.isEmpty {
                Text("No session times known for this day")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(times, id: \.self) { t in
                        Button {
                            cinemaName = c.name
                            time = t
                        } label: {
                            TimeChip(time: t, selected: chosen && t == time)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pickDay(_ d: String) {
        day = d
        if let c = store.cinema(named: cinemaName) {
            let times = sessions(c, d)
            if !times.isEmpty && !times.contains(time) { time = times.first { $0 >= "18:00" } ?? times[times.count - 1] }
        }
    }

    /// Suggests the first day one of your cinemas shows the film, else the release day or the chosen day.
    private func suggestDay() {
        guard let f = film else { return }
        if let d = days.first(where: { hasSessions($0) }) {
            day = d
            if let c = suggested.first(where: { !sessions($0, d).isEmpty }) {
                cinemaName = c.name
                let times = sessions(c, d)
                time = times.first { $0 >= "18:00" } ?? times[times.count - 1]
            }
        } else {
            if f.date > day { day = f.date }
            if cinemaName.isEmpty { cinemaName = suggested.first?.name ?? store.defaultCinema(for: f).name }
        }
    }

    private func setUp() {
        guard !ready else { return }
        ready = true
        day = max(target.day, D.today)
        filmId = target.filmId
        if let id = target.filmId, let existing = store.plans[id], existing.ok == true {
            day = existing.d
            time = existing.t
            cinemaName = existing.cn
        } else {
            suggestDay()
        }
    }

    private func save() {
        guard let f = film else { return }
        store.planFilm(f, day: day, time: time, cinemaName: cinemaName)
        dismiss()
    }
}

struct DayChip: View {
    let day: String
    let selected: Bool
    let available: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(day == D.today ? "Today" : D.fmt(day, "EEE")).font(.caption2)
            Text(D.fmt(day, "d")).font(.headline)
            Circle().fill(available ? Color.green : Color.clear).frame(width: 6, height: 6)
        }
        .frame(width: 50, height: 62)
        .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(D.fmt(day, "EEEE d MMMM") + (available ? ", sessions available" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TimeChip: View {
    let time: String
    let selected: Bool

    var body: some View {
        Text(time)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .frame(minWidth: 58)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(selected ? Color.accentColor : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
