import SwiftUI

// MARK: - Films since 2015
// data/history.json (scripts/history.py): every film released in France from 2015 to 2025.
// Used for search, imports, your watched films and their pages. The Films page stays on this year.

struct HistoryFile: Decodable {
    var films: [Film]
}

extension Store {
    static let historyRemote = URL(string: "https://raw.githubusercontent.com/benjaminrenard19/paris-cinema/main/data/history.json")!
    static var historyOn: Bool { UserDefaults.standard.object(forKey: "historyOn") as? Bool ?? true }

    var historyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json")
    }

    /// An older film, from the history list rather than this year's films.
    func isOld(_ id: String) -> Bool { !currentIds.contains(id) && historyIds.contains(id) }

    /// The copy on this iPhone at launch, then a fresh one from GitHub once a week.
    func loadHistory() async {
        guard Store.historyOn else { return }
        let url = historyURL
        if history.isEmpty, let data = try? Data(contentsOf: url),
           let file = await Task.detached(priority: .utility, operation: { try? JSONDecoder().decode(HistoryFile.self, from: data) }).value {
            setHistory(file.films)
        }
        let last = UserDefaults.standard.double(forKey: "historyCheckedAt")
        guard history.isEmpty || Date().timeIntervalSince1970 - last > 7 * 86_400 else { return }
        guard let result = try? await URLSession.shared.data(from: Store.historyRemote) else { return }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let file = await Task.detached(priority: .utility, operation: { try? JSONDecoder().decode(HistoryFile.self, from: data) }).value,
              !file.films.isEmpty else { return }
        try? data.write(to: url, options: .atomic)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "historyCheckedAt")
        setHistory(file.films)
    }

    func dropHistory() {
        setHistory([])
        try? FileManager.default.removeItem(at: historyURL)
        UserDefaults.standard.removeObject(forKey: "historyCheckedAt")
    }

    /// Older films matching a search, newest first (this year's films are searched separately).
    func searchHistory(_ q: String) -> [Film] {
        let words = q.folded.split(separator: " ").map(String.init)
        guard !words.isEmpty, !history.isEmpty else { return [] }
        return history.filter { f in
            guard !currentIds.contains(f.id) else { return false }
            let t = f.searchText
            return words.allSatisfy { t.contains($0) }
        }.sorted { $0.date > $1.date }
    }

}

/// Settings › Film history.
struct HistorySettings: View {
    @Environment(Store.self) private var store
    @AppStorage("historyOn") private var historyOn = true
    @AppStorage("importCinema") private var importCinema = ""

    var body: some View {
        Section {
            Toggle("Films since 2015", isOn: $historyOn)
                .onChange(of: historyOn) { _, on in
                    if on { Task { await store.loadHistory() } } else { store.dropHistory() }
                }
            if historyOn {
                LabeledContent("Older films", value: store.history.isEmpty ? String(localized: "Downloading…") : "\(store.history.count)")
            }
            Picker("Cinema for imported films", selection: $importCinema) {
                Text("None").tag("")
                ForEach(store.allCinemas.map(\.name).sorted { a, b in
                    let ma = store.isPreferred(a), mb = store.isPreferred(b)
                    return ma != mb ? ma : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                }, id: \.self) { n in Text(n).tag(n) }
            }
        } header: {
            Text("Film history")
        } footer: {
            Text("Every film released in France from 2015 to 2025, with posters and ratings. They're used for search, imports and your watched films. The Films page stays on this year. Imported films get no cinema unless you pick one here; you can set it on each film's page.")
        }
    }
}

/// On a watched film's page: where you saw it.
struct SeenCinemaPicker: View {
    @Environment(Store.self) private var store
    let id: String

    var body: some View {
        Picker("Cinema", selection: Binding(get: { store.seen[id]?.cn ?? "" }, set: { store.setSeenCinema(id, $0) })) {
            Text("Not set").tag("")
            let current = store.seen[id]?.cn ?? ""
            if !current.isEmpty && store.cinema(named: current) == nil { Text(current).tag(current) }
            ForEach(store.allCinemas.map(\.name).sorted { a, b in
                let ma = store.isPreferred(a), mb = store.isPreferred(b)
                return ma != mb ? ma : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }, id: \.self) { n in Text(n).tag(n) }
        }
    }
}
