import Foundation

/// When and where you usually go to the cinema, learnt from the films you watched (with the
/// cinema and session of your plan) and from your confirmed plans. The more you use the app,
/// the better its suggestions.
struct Habits {
    /// Cinemas you go to, most visited first.
    var cinemas: [String] = []
    /// Weekdays you go (1 = Sunday … 7 = Saturday), most frequent first.
    var weekdays: [Int] = []
    /// The time you usually go, "HH:mm".
    var usualTime: String?
    /// How many outings this is based on.
    var outings = 0

    var knowsSomething: Bool { !cinemas.isEmpty || !weekdays.isEmpty || usualTime != nil }

    /// The next day you usually go, on or after `start` (the next Saturday while it's not known).
    func nextUsualDay(from start: String) -> String {
        guard let wd = weekdays.first else { return D.saturdayAfter(start) }
        return D.addDays(start, (wd - D.weekday(start) + 7) % 7)
    }

    /// The session nearest to a time ("20:15"), or nil if there are none.
    static func closest(_ times: [String], to target: String) -> String? {
        guard !times.isEmpty else { return nil }
        let goal = minutes(target)
        return times.min { abs(minutes($0) - goal) < abs(minutes($1) - goal) }
    }

    static func minutes(_ t: String) -> Int {
        (Int(t.prefix(2)) ?? 0) * 60 + (Int(t.suffix(2)) ?? 0)
    }

    /// "You usually go on Saturday around 20:00, most often to UGC Ciné Cité Les Halles."
    var summary: String? {
        let day = weekdays.first.map { D.weekdayName($0) }
        let cinema = cinemas.first
        switch (day, usualTime, cinema) {
        case (let d?, let t?, let c?): return String(localized: "You usually go on \(d) around \(t), most often to \(c).")
        case (let d?, let t?, .none): return String(localized: "You usually go on \(d) around \(t).")
        case (let d?, .none, let c?): return String(localized: "You usually go on \(d), most often to \(c).")
        case (.none, let t?, let c?): return String(localized: "You usually go around \(t), most often to \(c).")
        case (.none, .none, let c?): return String(localized: "You go most often to \(c).")
        default: return nil
        }
    }
}

extension Store {
    var habits: Habits {
        var cinemaScore: [String: Double] = [:]
        var daysScore: [Int: Double] = [:]
        var times: [String] = []
        var outings = 0
        let since = D.addDays(D.today, -730)
        for s in seen.values where s.d >= since {
            outings += 1
            let fromPlan = s.cn != nil || s.tm != nil
            daysScore[D.weekday(s.d), default: 0] += fromPlan ? 2 : 1
            if let c = s.cn, !c.isEmpty { cinemaScore[c, default: 0] += 2 }
            if let t = s.tm, t.count == 5 { times.append(t) }
        }
        for p in plans.values where p.ok == true {
            cinemaScore[p.cn, default: 0] += 1
            daysScore[D.weekday(p.d), default: 0] += 1
            if p.t.count == 5 { times.append(p.t) }
        }
        var h = Habits()
        h.outings = outings
        h.cinemas = cinemaScore.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.map { $0.key }
        if daysScore.values.reduce(0, +) >= 4 {
            h.weekdays = daysScore.sorted { $0.value > $1.value }.map { $0.key }
        }
        if times.count >= 2 {
            let sorted = times.sorted()
            h.usualTime = sorted[sorted.count / 2]
        }
        return h
    }
}
