import SwiftUI

/// One cinema showing a film, with its next day of sessions.
struct CinemaListingRow: Identifiable {
    var id: String { cinema }
    let cinema: String
    let day: String
    let sessions: [Session]
    let mine: Bool
}

extension Store {
    /// Every cinema showing a film from today on, with its next sessions: your cinemas first, then the soonest.
    func cinemaListing(_ id: String) -> [CinemaListingRow] {
        guard let list = showtimes[id]?.cinemas else { return [] }
        var names: [String] = []
        for c in list {
            if let n = c.name, !n.isEmpty, !names.contains(where: { sameCinema($0, n) }) { names.append(n) }
        }
        let rows: [CinemaListingRow] = names.compactMap { n in
            guard let next = nextSessions(id, at: n) else { return nil }
            return CinemaListingRow(cinema: n, day: next.day, sessions: next.sessions, mine: myCinemas.contains { sameCinema($0, n) })
        }
        return rows.sorted { a, b in
            if a.mine != b.mine { return a.mine }
            if a.day != b.day { return a.day < b.day }
            return (a.sessions.first?.time ?? "") < (b.sessions.first?.time ?? "")
        }
    }
}

/// The cinemas showing a film, your cinemas in bold gold. Tap a time to plan it.
/// Compact: your cinemas (or the first one showing it) until "Show all".
struct FilmCinemasList: View {
    @Environment(Store.self) private var store
    let film: Film
    var compact = true
    @Binding var ask: ClashQuestion?
    @State private var showAll = false

    var body: some View {
        let rows = store.cinemaListing(film.id)
        let mine = rows.filter { $0.mine }
        let shown = (showAll || !compact) ? rows : (mine.isEmpty ? Array(rows.prefix(1)) : mine)
        ForEach(shown) { r in row(r) }
        if compact && rows.count > (mine.isEmpty ? 1 : mine.count) {
            Button(showAll ? String(localized: "Show fewer") : String(localized: "Show all \(rows.count) cinemas")) {
                withAnimation { showAll.toggle() }
            }
        }
    }

    private func row(_ r: CinemaListingRow) -> some View {
        let plan = store.plans[film.id]
        let gold = Color(hex: 0xE0A800)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if r.mine { Image(systemName: "star.fill").font(.caption2).foregroundStyle(gold) }
                Text(r.cinema)
                    .font(.subheadline.weight(r.mine ? .bold : .semibold))
                    .foregroundStyle(r.mine ? gold : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(dayLabel(r.day)).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(r.sessions) { s in
                        Button {
                            ask = store.requestPlan(film, day: r.day, time: s.time, cinemaName: r.cinema)
                        } label: {
                            TimeChip(time: s.time, selected: plan?.d == r.day && plan?.t == s.time && plan?.cn == r.cinema, version: s.version,
                                     clash: !store.clashes(film.id, day: r.day, time: s.time, cinema: r.cinema).isEmpty)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func dayLabel(_ day: String) -> String {
        if day == D.today { return String(localized: "Today") }
        if day == D.addDays(D.today, 1) { return String(localized: "Tomorrow") }
        return D.fmt(day, "EEE d MMM")
    }
}

/// Opened by swiping a film on the Films page.
struct FilmCinemasSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let film: Film
    @State private var clashAsk: ClashQuestion?

    var body: some View {
        NavigationStack {
            List {
                if store.cinemaListing(film.id).isEmpty {
                    ContentUnavailableView("No sessions known yet", systemImage: "clock",
                                           description: Text("Pull down on the Films page to get the latest showtimes."))
                } else {
                    Section {
                        FilmCinemasList(film: film, compact: false, ask: $clashAsk)
                    } header: {
                        Text("These cinemas have your wanted movie!")
                    } footer: {
                        Text("Tap a time to plan it.")
                    }
                }
            }
            .navigationTitle(film.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .clashQuestion($clashAsk)
        }
    }
}
