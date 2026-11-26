import SwiftUI
import PhotosUI
import AVFoundation
import Vision
import UniformTypeIdentifiers

// MARK: - Reading a screen recording of another film app

/// A screen recording picked in Photos, copied to a temporary file.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}

/// One film read from the recording: its title, year and the stars you gave it.
struct ReadFilm: Identifiable, Hashable {
    let id: String          // folded title
    var title: String
    var year: String
    var stars: [Int: Int]   // stars counted → how many frames said so

    var rating: Int { stars.max { $0.value < $1.value }?.key ?? 0 }
}

enum RecordingReader {
    /// Reads a frame every half second: each "title / year and genres / stars" row of a list.
    static func read(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async -> [ReadFilm] {
        let asset = AVURLAsset(url: url)
        let loaded = try? await asset.load(.duration)
        guard let duration = loaded else { return [] }
        let seconds = max(0.5, CMTimeGetSeconds(duration))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        var found: [String: ReadFilm] = [:]
        var order: [String] = []
        let step = 0.5
        var t = 0.0
        while t < seconds {
            let result = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
            if let frame = result?.image {
                for (title, year, stars) in rows(in: frame) {
                    let key = slug(title)
                    if found[key] == nil {
                        found[key] = ReadFilm(id: key, title: title, year: year, stars: [:])
                        order.append(key)
                    }
                    if stars > 0 { found[key]?.stars[stars, default: 0] += 1 }
                }
            }
            t += step
            progress(min(1, t / seconds))
        }
        return order.compactMap { found[$0] }
    }

    private struct Line {
        let text: String
        let x: CGFloat, y: CGFloat, h: CGFloat    // top-left origin, 0…1
    }

    /// (title, year, stars) for each row of one frame.
    private static func rows(in image: CGImage) -> [(String, String, Int)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines: [Line] = (request.results ?? []).compactMap { o in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            let b = o.boundingBox
            return Line(text: s.trimmingCharacters(in: .whitespaces), x: b.minX, y: 1 - b.maxY, h: b.height)
        }
        .filter { $0.y > 0.07 && $0.y < 0.92 }
        .sorted { $0.y < $1.y }
        guard let pixels = Pixels(image) else { return [] }
        var out: [(String, String, Int)] = []
        for line in lines {
            guard let m = line.text.range(of: #"^(19|20)\d\d\b"#, options: .regularExpression) else { continue }
            let year = String(line.text[m])
            // The title sits just above, starting at the same left edge.
            let above = lines.last { t in
                t.y < line.y && abs(t.x - line.x) < 0.04 && line.y - (t.y + t.h) < line.h * 2
            }
            guard let title = above?.text, isTitle(title) else { continue }
            out.append((title, year, pixels.stars(below: line)))
        }
        return out
    }

    /// Leaves out lines that are stars or years read as text ("★★★", "KKK", "2026").
    private static func isTitle(_ s: String) -> Bool {
        let letters = s.filter { $0.isLetter }
        guard letters.count >= 2, s.range(of: #"^(19|20)\d\d\b"#, options: .regularExpression) == nil else { return false }
        return Set(letters.lowercased()).count > 1
    }

    /// The frame's pixels, to count the orange stars under a row.
    private struct Pixels {
        let data: [UInt8]
        let w: Int, h: Int

        init?(_ image: CGImage) {
            w = image.width; h = image.height
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let ok = buf.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            data = buf
        }

        func orange(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < w, y < h else { return false }
            let i = (y * w + x) * 4
            let r = data[i], g = data[i + 1], b = data[i + 2]
            return r > 200 && g > 110 && g < 210 && b < 100
        }

        /// Filled stars in the strip under a "year · genres" line.
        func stars(below line: Line) -> Int {
            let lh = line.h * CGFloat(h)
            let top = Int((line.y + line.h) * CGFloat(h) + lh * 0.15)
            let bottom = top + Int(lh * 1.4)
            let x0 = Int(line.x * CGFloat(w)), x1 = x0 + Int(lh * 9)
            var count = 0, run = 0
            for x in x0..<x1 {
                var hit = false
                var y = top
                while y < bottom { if orange(x, y) { hit = true; break }; y += 2 }
                if hit { run += 1 } else {
                    if run >= 3 { count += 1 }
                    run = 0
                }
            }
            if run >= 3 { count += 1 }
            return min(5, count)
        }
    }
}

// MARK: - Matching with Sloth Cinema's films

extension Store {
    /// The film a title read from another app stands for: same French or original title, or very close, same year.
    func matchFilm(title: String, year: String) -> Film? {
        let key = slug(title)
        let y = Int(year) ?? 0
        func nearYear(_ f: Film) -> Bool { abs((Int(f.date.prefix(4)) ?? 0) - y) <= 1 || y == 0 }
        let candidates = films.filter(nearYear)
        if let f = candidates.first(where: { slug($0.title) == key || ($0.orig.map { !$0.allSatisfy(\.isNumber) && slug($0) == key } ?? false) }) {
            return f
        }
        var best: (Film, Double)?
        for f in candidates {
            for t in [f.title, f.orig ?? ""] where !t.isEmpty {
                let r = similarity(key, slug(t))
                if r > (best?.1 ?? 0) { best = (f, r) }
            }
        }
        return (best?.1 ?? 0) >= 0.85 ? best?.0 : nil
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }
}

// MARK: - The import screen

struct VideoImportView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let id: String
        var read: ReadFilm
        var filmId: String?
        var rating: Int
        var include: Bool
        var asIs = false    // add with the title as read, without a film from the list
    }

    @State private var item: PhotosPickerItem?
    @State private var progress: Double?
    @State private var rows: [Row] = []
    @State private var dateRule = 0     // 0 release day, 1 1 January of its year, 2 today
    @State private var choosing: String?
    @State private var note: String?

    private var found: [Row] { rows.filter { $0.filmId != nil } }
    private var unmatched: [Row] { rows.filter { $0.filmId == nil } }
    private var toImport: Int { rows.filter { $0.include && ($0.filmId != nil || $0.asIs) }.count }

    var body: some View {
        NavigationStack {
            Form {
                if rows.isEmpty {
                    Section {
                        PhotosPicker(selection: $item, matching: .videos) {
                            Label("Choose the screen recording", systemImage: "video.badge.plus")
                        }
                        if let p = progress {
                            ProgressView(value: p) { Text("Reading the films…") }
                        }
                        if let n = note { Text(n).foregroundStyle(.secondary) }
                    } footer: {
                        Text("Record your screen while scrolling through a list of films in another app (title, year and your stars). Sloth Cinema reads every film in the video, on this iPhone.")
                    }
                } else {
                    Section {
                        Text(String(localized: "\(rows.count) films read · \(found.count) found in Sloth Cinema"))
                            .font(.subheadline.weight(.semibold))
                    }
                    Section {
                        Picker("Date", selection: $dateRule) {
                            Text("Release day in Paris").tag(0)
                            Text("1 January of its year").tag(1)
                            Text("Today").tag(2)
                        }
                        LabeledContent("Rating", value: String(localized: "Stars from the video"))
                        LabeledContent("Cinema", value: String(localized: "Left empty"))
                    } header: {
                        Text("For all these films")
                    } footer: {
                        Text("The cinema stays empty. You can add it later on each film's page.")
                    }
                    if !unmatched.isEmpty {
                        Section(String(localized: "To check · \(unmatched.count)")) {
                            ForEach(unmatched) { r in unmatchedRow(r) }
                        }
                    }
                    Section(String(localized: "Found · \(found.count)")) {
                        ForEach(found) { r in foundRow(r) }
                    }
                }
            }
            .navigationTitle("Import from a video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Import \(toImport)")) { importAll() }
                        .disabled(toImport == 0)
                }
            }
            .onChange(of: item) { _, new in
                guard let new else { return }
                Task { await load(new) }
            }
            .sheet(item: Binding(get: { choosing.map { EditTarget(id: $0) } }, set: { choosing = $0?.id })) { t in
                FilmChooser(query: rows.first { $0.id == t.id }?.read.title ?? "") { film in
                    if let i = rows.firstIndex(where: { $0.id == t.id }) {
                        rows[i].filmId = film.id
                        rows[i].include = true
                    }
                    choosing = nil
                }
                .environment(store)
            }
        }
    }

    private func foundRow(_ r: Row) -> some View {
        let f = r.filmId.flatMap { store.index[$0] }
        let already = r.filmId.flatMap { store.seen[$0] } != nil
        return HStack(spacing: 12) {
            if let f { PosterTile(title: f.title, cat: f.category, width: 36, url: f.poster) }
            VStack(alignment: .leading, spacing: 2) {
                Text(f?.title ?? r.read.title).font(.subheadline.weight(.semibold))
                if let f, slug(f.title) != r.read.id {
                    Text(String(localized: "In the video: \(r.read.title)")).font(.caption).foregroundStyle(.secondary)
                }
                if already { Text("Already in Watched: the rating is updated").font(.caption).foregroundStyle(.secondary) }
                starsMenu(r)
            }
            Spacer()
            Button { toggle(r.id) } label: {
                Image(systemName: r.include ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(r.include ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(r.include ? String(localized: "Leave out") : String(localized: "Include"))
        }
    }

    private func unmatchedRow(_ r: Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.read.title).font(.subheadline.weight(.semibold))
                Text(r.asIs ? String(localized: "Added with this title") : String(localized: "Not found in Sloth Cinema"))
                    .font(.caption).foregroundStyle(.secondary)
                starsMenu(r)
            }
            Spacer()
            Menu {
                Button { choosing = r.id } label: { Label("Choose the film", systemImage: "magnifyingglass") }
                Button { setAsIs(r.id, true) } label: { Label("Add with this title", systemImage: "plus") }
                Button(role: .destructive) { setAsIs(r.id, false) } label: { Label("Leave out", systemImage: "xmark") }
            } label: {
                Text(r.asIs ? String(localized: "Change") : String(localized: "Choose"))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func starsMenu(_ r: Row) -> some View {
        Menu {
            ForEach(0...5, id: \.self) { n in
                Button(n == 0 ? String(localized: "No rating") : String(repeating: "★", count: n)) { setRating(r.id, n) }
            }
        } label: {
            Text(r.rating == 0 ? String(localized: "No rating") : String(repeating: "★", count: r.rating) + String(repeating: "☆", count: 5 - r.rating))
                .font(.caption).foregroundStyle(Color(hex: 0xE0A800))
        }
    }

    private func toggle(_ id: String) { if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].include.toggle() } }
    private func setRating(_ id: String, _ n: Int) { if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].rating = n } }
    private func setAsIs(_ id: String, _ on: Bool) {
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].asIs = on; rows[i].include = on }
    }

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        note = nil
        progress = 0
        let picked = try? await item.loadTransferable(type: MovieFile.self)
        guard let movie = picked ?? nil else {
            progress = nil
            note = String(localized: "That video couldn't be opened.")
            return
        }
        let read = await RecordingReader.read(movie.url) { p in
            Task { @MainActor in progress = p }
        }
        try? FileManager.default.removeItem(at: movie.url)
        progress = nil
        guard !read.isEmpty else {
            note = String(localized: "No films found in that video. Record a list showing each film's title, year and stars.")
            return
        }
        var used = Set<String>()
        rows = read.compactMap { r in
            let f = store.matchFilm(title: r.title, year: r.year)
            if let f, !used.insert(f.id).inserted { return nil }    // the same film read twice
            return Row(id: r.id, read: r, filmId: f?.id, rating: r.rating, include: f != nil)
        }
    }

    private func importAll() {
        let today = D.today
        for r in rows where r.include {
            if let id = r.filmId, let f = store.index[id] {
                if let old = store.seen[id] {
                    store.setSeen(f, rating: r.rating, on: old.d)
                } else {
                    let day: String
                    switch dateRule {
                    case 1: day = "\(f.date.prefix(4))-01-01"
                    case 2: day = today
                    default: day = min(f.date, today)
                    }
                    store.setSeen(f, rating: r.rating, on: day)
                }
            } else if r.asIs {
                let day = dateRule == 2 || r.read.year.isEmpty ? today : min("\(r.read.year)-01-01", today)
                store.addCustomSeen(title: r.read.title, day: day, rating: r.rating, category: .O)
            }
        }
        dismiss()
    }
}

/// Pick the right film for a title that wasn't recognised.
struct FilmChooser: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var query: String
    let onPick: (Film) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.search(query).prefix(60)) { f in
                    Button { onPick(f) } label: { FilmRow(film: f, showDate: true) }
                        .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, director, actor")
            .navigationTitle("Choose the film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
