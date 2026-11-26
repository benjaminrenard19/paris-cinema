import SwiftUI
import EventKit
import EventKitUI

struct FilmDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let id: String

    @State private var watchedOn = Date()
    @State private var calendarEvent: CalendarDraft?

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

            Section("Your film") {
                Button { store.toggleFav(f) } label: {
                    Label(store.isFav(f.id) ? "In your favourites" : "Add to favourites",
                          systemImage: store.isFav(f.id) ? "star.fill" : "star")
                }
                ratingRow(f)
                if store.seen[f.id] != nil {
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

            if let syn = f.syn, !syn.isEmpty {
                Section("Story") { Text(syn) }
            }

            Section("Credits") {
                row("Director", f.dir)
                row("Cast", f.cast)
                row("Producers", f.prod ?? "Not listed yet. The Tuesday update adds them.")
                row("Genres", f.genre)
                row("Origin", f.origin)
                if let n = f.note, !n.isEmpty { row("Note", n) }
            }

            Section {
                if let u = f.trailerURL {
                    Link(destination: u) {
                        Label(f.isFrench || f.category == .E ? "Trailer" : "Trailer in original version, French subtitles", systemImage: "play.rectangle.fill")
                    }
                }
                if let u = f.allocineURL { Link(destination: u) { Label("Poster and reviews on AlloCiné", systemImage: "photo.on.rectangle") } }
                if let u = f.showtimesSearchURL { Link(destination: u) { Label("All showtimes in Paris", systemImage: "clock") } }
            } header: {
                Text("Watch")
            } footer: {
                Text("Usually shown in \(f.venueType.lowercased()) cinemas.")
            }
        }
        .navigationTitle(f.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFav(f) } label: {
                    Image(systemName: store.isFav(f.id) ? "star.fill" : "star")
                }
                .accessibilityLabel(store.isFav(f.id) ? "Remove from favourites" : "Add to favourites")
            }
        }
        .sheet(item: $calendarEvent) { draft in
            EventEditor(draft: draft) { calendarEvent = nil }
                .ignoresSafeArea()
        }
    }

    private func header(_ f: Film) -> some View {
        HStack(alignment: .top, spacing: 16) {
            PosterTile(title: f.title, cat: f.category, width: 110, url: f.poster)
                .overlay(alignment: .topTrailing) {
                    Button { store.toggleFav(f) } label: {
                        Image(systemName: store.isFav(f.id) ? "star.fill" : "star")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(store.isFav(f.id) ? Color(hex: 0xFFD23F) : Color.white)
                            .padding(7)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .padding(5)
                    .accessibilityLabel(store.isFav(f.id) ? "Remove from favourites" : "Add to favourites")
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CatBadge(cat: f.category)
                    Text(f.releaseSize.label).font(.caption).foregroundStyle(.secondary)
                }
                Text(f.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let o = f.orig, !o.isEmpty {
                    Text(f.category == .R ? o : "Original: \(o)").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("In cinemas from \(D.fmt(f.date, "EEEE d MMMM yyyy"))")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
    }

    private func ratingRow(_ f: Film) -> some View {
        let current = store.seen[f.id]?.r ?? 0
        return HStack {
            Text("Your rating")
            Spacer()
            ForEach(1...5, id: \.self) { i in
                Button {
                    let day = store.seen[f.id]?.d ?? D.str(watchedOn)
                    store.setSeen(f, rating: current == i ? 0 : i, on: day)
                } label: {
                    Image(systemName: i <= current ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(i <= current ? Color(hex: 0xE0A800) : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
            }
        }
    }

    // MARK: Plan to watch

    @ViewBuilder
    private func planSection(_ f: Film, _ p: Plan) -> some View {
        let showings = store.showings(for: f.id)
        Section {
            if !showings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(showings.prefix(20)) { s in
                            let on = s.day == p.d && s.time == p.t && s.cinema == p.cn
                            Button {
                                store.updatePlan(f.id, Plan(d: s.day, t: s.time, cn: s.cinema, ca: s.address, title: f.title, fd: f.date))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(D.fmt(s.day, "EEE d")) · \(s.time)").font(.subheadline.weight(.semibold))
                                    Text(s.cinema).font(.caption2).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(on ? Color.accentColor : Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(on ? Color.white : Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            DatePicker("Day and time", selection: planDate(f, p), in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .environment(\.timeZone, D.paris)

            NavigationLink {
                CinemaPickerView(film: f, selected: planCinema(f, p))
            } label: {
                LabeledContent("Cinema") {
                    HStack(spacing: 4) {
                        if store.isPreferred(p.cn) { Image(systemName: "star.fill").font(.caption).foregroundStyle(Color(hex: 0xE0A800)) }
                        Text(p.cn)
                    }
                }
            }

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
        } header: {
            Text("Plan to watch")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if p.ok == true {
                    Text("After the film you'll get a notification to say how it was, or to pick another day.")
                } else {
                    Text("Provisional plan. Confirm it, or change the day, time or cinema, to get a notification after the film.")
                }
                if showings.isEmpty {
                    Text("Real showtimes appear here after the Tuesday update, once cinemas publish the week.")
                } else if let when = D.when(store.showtimes[f.id]?.updatedAt) {
                    Text("Showtimes checked \(when). Tap one to plan it.")
                }
            }
        }
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
        if let d = f.dir, !d.isEmpty { lines.append("Directed by " + d) }
        if let s = f.syn, !s.isEmpty { lines.append(s) }
        if let u = f.showtimesSearchURL { lines.append("Showtimes: " + u.absoluteString) }
        return lines.joined(separator: "\n\n")
    }

    private func draft(_ f: Film, _ p: Plan) -> CalendarDraft {
        CalendarDraft(title: "Cinema: " + f.title,
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
            "text": "Cinema: " + f.title,
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
                    Text(label).font(.caption).foregroundStyle(.secondary)
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
