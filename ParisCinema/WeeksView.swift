import SwiftUI

struct WeeksView: View {
    @Environment(Store.self) private var store
    @State private var week = ""
    @State private var cats: Set<Cat> = []
    @State private var favOnly = false
    @State private var query = ""
    @State private var showData = false

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section { weekHeader }
                    Section {
                        filterBar
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                    Section {
                        if visible.isEmpty {
                            Text(store.films(in: week).isEmpty ? "No films loaded for this week yet." : "No films match these filters.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(visible) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f) }
                                .swipeActions(edge: .trailing) { favButton(f) }
                        }
                    } header: {
                        Text("\(visible.count) film\(visible.count == 1 ? "" : "s")")
                    }
                } else {
                    let results = store.search(query)
                    Section("\(results.count) result\(results.count == 1 ? "" : "s")") {
                        ForEach(results.prefix(150)) { f in
                            NavigationLink(value: f.id) { FilmRow(film: f, showDate: true) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await store.refreshFromFeed(force: true) }
            .navigationTitle("Paris cinema")
            .searchable(text: $query, prompt: "Title, director, actor")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showData = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .accessibilityLabel("Update films")
                }
            }
            .sheet(isPresented: $showData) { DataView().environment(store) }
            .onAppear { if week.isEmpty || store.byWeek[week] == nil { week = store.defaultWeek } }
            .onChange(of: store.weeks) { _, _ in if store.byWeek[week] == nil { week = store.defaultWeek } }
        }
    }

    private var visible: [Film] {
        store.films(in: week).filter { f in
            (cats.isEmpty || cats.contains(f.category)) && (!favOnly || store.isFav(f.id))
        }
    }

    private var position: Int? { store.weeks.firstIndex(of: week) }

    private var weekHeader: some View {
        HStack(spacing: 8) {
            Button { step(-1) } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                .disabled((position ?? 0) <= 0)
                .accessibilityLabel("Previous week")
            Menu {
                if store.byWeek[store.currentWeek] != nil {
                    Button("This week") { week = store.currentWeek }
                }
                ForEach(months, id: \.0) { item in
                    Menu(item.0) {
                        ForEach(item.1, id: \.self) { w in
                            Button("\(D.fmt(w, "d MMM")) · \(store.films(in: w).count) films") { week = w }
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text(week == store.currentWeek ? "This week" : "Week of \(D.fmt(week, "d MMMM yyyy"))")
                        .font(.headline)
                    Text(D.weekRange(week)).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            Button { step(1) } label: { Image(systemName: "chevron.right").font(.title3.weight(.semibold)) }
                .disabled(position == nil || position! >= store.weeks.count - 1)
                .accessibilityLabel("Next week")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private var months: [(String, [String])] {
        var out: [(String, [String])] = []
        for w in store.weeks {
            let m = D.fmt(w, "MMMM yyyy")
            if out.last?.0 == m { out[out.count - 1].1.append(w) } else { out.append((m, [w])) }
        }
        return out
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Favourites", symbol: "star.fill", on: favOnly, color: Color(hex: 0xE0A800)) { favOnly.toggle() }
                ForEach(Cat.allCases) { c in
                    let n = store.films(in: week).filter { $0.category == c }.count
                    if n > 0 {
                        chip("\(c.short) \(n)", symbol: nil, on: cats.contains(c), color: c.color) {
                            if cats.contains(c) { cats.remove(c) } else { cats.insert(c) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ text: String, symbol: String?, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                Text(text).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? color : color.opacity(0.12), in: Capsule())
            .foregroundStyle(on ? Color.white : color)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func favButton(_ f: Film) -> some View {
        Button { store.toggleFav(f) } label: {
            Label(store.isFav(f.id) ? "Unfavourite" : "Favourite", systemImage: store.isFav(f.id) ? "star.slash" : "star")
        }
        .tint(Color(hex: 0xE0A800))
    }

    private func step(_ d: Int) {
        guard let i = position else { week = store.defaultWeek; return }
        let j = i + d
        if store.weeks.indices.contains(j) { week = store.weeks[j] }
    }
}
