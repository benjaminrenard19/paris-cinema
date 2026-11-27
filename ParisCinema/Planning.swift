import SwiftUI

// MARK: - No double booking, and films in a row

/// Another OTW film you could see just before or after a plan, at the same cinema.
struct RowSuggestion: Identifiable {
    var id: String { film.id + "-" + time }
    let film: Film
    let time: String
    let version: String?
    let before: Bool
}

extension Store {
    /// Minutes of adverts and trailers between the session time and the film:
    /// about 20 at UGC, Pathé and Gaumont, 15 at mk2, 10 at the independents (20 when the cinema isn't known).
    static func trailerMinutes(_ cinema: String?) -> Int {
        guard let n = cinema?.folded, !n.isEmpty else { return 20 }
        if n.hasPrefix("ugc") || n.hasPrefix("pathe") || n.hasPrefix("gaumont") { return 20 }
        if n.hasPrefix("mk2") { return 15 }
        return 10
    }

    /// When you should be walking out: session time, then trailers, then the film. Nil when the running time isn't known.
    func exitTime(_ id: String, day: String, time: String, cinema: String?) -> Date? {
        guard let minutes = index[id]?.duration, let start = D.stamp(day: day, time: time) else { return nil }
        return start.addingTimeInterval(TimeInterval((minutes + Store.trailerMinutes(cinema)) * 60))
    }

    /// When a film would be over at that time (2 h 10 plus trailers when its running time isn't known).
    func endOf(_ id: String, day: String, time: String, cinema: String? = nil) -> Date? {
        exitTime(id, day: day, time: time, cinema: cinema)
            ?? D.stamp(day: day, time: time)?.addingTimeInterval(TimeInterval((130 + Store.trailerMinutes(cinema)) * 60))
    }

    /// Your other plans that day that would overlap a session of this film by more than 10 minutes.
    func clashes(_ id: String, day: String, time: String, cinema: String? = nil) -> [(Film, Plan)] {
        guard let start = D.stamp(day: day, time: time), let end = endOf(id, day: day, time: time, cinema: cinema) else { return [] }
        return plans.compactMap { k, p -> (Film, Plan)? in
            guard k != id, p.d == day, seen[k] == nil, let f = index[k],
                  let s = D.stamp(day: p.d, time: p.t), let e = endOf(k, day: p.d, time: p.t, cinema: p.cn) else { return nil }
            // Up to 10 minutes of overlap is fine: the next session starts with trailers.
            let grace: TimeInterval = 10 * 60
            return (s.addingTimeInterval(grace) < end && start.addingTimeInterval(grace) < e) ? (f, p) : nil
        }
        .sorted { $0.1.t < $1.1.t }
    }

