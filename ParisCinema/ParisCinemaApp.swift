import SwiftUI

@main
struct ParisCinemaApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Posters stay on disk; only a little is kept in memory, so iOS doesn't close the app in the background.
        URLCache.shared = URLCache(memoryCapacity: 16_000_000, diskCapacity: 300_000_000)
        Notifier.shared.setUp()
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ParisCinemaApp.trimMemory() }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onAppear {
                    Notifier.shared.attach { tap in
                        Task { @MainActor in store.handle(tap) }
                    }
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                store.scheduleBackgroundRefresh()
                ParisCinemaApp.trimMemory()
            }
            guard phase == .active else { return }
            Theme.shared.apply()
            store.refreshFromLinkedFile()
            Task { @MainActor in
                await store.refreshFromFeed()
                await store.loadHistory()
            }
        }
        .backgroundTask(.appRefresh(AlertPrefs.refreshTask)) {
            await store.backgroundRefresh()
        }
    }

    /// Empties the in-memory poster cache (the copies on disk stay).
    static func trimMemory() {
        let cache = URLCache.shared
        let capacity = cache.memoryCapacity
        cache.memoryCapacity = 0
        cache.memoryCapacity = capacity
    }
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    @AppStorage("welcomeDone") private var welcomeDone = false
    @AppStorage("versionAsked") private var versionAsked = false

    /// First the welcome (name, cinemas, versions, sorting), then the tutorial.
    enum Cover: String, Identifiable {
        case welcome, tutorial, versions
        var id: String { rawValue }
    }

    private var cover: Cover? {
        if !welcomeDone { return .welcome }
        if !tutorialSeen { return .tutorial }
        if !versionAsked { return .versions }
        return nil
    }

    var body: some View {
        @Bindable var model = store
        let theme = Theme.shared
        TabView {
            WeeksView()
                .tabItem { Label("Films", systemImage: "film") }
            WeekPlanView()
                .tabItem { Label("My week", systemImage: "calendar") }
            MyListView()
                .tabItem { Label("OTW", systemImage: "star") }
            HallOfFameView()
                .tabItem { Label("Hall of Fame", systemImage: "trophy") }
            CinemasView()
                .tabItem { Label("Cinemas", systemImage: "map") }
        }
        .tint(theme.color)
        .onAppear { theme.apply(); theme.scheduleIcon() }
        .sheet(item: $model.checkIn) { c in
            CheckInView(checkIn: c).environment(store)
        }
        .fullScreenCover(item: Binding(get: { cover }, set: { _ in })) { c in
            switch c {
            case .welcome:
                WelcomeView { welcomeDone = true; versionAsked = true; store.scheduleReleaseAlerts(ask: true) }
                    .environment(store)
                    .tint(theme.color)
            case .tutorial:
                TutorialView { tutorialSeen = true }
            case .versions:
                VersionSetupView { versionAsked = true; store.scheduleReleaseAlerts(ask: true) }
                    .tint(theme.color)
            }
        }
        .fullScreenCover(item: $model.releasesWeek) { t in
            ReleasesSlideshowView(week: t.id).environment(store).tint(theme.color)
        }
        .sheet(item: $model.openCinema) { t in
            CinemaSheet(name: t.id).environment(store).tint(theme.color)
        }
        .sheet(item: $model.receivedInvite) { i in
            InvitationReceivedView(invite: i).environment(store).tint(theme.color)
        }
        .onOpenURL { store.openInvitation($0) }
        .onChange(of: store.inboxBadge, initial: true) { _, n in store.updateIconBadge(n) }
    }
}

// MARK: - Shared pieces

/// A designed poster tile (real posters can't be bundled, so each film gets its own tile).
/// The film's official poster when there is one, otherwise a designed tile.
struct PosterTile: View {
    let title: String
    let cat: Cat
    var width: CGFloat = 54
    var url: String? = nil

    var body: some View {
        ZStack {
            tile
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: width, height: width * 1.45)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var tile: some View {
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
        .accessibilityLabel(rating == 0 ? String(localized: "Not rated") : String(localized: "\(rating) out of 5 stars"))
    }
}

/// Five stars filled to a rating out of 5, in half steps (3.6 shows three and a half).
struct RatingStars: View {
    let value: Double
    var size: CGFloat = 12
    var body: some View {
        let halves = Int((min(max(value, 0), 5) * 2).rounded())
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                let name = halves >= i * 2 ? "star.fill" : halves == i * 2 - 1 ? "star.leadinghalf.filled" : "star"
                Image(systemName: name)
                    .font(.system(size: size))
                    .foregroundStyle(name == "star" ? Color.secondary.opacity(0.5) : Color(hex: 0xE0A800))
            }
        }
        .accessibilityHidden(true)
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
            PosterTile(title: film.title, cat: film.category, url: film.poster)
            VStack(alignment: .leading, spacing: 4) {
                Text(film.title).font(.headline).lineLimit(2)
                if let line = subtitle { Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 6) {
                    CatBadge(cat: film.category)
                    if !film.isRepertory { Text(film.releaseSize.label).font(.caption2).foregroundStyle(.secondary) }
                    if let s = store.seen[film.id] { RatingStars(value: s.value, size: 9) }
                }
                if !film.genres.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(film.genres.prefix(3), id: \.self) { g in
                            Text(Film.genreLabel(g))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                    }
                    .lineLimit(1)
                }
                if let facts {
                    Text(facts).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { store.toggleFav(film) } label: {
                Image(systemName: store.isFav(film.id) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(store.isFav(film.id) ? Color(hex: 0xE0A800) : Color.secondary.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(store.isFav(film.id) ? String(localized: "Remove from favourites") : String(localized: "Add to favourites"))
        }
        .padding(.vertical, 2)
    }

    private var facts: String? {
        var parts: [String] = []
        if let d = film.durationText { parts.append(d) }
        if let p = film.press { parts.append(String(localized: "Critics \(String(format: "%.1f", p))")) }
        if let s = film.spect { parts.append(String(localized: "Audience \(String(format: "%.1f", s))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var subtitle: String? {
        var parts: [String] = []
        if !film.isRepertory && (showDate || film.date != film.week) { parts.append(D.fmt(film.date, "EEE d MMM")) }
        if let d = film.dir, !d.isEmpty { parts.append(d) }
        if let o = film.origin, !o.isEmpty { parts.append(o) }
        if film.category == .R, let y = film.orig, !y.isEmpty { parts.append(y) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
