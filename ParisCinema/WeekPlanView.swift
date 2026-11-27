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
    @State private var inviting: EditTarget?

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
                                    Button { inviting = EditTarget(id: item.0.id) } label: { Label("Invite", systemImage: "person.2.wave.2") }
                                        .tint(.blue)
                                }
                                .contextMenu {
                                    Button { inviting = EditTarget(id: item.0.id) } label: { Label("Invite someone", systemImage: "person.2.wave.2") }
                                }
                            if day >= D.today { InARowRow(film: item.0, plan: item.1) }
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
                    Section("OTW films without a plan") {
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
            .navigationTitle("🗓️ " + weekTitle)
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .sheet(item: $target) { t in AddPlanView(target: t).environment(store) }
            .sheet(item: $inviting) { t in InviteSheet(filmId: t.id).environment(store) }
        }
    }

    /// "My week", "Next week", "Last week", else "Week of 9 – 15 Dec".
    private var weekTitle: String {
        let now = D.weekOf(D.today)
        if week == now { return String(localized: "My week") }
        if week == D.addDays(now, 7) { return String(localized: "Next week") }
        if week == D.addDays(now, -7) { return String(localized: "Last week") }
        let end = D.addDays(week, 6)
        let range = D.fmt(week, "MMM") == D.fmt(end, "MMM")
            ? "\(D.fmt(week, "d")) – \(D.fmt(end, "d MMM"))" : "\(D.fmt(week, "d MMM")) – \(D.fmt(end, "d MMM"))"
        return String(localized: "Week of \(range)")
    }

    private var weekHeader: some View {
        HStack {
            Button { week = D.addDays(week, -7) } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(D.weekRange(week)).font(.subheadline.weight(.semibold))
                if week != D.weekOf(D.today) {
                    Button("Back to my week") { week = D.weekOf(D.today) }.font(.caption)
                }
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
                ExitTimeLine(id: f.id, day: p.d, time: p.t, cinema: p.cn, compact: true)
                    .font(.caption).foregroundStyle(.secondary)
                ClashWarning(clashes: store.clashes(f.id, day: p.d, time: p.t, cinema: p.cn))
            }
        }
    }

    private func dayTitle(_ day: String) -> String {
        let base = D.fmt(day, "EEEE d MMMM")
        if day == D.today { return String(localized: "Today · \(base)") }
        if day == D.addDays(D.today, 1) { return String(localized: "Tomorrow · \(base)") }
        return D.fmtCap(day, "EEEE d MMMM")
    }
}

