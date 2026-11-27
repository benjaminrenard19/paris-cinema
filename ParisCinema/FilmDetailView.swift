import SwiftUI
import EventKit
import EventKitUI

struct FilmDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let id: String

    @State private var watchedOn = Date()
    @State private var calendarEvent: CalendarDraft?
    @State private var alt: ArtworkHit?
    @State private var viewer: Film?
    @State private var showCalendar = false
    @State private var inviting = false

    @State private var clashAsk: ClashQuestion?

    var body: some View {
        if let f = store.index[id] {
            content(f)
        } else {
            ContentUnavailableView("Film not found", systemImage: "film", description: Text("It may have moved to another week. Update your films and try again."))
        }
    }

    @ViewBuilder
    private func content(_ f: Film) -> some View {
        List {
            Section { header(f) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            Section {
                ratingsCard(f)
            } header: {
                Text("Ratings")
            } footer: {
                Text(f.press == nil && f.spect == nil
                     ? String(localized: "No ratings on AlloCiné yet. They usually appear in the first days of release.")
                     : String(localized: "AlloCiné ratings out of 5: critics from press reviews, audience from spectators."))
            }

            Section("Your film") {
                Button { store.toggleFav(f) } label: {
                    Label(store.isFav(f.id) ? String(localized: "In your OTW (One To Watch)") : String(localized: "Add to OTW (One To Watch)"),
                          systemImage: store.isFav(f.id) ? "popcorn.fill" : "popcorn")
                }
                ratingRow(f)
                if store.seen[f.id] != nil {
                    CompanionPicker(selected: Binding(get: { store.seen[f.id]?.w ?? [] }, set: { store.setCompanions(f.id, $0) }))
                    SeenCinemaPicker(id: f.id)
                    DatePicker("Watched on", selection: seenDate(f), in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, D.paris)
                    Button("Remove from watched", role: .destructive) { store.removeSeen(f.id) }
                } else {
                    DatePicker("Watched on", selection: $watchedOn, in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, D.paris)
                    Button { store.setSeen(f, rating: 0, on: D.str(watchedOn)) } label: {
                        Label("Mark as watched", systemImage: "checkmark.circle")
                    }
                }
            }

            if store.isFav(f.id), store.seen[f.id] == nil, let p = store.plans[f.id] {
                planSection(f, p)
            }

            if store.isOld(f.id) {
                Section {
                    Label("Not in cinemas now. Released \(D.fmt(f.date, "EEEE d MMMM yyyy")).", systemImage: "film.stack")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else if store.seen[f.id] == nil {
                let showing = !store.cinemaListing(f.id).isEmpty
                if showing || !store.isFav(f.id) {
                    Section {
                        if !store.isFav(f.id) {
                            Button { store.toggleFav(f) } label: {
                                Label("Add it to One To Watch (OTW) to see when the sessions are.", systemImage: "popcorn")
                            }
                        }
                        if showing { FilmCinemasList(film: f, ask: $clashAsk) }
                    } header: {
                        if showing { Text("These cinemas have your wanted movie!") }
                    } footer: {
                        if showing { Text("Your cinemas in gold. Tap a time to plan it.") }
                    }
                }
            }

            if let syn = f.story, !syn.isEmpty {
                Section("Story") { Text(syn) }
            }

            Section("Credits") {
                row("Director", f.dir)
                row("Cast", f.cast)
                if !f.isRepertory && !store.isOld(f.id) { row("Producers", f.prod ?? String(localized: "Not listed yet. The Tuesday update adds them.")) }
                row("Genres", f.genreText)
                row("Origin", f.originText)
                if let n = f.note, !n.isEmpty { row("Note", n) }
            }

            Section {
                if let u = f.trailerURL {
                    Link(destination: u) {
                        Label(f.isFrench || f.category == .E ? String(localized: "Trailer") : String(localized: "Trailer in original version, French subtitles"), systemImage: "play.rectangle.fill")
                    }
                }
                if let u = f.allocineURL { Link(destination: u) { Label("Poster and reviews on AlloCiné", systemImage: "photo.on.rectangle") } }
                if let u = f.showtimesSearchURL { Link(destination: u) { Label("All showtimes in Paris", systemImage: "clock") } }
            } header: {
                Text("Watch")
            } footer: {
                Text(String(localized: "Usually shown in \(NSLocalizedString(f.venueType, comment: "Cinema type").lowercased()) cinemas."))
            }
        }
        .navigationTitle(f.title)
        .navigationBarTitleDisplayMode(.inline)
        .clashQuestion($clashAsk)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFav(f) } label: {
                    Image(systemName: store.isFav(f.id) ? "popcorn.fill" : "popcorn")
                }
                .accessibilityLabel(store.isFav(f.id) ? String(localized: "Remove from OTW") : String(localized: "Add to OTW (One To Watch)"))
            }
        }
        .fullScreenCover(item: $viewer) { film in
            PosterViewer(film: film, posters: posters(film), minutes: alt?.minutes)
        }
        .task(id: id) {
            if let film = store.index[id], film.poster == nil || film.duration == nil {
                alt = await Artwork.shared.lookup(film)
            }
        }
        .sheet(isPresented: $inviting) { InviteSheet(filmId: id).environment(store) }
        .sheet(item: $calendarEvent) { draft in
            EventEditor(draft: draft) { calendarEvent = nil }
                .ignoresSafeArea()
        }
    }

    private func header(_ f: Film) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PosterTile(title: f.title, cat: f.category, width: 110, url: f.poster ?? alt?.poster)
                .onTapGesture { viewer = f }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Show the poster full screen")
                .overlay(alignment: .topTrailing) {
                    Button { store.toggleFav(f) } label: {
                        Image(systemName: store.isFav(f.id) ? "popcorn.fill" : "popcorn")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(store.isFav(f.id) ? Color(hex: 0xFFD23F) : Color.white)
                            .padding(7)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .padding(5)
                    .accessibilityLabel(store.isFav(f.id) ? String(localized: "Remove from favourites") : String(localized: "Add to favourites"))
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CatBadge(cat: f.category)
                    if !f.isRepertory { Text(f.releaseSize.label).font(.caption).foregroundStyle(.secondary) }
                }
                Text(f.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let o = f.orig, !o.isEmpty {
                    Text(f.category == .R ? o : String(localized: "Original: \(o)")).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(f.isRepertory ? String(localized: "Showing again in Paris") : String(localized: "In cinemas from \(D.fmt(f.date, "EEEE d MMMM yyyy"))"))
                    .font(.subheadline)
                if let line = facts(f) {
                    Text(line).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                Text("Tap the poster for more").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }

    private func ratingsCard(_ f: Film) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ratingTile("Critics", "Press", f.press)
            Divider()
            ratingTile("Audience", "Spectators", f.spect)
            Divider()
            ratingTile("Average", "Both", f.average)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func ratingTile(_ title: String, _ subtitle: String, _ value: Double?) -> some View {
        VStack(spacing: 4) {
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
            Text(value.map { String(format: "%.1f", $0) } ?? "–")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .monospacedDigit()
            RatingStars(value: value ?? 0, size: 11)
                .opacity(value == nil ? 0.35 : 1)
            Text(LocalizedStringKey(subtitle)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { String(localized: "\(NSLocalizedString(title, comment: "")): \(String(format: "%.1f", $0)) out of 5") }
                            ?? String(localized: "\(NSLocalizedString(title, comment: "")): no rating yet"))
    }

    private func ratingRow(_ f: Film) -> some View {
        HStack {
            Text("Your rating")
            Spacer()
            HalfStarPicker(value: Binding(get: { store.seen[f.id]?.value ?? 0 },
                                          set: { store.setSeen(f, value: $0, on: store.seen[f.id]?.d ?? D.str(watchedOn)) }),
                           size: 22)
        }
    }

    // MARK: Plan to watch: cinema, then day, then time

    @ViewBuilder
    private func planSection(_ f: Film, _ p: Plan) -> some View {
        let byDay = store.showtimes(for: f.id, at: p.cn)
        Section {
            NavigationLink {
                CinemaPickerView(film: f, selected: planCinema(f, p))
            } label: {
                LabeledContent {
                    HStack(spacing: 4) {
                        if store.isPreferred(p.cn) { Image(systemName: "star.fill").font(.caption).foregroundStyle(Color(hex: 0xE0A800)) }
                        Text(p.cn)
                    }
                } label: {
                    step(1, "Cinema")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                step(2, "Day")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(nextDays, id: \.self) { day in
                            Button { setDay(f, p, day) } label: {
                                dayChip(day, selected: day == p.d, available: byDay[day] != nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(byDay.isEmpty
                     ? String(localized: "No showtimes known yet for this cinema. Pick any day, or check the calendar.")
                     : String(localized: "A green dot means this cinema shows the film that day."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            DisclosureGroup("Calendar", isExpanded: $showCalendar) {
                DatePicker("Day", selection: planDay(f, p), in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, D.paris)
            }

            VStack(alignment: .leading, spacing: 10) {
                step(3, "Time")
                let list = store.sessions(f.id, at: p.cn, on: p.d)
                if !list.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(list) { s in
                            Button { setTime(f, p, s.time) } label: {
                                TimeChip(time: s.time, selected: s.time == p.t, version: s.version,
                                         clash: !store.clashes(f.id, day: p.d, time: s.time).isEmpty)
                            }
                                .buttonStyle(.plain)
                        }
                    }
                } else {
                    DatePicker("Time", selection: planTime(f, p), displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, D.paris)
                }
            }
            .padding(.vertical, 4)

            if p.ok != true {
                Button { store.confirmPlan(f.id) } label: {
                    Label("Confirm this plan", systemImage: "checkmark.circle")
                }
            }
            Button { calendarEvent = draft(f, p) } label: {
                Label("Add to Apple Calendar", systemImage: "calendar.badge.plus")
            }
            if let u = googleURL(f, p) {
                Link(destination: u) { Label("Add to Google Calendar", systemImage: "calendar") }
            }
            if let c = store.cinema(named: p.cn), let u = c.directionsURL {
                Link(destination: u) { Label("Directions to \(c.name)", systemImage: "arrow.triangle.turn.up.right.diamond") }
            }
            CompanionPicker(selected: Binding(get: { store.plans[f.id]?.w ?? [] }, set: { store.setPlanCompanions(f.id, $0) }),
                            title: "Going with")
            Button { inviting = true } label: {
                Label("Invite someone", systemImage: "person.2.wave.2")
            }
        } header: {
            Text("Plan to watch")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                ClashWarning(clashes: store.clashes(f.id, day: p.d, time: p.t))
                Text("\(D.fmt(p.d, "EEEE d MMMM")) at \(p.t), \(p.cn).")
                if p.ok == true {
                    Text(CalendarSync.shared.enabled
                         ? String(localized: "Saved to your calendar automatically. After the film you'll get a notification to say how it was.")
                         : String(localized: "After the film you'll get a notification to say how it was, or to pick another day."))
                } else {
                    Text("Provisional plan. Confirm it, or change the cinema, day or time, to get a notification after the film.")
                }
                if let when = D.when(store.showtimes[f.id]?.updatedAt) { Text("Showtimes checked \(when).") }
            }
        }

        let today = store.todayScreenings(f.id)
        if !today.rows.isEmpty {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(today.rows, id: \.cinema) { row in
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.cinema).font(.subheadline.weight(.semibold)).lineLimit(2)
                                if let c = store.cinema(named: row.cinema) {
                                    Text(c.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(width: 120, alignment: .leading)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(row.sessions) { s in
                                        Button {
                                            store.updatePlan(f.id, Plan(d: D.today, t: s.time, cn: row.cinema,
                                                                        ca: store.cinema(named: row.cinema)?.address,
                                                                        title: f.title, fd: f.date))
                                        } label: {
                                            TimeChip(time: s.time, selected: p.d == D.today && p.t == s.time && p.cn == row.cinema, version: s.version)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(today.mine ? String(localized: "Today at your cinemas") : String(localized: "Today in Paris"))
            } footer: {
                Text(today.mine ? String(localized: "Tap a time to plan it.") : String(localized: "Star your cinemas in the Cinemas tab to see only those here. Tap a time to plan it."))
            }
        }
    }

    private var nextDays: [String] { (0..<14).map { D.addDays(D.today, $0) } }

    private func step(_ n: Int, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.theme, in: Circle())
            Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
        }
    }

    private func dayChip(_ day: String, selected: Bool, available: Bool) -> some View {
        VStack(spacing: 3) {
            Text(day == D.today ? String(localized: "Today") : D.fmt(day, "EEE")).font(.caption2)
            Text(D.fmt(day, "d")).font(.headline)
            Circle().fill(available ? Color.green : Color.clear).frame(width: 6, height: 6)
        }
        .frame(width: 50, height: 62)
        .background(selected ? Color.theme : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    private func timeChip(_ t: String, selected: Bool) -> some View {
        Text(t)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .frame(minWidth: 58)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(selected ? Color.theme : Color.theme.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(selected ? Color.white : Color.theme)
    }

    private func setDay(_ f: Film, _ p: Plan, _ day: String) {
        var np = store.plans[f.id] ?? p
        np.d = day
        let all = store.sessions(f.id, at: np.cn, on: day)
        if !all.isEmpty && !all.contains(where: { $0.time == np.t }) {
            let pool = store.preferredPool(all, for: f.id).map { $0.time }
            np.t = Habits.closest(pool, to: store.habits.usualTime ?? "20:00") ?? pool[0]
        }
        store.updatePlan(f.id, np)
    }

    private func setTime(_ f: Film, _ p: Plan, _ t: String) {
        var np = store.plans[f.id] ?? p
        np.t = t
        store.updatePlan(f.id, np)
    }

    private func planDay(_ f: Film, _ p: Plan) -> Binding<Date> {
        Binding(get: { D.date(p.d) ?? Date() }, set: { setDay(f, p, D.str($0)) })
    }

    private func planTime(_ f: Film, _ p: Plan) -> Binding<Date> {
        Binding(get: { D.stamp(day: p.d, time: p.t) ?? Date() }, set: { setTime(f, p, D.stampString($0).time) })
    }

    private func facts(_ f: Film) -> String? {
        var parts: [String] = []
        if let d = f.durationText ?? alt?.minutes.map({ $0 >= 60 ? "\($0 / 60)h \(String(format: "%02d", $0 % 60))" : "\($0) min" }) { parts.append(d) }
        if let g = f.genreText, !g.isEmpty { parts.append(g.components(separatedBy: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func posters(_ f: Film) -> [String] {
        var out: [String] = []
        for u in [f.poster, alt?.poster].compactMap({ $0 }) where !out.contains(u) { out.append(u) }
        return out
    }

    private func seenDate(_ f: Film) -> Binding<Date> {
        Binding(
            get: { store.seen[f.id].flatMap { D.date($0.d) } ?? Date() },
            set: { store.setSeenDate(f.id, D.str($0)) })
    }

    private func planDate(_ f: Film, _ p: Plan) -> Binding<Date> {
        Binding(
            get: { D.stamp(day: p.d, time: p.t) ?? Date() },
            set: { d in
                let s = D.stampString(d)
                var np = store.plans[f.id] ?? p
                np.d = s.day; np.t = s.time
                store.updatePlan(f.id, np)
            })
    }

    private func planCinema(_ f: Film, _ p: Plan) -> Binding<String> {
        Binding(
            get: { p.cn },
            set: { n in
                var np = store.plans[f.id] ?? p
                np.cn = n
                np.ca = store.cinema(named: n)?.address ?? np.ca
                store.updatePlan(f.id, np)
            })
    }

    private func address(_ p: Plan) -> String {
        let a = p.ca ?? store.cinema(named: p.cn)?.address ?? ""
        return a.isEmpty ? p.cn + ", Paris" : p.cn + ", " + a
    }

    private func notes(_ f: Film) -> String {
        var lines: [String] = []
        if let d = f.dir, !d.isEmpty { lines.append(String(localized: "Directed by \(d)")) }
        if let s = f.story, !s.isEmpty { lines.append(s) }
        if let u = f.showtimesSearchURL { lines.append(String(localized: "Showtimes: \(u.absoluteString)")) }
        return lines.joined(separator: "\n\n")
    }

    private func draft(_ f: Film, _ p: Plan) -> CalendarDraft {
        CalendarDraft(title: String(localized: "Cinema: \(f.title)"),
                      start: D.stamp(day: p.d, time: p.t) ?? Date(),
                      minutes: 150,
                      location: address(p),
                      notes: notes(f))
    }

    private func googleURL(_ f: Film, _ p: Plan) -> URL? {
        guard let start = D.stamp(day: p.d, time: p.t) else { return nil }
        let end = start.addingTimeInterval(150 * 60)
        return URL.with("https://calendar.google.com/calendar/render", [
            "action": "TEMPLATE",
            "text": String(localized: "Cinema: \(f.title)"),
            "dates": D.gcal(start) + "/" + D.gcal(end),
            "ctz": "Europe/Paris",
            "location": address(p),
            "details": notes(f),
        ])
    }

    private func row(_ label: String, _ value: String?) -> some View {
        Group {
            if let v = value, !v.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
                    Text(v)
                }
            }
        }
    }
}

// MARK: - Apple Calendar (system editor, no calendar permission needed on iOS 17+)

struct CalendarDraft: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let minutes: Int
    let location: String
    let notes: String
}

struct EventEditor: UIViewControllerRepresentable {
    let draft: CalendarDraft
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.start.addingTimeInterval(TimeInterval(draft.minutes * 60))
        event.timeZone = D.paris
        event.location = draft.location
        event.notes = draft.notes
        event.addAlarm(EKAlarm(relativeOffset: -2 * 3600))
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
