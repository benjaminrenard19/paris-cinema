import Foundation

/// A poster found in Apple's iTunes catalogue (no account or key needed).
struct ArtworkHit: Identifiable, Hashable, Codable {
    var id: String { poster }
    let title: String
    let year: String
    let poster: String
    let minutes: Int?
}

/// Looks up posters (and running times) on iTunes when AlloCiné has none,
/// or to offer a second poster. Results are remembered on the phone.
@MainActor
final class Artwork {
    static let shared = Artwork()
    private var cache: [String: ArtworkHit] = [:]
    private var misses: Set<String> = []
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("artwork.json")
    }

    init() {
        if let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode([String: ArtworkHit].self, from: d) { cache = c }
    }

    /// Search by any title, for films added by hand.
    func search(_ term: String) async -> [ArtworkHit] {
        guard let url = URL.with("https://itunes.apple.com/search",
                                 ["term": term, "country": "fr", "media": "movie", "entity": "movie", "limit": "15"]) else { return [] }
        guard let reply = try? await URLSession.shared.data(from: url),
              let res = try? JSONDecoder().decode(ITunesResults.self, from: reply.0) else { return [] }
        return res.results.compactMap { r in
            guard let art = r.artworkUrl100, let name = r.trackName else { return nil }
            return ArtworkHit(title: name, year: String((r.releaseDate ?? "").prefix(4)),
                              poster: art.replacingOccurrences(of: "100x100bb", with: "600x900bb"),
                              minutes: r.trackTimeMillis.map { Int($0 / 60000) })
        }
    }

    /// The best match for a film from the database (same title, released within a year).
    func lookup(_ f: Film) async -> ArtworkHit? {
        if let hit = cache[f.id] { return hit }
        if misses.contains(f.id) { return nil }
        let names = [f.title, f.orig].compactMap { $0 }.map { $0.folded }
        let year = Int(f.year) ?? 0
        var found: ArtworkHit?
        for term in [f.orig, f.title].compactMap({ $0 }) where found == nil {
            let hits = await search(term)
            found = hits.first { h in
                let t = h.title.folded
                let y = Int(h.year) ?? 0
                let sameName = names.contains { $0 == t || (t.count > 4 && ($0.hasPrefix(t) || t.hasPrefix($0))) }
                return sameName && (y == 0 || abs(y - year) <= 1)
            }
        }
        if let found {
            cache[f.id] = found
            if let d = try? JSONEncoder().encode(cache) { try? d.write(to: cacheURL, options: .atomic) }
        } else {
            misses.insert(f.id)
        }
        return found
    }
}

private struct ITunesResults: Decodable {
    let results: [ITunesItem]
}

private struct ITunesItem: Decodable {
    let trackName: String?
    let artworkUrl100: String?
    let releaseDate: String?
    let trackTimeMillis: Double?
}