// MARK: - Add or change a plan: film, cinema, then its first session

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
    @State private var clashAsk: ClashQuestion?

    private var film: Film? { filmId.flatMap { store.index[$0] } }
    private var days: [String] { (0..<14).map { D.addDays(D.today, $0) } }
    private var usualTime: String { store.habits.usualTime ?? "20:00" }

    /// The film's sessions at a cinema on a day, from now on, your version first.
    private func sessionList(_ name: String, _ d: String) -> [Session] {
        guard let f = film, !name.isEmpty else { return [] }
        return store.sessions(f.id, at: name, on: d)
    }

    private func sessions(_ name: String, _ d: String) -> [String] { sessionList(name, d).map { $0.time } }

    /// Days in the next two weeks when a cinema shows the film.
    private func sessionDays(_ name: String) -> [String] { days.filter { !sessions(name, $0).isEmpty } }

    /// Your favourite cinemas, then the ones you go to most, then any cinema showing the film (soonest first).
    private var candidates: [String] {
        var out: [String] = []
        func add(_ n: String) {
            if !n.isEmpty && !out.contains(where: { store.sameCinema($0, n) }) { out.append(n) }
        }
        store.myCinemas.forEach(add)
        store.habits.cinemas.forEach(add)
        if let f = film {
            let showing: [(String, String)] = (store.showtimes[f.id]?.cinemas ?? []).compactMap { c in
                guard let n = c.name, let first = sessionDays(n).first else { return nil }
                return (n, first)
            }
            showing.sorted { $0.1 < $1.1 }.forEach { add($0.0) }
        }
        return out
    }

    /// Other cinemas showing the film on the chosen day, your favourites first.
    private var otherCinemasThatDay: [String] {
        candidates.filter { !store.sameCinema($0, cinemaName) && !sessions($0, day).isEmpty }
    }

    private func address(_ name: String) -> String {
        if let a = store.cinema(named: name)?.address { return a }
        guard let f = film else { return "" }
        return store.showtimes[f.id]?.cinemas?.first(where: { store.sameCinema($0.name ?? "", name) })?.address ?? ""
    }

    private func isFavourite(_ name: String) -> Bool { store.myCinemas.contains { store.sameCinema($0, name) } }

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
                                    Text([String(localized: "In cinemas from \(D.fmt(f.date, "d MMM"))"), f.durationText].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Label("Choose a film", systemImage: "film")
                        }
                    }
                }

                if film != nil {
                    cinemaSection
                    sessionSection
                    Section {
                        Label("\(D.fmt(day, "EEE d MMM")) · \(time)\(cinemaName.isEmpty ? "" : " · " + cinemaName)", systemImage: "ticket")
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
                if old != nil || target.filmId == nil { chooseBest(preferDay: target.filmId == nil ? target.day : nil) }
            }
            .onChange(of: cinemaName) { _, _ in pickTime() }
        }
        .clashQuestion($clashAsk) { dismiss() }
    }

    // MARK: Cinema

    private var cinemaSection: some View {
        Section {
            NavigationLink {
                CinemaPickerView(film: film, selected: $cinemaName)
            } label: {
                HStack(spacing: 8) {
                    if isFavourite(cinemaName) {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Color(hex: 0xE0A800))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cinemaName.isEmpty ? String(localized: "Choose a cinema") : cinemaName).font(.headline)
                        let a = address(cinemaName)
                        if !a.isEmpty { Text(a).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
            let quick = Array(candidates.prefix(6))
            if quick.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.self) { name in
                            Button { cinemaName = name; jumpToFirstSession() } label: {
                                CinemaChip(name: name, favourite: isFavourite(name),
                                           next: sessionDays(name).first.map { D.fmt($0, "EEE d") },
                                           selected: store.sameCinema(name, cinemaName))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("1. Cinema")
        } footer: {
            if let h = store.habits.summary {
                Text(h)
            } else if store.myCinemas.isEmpty {
                Text("Star your cinemas in the Cinemas tab: they come first here, with their session times.")
            }
        }
    }

    // MARK: Day and session

    private var sessionSection: some View {
        let times = sessionList(cinemaName, day)
        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { d in
                        Button { pickDay(d) } label: {
                            DayChip(day: d, selected: d == day, available: !sessions(cinemaName, d).isEmpty)
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
            if !times.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(times) { s in
                        Button { time = s.time } label: {
                            TimeChip(time: s.time, selected: s.time == time, version: s.version,
                                     clash: filmId.map { !store.clashes($0, day: day, time: s.time, cinema: cinemaName).isEmpty } ?? false)
                        }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } else {
                noSession
            }
            if let id = filmId, times.contains(where: { $0.time == time }) {
                VStack(alignment: .leading, spacing: 4) {
                    ExitTimeLine(id: id, day: day, time: time, cinema: cinemaName)
                        .font(.subheadline)
                    ClashWarning(clashes: store.clashes(id, day: day, time: time, cinema: cinemaName))
                }
            }
        } header: {
            Text("2. Day and session · \(D.fmt(day, "EEEE d MMMM"))")
        } footer: {
            Text("A green dot marks the days this cinema shows the film. Times come from the cinemas' websites and AlloCiné, every morning.")
        }
    }

    /// No session at the chosen cinema that day: say so, then offer its next session or another cinema.
    @ViewBuilder
    private var noSession: some View {
        Label(cinemaName.isEmpty ? String(localized: "Choose a cinema to see its sessions.")
                                 : String(localized: "No session at \(cinemaName) on \(D.fmt(day, "EEEE d MMMM")).") ,
              systemImage: "calendar.badge.exclamationmark")
            .foregroundStyle(.orange)
        if let next = sessionDays(cinemaName).first(where: { $0 > day }) ?? sessionDays(cinemaName).first,
           let first = sessions(cinemaName, next).first {
            Button { pickDay(next) } label: {
                Label(String(localized: "Next session there: \(D.fmt(next, "EEEE d MMMM")) at \(first)"), systemImage: "arrow.right.circle.fill")
            }
        } else if !cinemaName.isEmpty {
            Text("No session times known there for the next two weeks.").font(.footnote).foregroundStyle(.secondary)
        }
        let others = Array(otherCinemasThatDay.prefix(4))
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Other cinemas showing it that day").font(.subheadline.weight(.semibold))
                ForEach(others, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            if isFavourite(name) {
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color(hex: 0xE0A800))
                            }
                            Text(name).font(.subheadline)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sessionList(name, day)) { s in
                                    Button {
                                        cinemaName = name
                                        time = s.time
                                    } label: {
                                        TimeChip(time: s.time, selected: false, version: s.version,
                                                 clash: filmId.map { !store.clashes($0, day: day, time: s.time, cinema: name).isEmpty } ?? false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        DatePicker("Or pick a time yourself", selection: Binding(get: { D.stamp(day: day, time: time) ?? Date() },
                                                               set: { time = D.stampString($0).time }),
                   displayedComponents: .hourAndMinute)
            .environment(\.timeZone, D.paris)
    }

    // MARK: Choices

    private func pickDay(_ d: String) {
        day = d
        pickTime()
    }

    /// The session nearest the time you usually go, in the version you prefer,
    /// leaving out sessions that overlap another plan when there is a free one.
    private func pickTime() {
        let all = sessionList(cinemaName, day)
        guard let f = film, !all.isEmpty, !all.contains(where: { $0.time == time }) else { return }
        let pool = store.preferredPool(all, for: f.id).map { $0.time }
        let free = pool.filter { store.clashes(f.id, day: day, time: $0, cinema: cinemaName).isEmpty }
        let choices = free.isEmpty ? pool : free
        time = Habits.closest(choices, to: usualTime) ?? choices[0]
    }

    /// After choosing a cinema: its first day with a session, unless the chosen day has one.
    private func jumpToFirstSession() {
        if sessions(cinemaName, day).isEmpty, let first = sessionDays(cinemaName).first { day = first }
        pickTime()
    }

    /// The first cinema of the suggestions that shows the film (your favourites first), on its first
    /// day with a session, at the session nearest the time you usually go.
    private func chooseBest(preferDay: String?) {
        guard let f = film else { return }
        let list = candidates
        if let d = preferDay, let c = list.first(where: { !sessions($0, d).isEmpty }) {
            cinemaName = c
            day = d
        } else if let c = list.first(where: { !sessionDays($0).isEmpty }) {
            cinemaName = c
            day = sessionDays(c).first ?? day
        } else {
            if cinemaName.isEmpty { cinemaName = list.first ?? store.defaultCinema(for: f).name }
            if f.date > day { day = f.date }
            time = usualTime
        }
        pickTime()
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
            chooseBest(preferDay: target.filmId == nil ? day : nil)
        }
    }

    private func save() {
        guard let f = film else { return }
        if let q = store.requestPlan(f, day: day, time: time, cinemaName: cinemaName) {
            clashAsk = q
        } else {
            dismiss()
        }
    }
}

/// A cinema to switch to, with its next day showing the film.
struct CinemaChip: View {
    let name: String
    let favourite: Bool
    let next: String?
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if favourite { Image(systemName: "star.fill").font(.system(size: 9)) }
                Text(name).font(.caption.weight(.semibold)).lineLimit(1)
            }
            Text(next.map { String(localized: "Next: \($0)") } ?? String(localized: "No sessions known"))
                .font(.caption2).opacity(0.8)
        }
        .frame(maxWidth: 170, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selected ? Color.theme : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct DayChip: View {
    let day: String
    let selected: Bool
    let available: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(day == D.today ? String(localized: "Today") : D.fmt(day, "EEE")).font(.caption2)
            Text(D.fmt(day, "d")).font(.headline)
            Circle().fill(available ? Color.green : Color.clear).frame(width: 6, height: 6)
        }
        .frame(width: 50, height: 62)
        .background(selected ? Color.theme : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(D.fmt(day, "EEEE d MMMM") + (available ? String(localized: ", sessions available") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TimeChip: View {
    let time: String
    let selected: Bool
    var version: String? = nil
    /// Overlaps another of your plans that day (shown in orange).
    var clash = false

    var body: some View {
        VStack(spacing: 1) {
            Text(time)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if let v = VersionPrefs.label(version) {
                Text(v).font(.system(size: 9, weight: .bold)).opacity(0.85)
            }
        }
            .frame(minWidth: 58)
            .padding(.horizontal, 8).padding(.vertical, version == nil ? 8 : 4)
            .background(selected ? (clash ? Color.orange : Color.theme) : (clash ? Color.orange.opacity(0.12) : Color.theme.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if clash { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).offset(x: 3, y: -3) }
            }
            .foregroundStyle(selected ? Color.white : (clash ? Color.orange : Color.theme))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(clash ? String(localized: "Overlaps another of your plans") : "")
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
                    Section("Your OTW films") { ForEach(favs) { f in choice(f) } }
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
                if selected == f.id { Image(systemName: "checkmark").foregroundStyle(Color.theme) }
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
    @State private var rating = 0.0
    @State private var with: [String] = []
    @State private var watchedOn = Date()
    @State private var newStart = Date()
    @State private var cinemaName = ""
    @State private var ready = false
    @State private var clashAsk: ClashQuestion?

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
                                HalfStarPicker(value: $rating, size: 32)
                                Spacer()
                            }
                            CompanionPicker(selected: $with)
                            DatePicker("Watched on", selection: $watchedOn, in: ...Date(), displayedComponents: .date)
                                .environment(\.timeZone, D.paris)
                        }
                    } else {
                        Section {
                            DatePicker("New day and time", selection: $newStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .environment(\.timeZone, D.paris)
                            if let f = film {
                                let st = D.stampString(newStart)
                                ExitTimeLine(id: f.id, day: st.day, time: st.time, cinema: cinemaName)
                                    .font(.subheadline)
                            }
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
            .navigationTitle(watched ? String(localized: "How was it?") : String(localized: "Plan again"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(film == nil) }
            }
            .onAppear(perform: setUp)
        }
        .clashQuestion($clashAsk) { dismiss() }
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
        with = p?.w ?? []
    }

    private func save() {
        guard let f = film else { return }
        if watched {
            store.setSeen(f, value: rating, on: D.str(watchedOn))
            store.setCompanions(f.id, with)
        } else {
            let s = D.stampString(newStart)
            if let q = store.requestPlan(f, day: s.day, time: s.time, cinemaName: cinemaName) {
                clashAsk = q
                return
            }
        }
        dismiss()
    }
}
