import SwiftUI

/// Full-screen poster. Tap or swipe for other posters, then running time and ratings,
/// the story, and the cast and producers.
struct PosterViewer: View {
    @Environment(\.dismiss) private var dismiss
    let film: Film
    let posters: [String]
    let minutes: Int?
    @State private var page = 0

    private var posterPages: Int { max(posters.count, 1) }
    private var lastPage: Int { posterPages + 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            TabView(selection: $page) {
                if posters.isEmpty {
                    PosterTile(title: film.title, cat: film.category, width: 280)
                        .onTapGesture { next() }
                        .tag(0)
                } else {
                    ForEach(posters.indices, id: \.self) { i in
                        AsyncImage(url: URL(string: posters[i])) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                            } else if phase.error != nil {
                                PosterTile(title: film.title, cat: film.category, width: 280)
                            } else {
                                ProgressView().tint(.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 150)
                        .contentShape(Rectangle())
                        .onTapGesture { next() }
                        .tag(i)
                    }
                }
                glance.tag(posterPages)
                story.tag(posterPages + 1)
                people.tag(posterPages + 2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                Spacer()
                titleBar
            }
            .allowsHitTesting(false)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }

    private func next() {
        withAnimation { page = min(page + 1, lastPage) }
    }

    private var durationText: String? {
        guard let d = film.duration ?? minutes else { return nil }
        return d >= 60 ? "\(d / 60)h \(String(format: "%02d", d % 60))" : "\(d) min"
    }

    private var titleBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text([film.year, durationText].compactMap { $0 }.joined(separator: " • "))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(film.title.uppercased())
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 44)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.9), .black], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Info pages

    private func infoPage<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(LocalizedStringKey(title)).font(.title2.bold())
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .padding(.top, 50)
            .padding(.bottom, 170)
        }
        .foregroundStyle(.white)
    }

    private var glance: some View {
        infoPage("At a glance") {
            if let d = durationText { fact("Running time", d, symbol: "clock") }
            rating("Critics", film.press)
            rating("Audience", film.spect)
            if let a = film.average, film.press != nil, film.spect != nil { rating("Average", a) }
            fact("In cinemas", D.fmt(film.date, "EEEE d MMMM yyyy"), symbol: "calendar")
            if let g = film.genreText { fact("Genres", g, symbol: "theatermasks") }
            if let o = film.originText { fact("Origin", o, symbol: "globe.europe.africa") }
            if film.press == nil && film.spect == nil {
                Text("No ratings yet. They appear once the film is out.").font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var story: some View {
        infoPage("Story") {
            Text(film.story ?? String(localized: "No synopsis yet. The Tuesday update adds one."))
                .font(.title3)
                .lineSpacing(4)
            if let o = film.orig, !o.isEmpty { fact(film.category == .R ? "Year" : "Original title", o, symbol: "character.book.closed") }
        }
    }

    private var people: some View {
        infoPage("Cast and crew") {
            if let d = film.dir { fact("Director", d, symbol: "megaphone") }
            if let c = film.cast { fact("Main actors", c, symbol: "person.2") }
            fact("Producers", film.prod ?? String(localized: "Not listed yet"), symbol: "building.2")
        }
    }

    private func fact(_ label: String, _ value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 28).foregroundStyle(Color(hex: 0xFFD23F))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.white.opacity(0.6))
                Text(value).font(.body)
            }
        }
    }

    @ViewBuilder
    private func rating(_ label: String, _ value: Double?) -> some View {
        if let v = value {
            HStack(spacing: 14) {
                Image(systemName: "star.fill").font(.title3).frame(width: 28).foregroundStyle(Color(hex: 0xFFD23F))
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 8) {
                        RatingStars(value: v, size: 16)
                        Text(String(format: "%.1f / 5", v)).font(.headline.monospacedDigit())
                    }
                }
            }
        }
    }
}
