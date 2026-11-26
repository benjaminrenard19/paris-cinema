import SwiftUI

@main
struct ParisCinemaApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(Color(hex: 0xA3142F))
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            store.refreshFromLinkedFile()
            Task { @MainActor in await store.refreshFromFeed() }
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            WeeksView()
                .tabItem { Label("Films", systemImage: "film") }
            MyListView()
                .tabItem { Label("My list", systemImage: "star") }
            WatchedView()
                .tabItem { Label("Watched", systemImage: "checkmark.seal") }
            CinemasView()
                .tabItem { Label("Cinemas", systemImage: "map") }
        }
    }
}

// MARK: - Shared pieces

/// A designed poster tile (real posters can't be bundled, so each film gets its own tile).
struct PosterTile: View {
    let title: String
    let cat: Cat
    var width: CGFloat = 54

    var body: some View {
        let h = width * 1.45
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [cat.color, cat.color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: cat.symbol)
                .font(.system(size: width * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(width * 0.08)
            Text(title)
                .font(.system(size: max(8, width * 0.15), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .padding(width * 0.09)
        }
        .frame(width: width, height: h)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct Stars: View {
    let rating: Int
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? Color(hex: 0xE0A800) : Color.secondary.opacity(0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating == 0 ? "Not rated" : "\(rating) out of 5 stars")
    }
}

struct CatBadge: View {
    let cat: Cat
    var body: some View {
        Text(cat.short)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(cat.color.opacity(0.15), in: Capsule())
            .foregroundStyle(cat.color)
    }
}

struct FilmRow: View {
    @Environment(Store.self) private var store
    let film: Film
    var showDate = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterTile(title: film.title, cat: film.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title).font(.headline).lineLimit(2)
                if let line = subtitle { Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 6) {
                    CatBadge(cat: film.category)
                    Text(film.releaseSize.label).font(.caption2).foregroundStyle(.secondary)
                    if let s = store.seen[film.id] { Stars(rating: s.r, size: 9) }
                }
            }
            Spacer(minLength: 0)
            if store.isFav(film.id) {
                Image(systemName: "star.fill").foregroundStyle(Color(hex: 0xE0A800)).accessibilityLabel("Favourite")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if showDate || film.date != film.week { parts.append(D.fmt(film.date, "EEE d MMM")) }
        if let d = film.dir, !d.isEmpty { parts.append(d) }
        if let o = film.origin, !o.isEmpty { parts.append(o) }
        if film.category == .R, let y = film.orig, !y.isEmpty { parts.append(y) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