    /// OTW films (not planned, not seen) showing at the same cinema just after this plan ends,
    /// or ending just before it starts: a double bill without changing cinema.
    func inARow(_ id: String, _ p: Plan) -> [RowSuggestion] {
        guard let start = D.stamp(day: p.d, time: p.t), let end = endOf(id, day: p.d, time: p.t, cinema: p.cn) else { return [] }
        var out: [RowSuggestion] = []
        for f in favouriteFilms where f.id != id && plans[f.id] == nil && seen[f.id] == nil {
            // The session closest to the plan, just after it or just before it
            var best: (gap: TimeInterval, s: RowSuggestion)?
            for s in sessions(f.id, at: p.cn, on: p.d) {
                guard let sStart = D.stamp(day: p.d, time: s.time), let sEnd = endOf(f.id, day: p.d, time: s.time, cinema: p.cn) else { continue }
                let after = sStart >= end.addingTimeInterval(-10 * 60) && sStart <= end.addingTimeInterval(100 * 60)
                let before = sEnd <= start.addingTimeInterval(10 * 60) && sEnd >= start.addingTimeInterval(-100 * 60)
                guard after || before, clashes(f.id, day: p.d, time: s.time, cinema: p.cn).isEmpty else { continue }
                let gap = after ? abs(sStart.timeIntervalSince(end)) : abs(start.timeIntervalSince(sEnd))
                if best == nil || gap < best!.gap {
                    best = (gap, RowSuggestion(film: f, time: s.time, version: s.version, before: !after))
                }
            }
            if let b = best { out.append(b.s) }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Films in OTW (your favourites), whatever their week.
    var favouriteFilms: [Film] { favs.compactMap { index[$0] } }
}

// MARK: - Asking before a double booking

/// A session you chose that overlaps another plan: replace it, keep both, or cancel.
struct ClashQuestion: Identifiable {
    let id = UUID()
    let film: Film
    let day: String
    let time: String
    let cinema: String
    let clashes: [(Film, Plan)]
}

extension Store {
    /// Plans the session, unless it overlaps another plan: then nothing changes yet and the question comes back.
    func requestPlan(_ f: Film, day: String, time: String, cinemaName: String) -> ClashQuestion? {
        let c = clashes(f.id, day: day, time: time, cinema: cinemaName)
        guard !c.isEmpty else {
            planFilm(f, day: day, time: time, cinemaName: cinemaName)
            return nil
        }
        return ClashQuestion(film: f, day: day, time: time, cinema: cinemaName, clashes: c)
    }

    func answer(_ q: ClashQuestion, replace: Bool) {
        if replace { for c in q.clashes { removePlan(c.0.id) } }
        planFilm(q.film, day: q.day, time: q.time, cinemaName: q.cinema)
    }
}

extension View {
    /// Asks before saving a session that overlaps another plan. `done` runs once it is saved.
    func clashQuestion(_ question: Binding<ClashQuestion?>, then done: @escaping () -> Void = {}) -> some View {
        modifier(ClashQuestionAlert(question: question, done: done))
    }
}

private struct ClashQuestionAlert: ViewModifier {
    @Environment(Store.self) private var store
    @Binding var question: ClashQuestion?
    let done: () -> Void

    func body(content: Content) -> some View {
        content.alert(String(localized: "Double booking"),
                      isPresented: Binding(get: { question != nil }, set: { if !$0 { question = nil } }),
                      presenting: question) { q in
            Button(q.clashes.count == 1 ? String(localized: "Replace \(q.clashes[0].0.title)") : String(localized: "Replace the other plans"),
                   role: .destructive) {
                store.answer(q, replace: true)
                done()
            }
            Button("Keep both") {
                store.answer(q, replace: false)
                done()
            }
            Button("Cancel", role: .cancel) {}
        } message: { q in
            Text(String(localized: "\(q.film.title) at \(q.time) overlaps \(q.clashes[0].0.title) at \(q.clashes[0].1.t), already in your week."))
        }
    }
}

/// "Out around 19:11 · 1h46 film + about 20 min of trailers" for a chosen session, confirmed or not.
struct ExitTimeLine: View {
    @Environment(Store.self) private var store
    let id: String
    let day: String
    let time: String
    let cinema: String?
    var compact = false

    var body: some View {
        if let out = store.exitTime(id, day: day, time: time, cinema: cinema) {
            let hm = D.stampString(out).time
            Label {
                if compact {
                    Text(String(localized: "Out around \(hm)"))
                } else {
                    Text(String(localized: "Out around \(hm)")).fontWeight(.semibold)
                    + Text(" · " + String(localized: "\(store.index[id]?.durationText ?? "") film + about \(Store.trailerMinutes(cinema)) min of trailers"))
                }
            } icon: {
                Image(systemName: "door.left.hand.open")
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Overlaps with …" under a plan or a session that clashes with another plan.
struct ClashWarning: View {
    let clashes: [(Film, Plan)]

    var body: some View {
        if let c = clashes.first {
            Label {
                Text(clashes.count == 1
                     ? String(localized: "Overlaps with \(c.0.title) at \(c.1.t)")
                     : String(localized: "Overlaps with \(c.0.title) at \(c.1.t) and \(clashes.count - 1) more"))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }
}

/// Under a plan in My week: OTW films at the same cinema just before or after, to watch in a row.
struct InARowRow: View {
    @Environment(Store.self) private var store
    let film: Film
    let plan: Plan

    var body: some View {
        let list = store.inARow(film.id, plan)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("🍿 Make it a double, same cinema")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list) { s in
                            Button {
                                store.planFilm(s.film, day: plan.d, time: s.time, cinemaName: plan.cn)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.film.title).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(s.before ? String(localized: "Before · \(s.time)") : String(localized: "After · \(s.time)"))
                                        .font(.caption2.monospacedDigit())
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: 170, alignment: .leading)
                                .background(Color.theme.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(Color.theme)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
