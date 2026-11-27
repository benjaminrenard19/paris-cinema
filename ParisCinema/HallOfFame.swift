import SwiftUI

// MARK: - Ratings in half stars

/// Five stars to tap: the left half of a star gives a half (3.5), tapping the same value again clears it.
struct HalfStarPicker: View {
    @Binding var value: Double
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                let full = value >= Double(i)
                let half = !full && value >= Double(i) - 0.5
                Image(systemName: full ? "star.fill" : half ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(full || half ? Color(hex: 0xE0A800) : Color.secondary)
                    .overlay {
                        HStack(spacing: 0) {
                            Color.clear.contentShape(Rectangle()).onTapGesture { set(Double(i) - 0.5) }
                            Color.clear.contentShape(Rectangle()).onTapGesture { set(Double(i)) }
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your rating"))
        .accessibilityValue(value == 0 ? String(localized: "Not rated") : String(localized: "\(String(format: "%.1f", value)) out of 5"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(5, value + 0.5)
            case .decrement: value = max(0, value - 0.5)
            @unknown default: break
            }
        }
    }

    private func set(_ v: Double) { value = value == v ? 0 : v }
}

// MARK: - Who you went with

struct CompanionPicker: View {
    @Environment(Store.self) private var store
    @Binding var selected: [String]
    var title: LocalizedStringKey = "Seen with"
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Your usual people, then anyone ticked who isn't in that list (from an invitation, say)
                    ForEach(store.companions + selected.filter { !store.companions.contains($0) }, id: \.self) { name in
                        let on = selected.contains(name)
                        Button {
                            if on { selected.removeAll { $0 == name } } else { selected.append(name) }
                        } label: {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(on ? Color.theme : Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Button { newName = ""; adding = true } label: {
                        Label("Add someone", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .alert("Add someone", isPresented: $adding) {
            TextField("First name", text: $newName)
            Button("Add") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                store.addCompanion(n)
                if !selected.contains(n) { selected.append(n) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// The people you usually go with (first launch and My profile).
struct CompanionsEditor: View {
    @Environment(Store.self) private var store
    @State private var newName = ""

    var body: some View {
        @Bindable var model = store
        List {
            Section {
                ForEach(store.companions, id: \.self) { Text($0) }
                    .onDelete { model.companions.remove(atOffsets: $0) }
                    .onMove { model.companions.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("First name", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Tick them when you mark a film as seen. Your stats and year review then name your best cinema buddy.")
            }
        }
    }

    private func add() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !store.companions.contains(n) else { return }
        store.companions.append(n)
        newName = ""
    }
}

// MARK: - Hall of Fame: podium, top 10 and every film by your rating

struct HallOfFameView: View {
    @Environment(Store.self) private var store
    @State private var year: Int? = Calendar.current.component(.year, from: Date())
    @State private var path: [String] = []
    @State private var adding = false
    @State private var importing = false
    @State private var editing: String?
    @State private var reordering = false

    private var items: [(String, SeenEntry)] { store.hallRanking(year: year) }

    /// Some films share a rating, so their order is yours to choose.
    private var hasTies: Bool {
        let values = items.map { $0.1.value }
        return Set(values).count < values.count
    }

    private var years: [Int] {
        var ys = Set(store.seenYears)
        ys.insert(Calendar.current.component(.year, from: Date()))
        return ys.sorted(by: >)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let list = items
                Section {
                    if years.count <= 3 {
                        periodPicker.pickerStyle(.segmented)
                    } else {
                        periodPicker.pickerStyle(.menu)
                    }
                    LabeledContent("Films watched", value: "\(list.count)")
                    let rated = list.map { $0.1.value }.filter { $0 > 0 }
                    if !rated.isEmpty {
                        LabeledContent("Average rating", value: String(format: "%.1f ★", rated.reduce(0, +) / Double(rated.count)))
                    }
                }
                if list.isEmpty {
                    ContentUnavailableView("Nothing watched yet", systemImage: "trophy",
                                           description: Text("Mark films as watched and rate them: your favourites climb onto the podium."))
                } else {
                    Section {
                        podium(Array(list.prefix(3)))
                            .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 0, trailing: 8))
                            .listRowBackground(Color.clear)
                    }
                    if list.count > 3 {
                        Section("Top 10") {
                            ForEach(Array(list.dropFirst(3).prefix(7).enumerated()), id: \.element.0) { i, item in
                                link(item, rank: i + 4)
                            }
                        }
                    }
                    if list.count > 10 {
                        Section(year.map { String(localized: "All \(String($0)) films, by your rating") } ?? String(localized: "Every film, by your rating")) {
                            ForEach(Array(list.dropFirst(10)), id: \.0) { item in link(item, rank: nil) }
                        }
                    }
                }
            }
            .navigationTitle("Hall of Fame")
            .navigationDestination(for: String.self) { id in FilmDetailView(id: id) }
            .toolbar {
                if hasTies {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { reordering = true } label: { Image(systemName: "arrow.up.arrow.down") }
                            .accessibilityLabel("Order films with the same rating")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { adding = true } label: { Label("Add a film you watched", systemImage: "plus") }
                        Button { importing = true } label: { Label("Import from a screen recording", systemImage: "video.badge.plus") }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add films you watched")
                }
            }
            .sheet(isPresented: $adding) { AddWatchedView().environment(store) }
            .sheet(isPresented: $reordering) { HallTiesView(year: year).environment(store) }
            .sheet(isPresented: $importing) { VideoImportView().environment(store) }
            .sheet(item: Binding(get: { editing.map { EditTarget(id: $0) } }, set: { editing = $0?.id })) { t in
                AddWatchedView(editingId: t.id).environment(store)
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $year) {
            ForEach(years, id: \.self) { y in Text(String(y)).tag(Optional(y)) }
            Text("All time").tag(Int?.none)
        }
    }

    private func open(_ id: String) {
        if store.index[id] != nil { path.append(id) } else { editing = id }
    }

    /// Second, first and third, the first in the middle and highest.
    private func podium(_ top: [(String, SeenEntry)]) -> some View {
        let order: [(Int, (String, SeenEntry))] = [1, 0, 2].compactMap { i in top.indices.contains(i) ? (i, top[i]) : nil }
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(order, id: \.1.0) { rank, item in
                let medal = rank == 0 ? Color(hex: 0xFFD60A) : rank == 1 ? Color(hex: 0xC0C0C0) : Color(hex: 0xCD7F32)
                let width: CGFloat = rank == 0 ? 96 : 78
                Button { open(item.0) } label: {
                    VStack(spacing: 6) {
                        PosterTile(title: title(item), cat: Cat.from(item.1.c), width: width, url: store.index[item.0]?.poster ?? item.1.p)
                            .overlay(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous).strokeBorder(medal, lineWidth: 3))
                            .shadow(color: medal.opacity(rank == 0 ? 0.55 : 0.3), radius: 14)
                        Text(title(item)).font(.caption.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
                            .foregroundStyle(.primary)
                        RatingStars(value: item.1.value, size: 11)
                        Text("\(rank + 1)")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: rank == 0 ? 70 : rank == 1 ? 50 : 36, alignment: .top)
                            .padding(.top, 4)
                            .background(LinearGradient(colors: [medal, medal.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                                        in: UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
                    }
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(String(localized: "Number \(rank + 1): \(title(item))"))
            }
        }
    }

    private func title(_ item: (String, SeenEntry)) -> String {
        item.1.t ?? store.index[item.0]?.title ?? String(localized: "Film")
    }

    @ViewBuilder
    private func link(_ item: (String, SeenEntry), rank: Int?) -> some View {
        Group {
            if store.index[item.0] != nil {
                NavigationLink(value: item.0) { row(item, rank: rank) }
            } else {
                Button { editing = item.0 } label: { row(item, rank: rank) }
                    .foregroundStyle(.primary)
            }
        }
        .swipeActions {
            Button(role: .destructive) { store.removeSeen(item.0) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private func row(_ item: (String, SeenEntry), rank: Int?) -> some View {
        let s = item.1
        let with = (s.w ?? []).joined(separator: ", ")
        return HStack(spacing: 12) {
            if let rank {
                Text("\(rank)").font(.headline.weight(.heavy)).foregroundStyle(.secondary).frame(width: 24)
            }
            PosterTile(title: title(item), cat: Cat.from(s.c), width: 36, url: store.index[item.0]?.poster ?? s.p)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(item)).font(.headline).lineLimit(2)
                Text(String(localized: "Watched \(D.fmt(s.d, "d MMM yyyy"))") + (with.isEmpty ? "" : " · " + String(localized: "with \(with)")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                RatingStars(value: s.value, size: 11)
            }
        }
    }
}

// MARK: - Same rating: your order

extension Store {
    /// Your watched films for a year (nil: all time), best first. Films with the same rating follow
    /// your own order for that period, then the most recently watched first.
    func hallRanking(year: Int?) -> [(String, SeenEntry)] {
        let key = year.map { String($0) } ?? "all"
        var pos: [String: Int] = [:]
        for (i, id) in (hallOrder[key] ?? []).enumerated() where pos[id] == nil { pos[id] = i }
        return seen
            .filter { year == nil || $0.value.d.hasPrefix(key) }
            .sorted { a, b in
                if a.value.value != b.value.value { return a.value.value > b.value.value }
                let pa = pos[a.key] ?? Int.max, pb = pos[b.key] ?? Int.max
                if pa != pb { return pa < pb }
                return a.value.d != b.value.d ? a.value.d > b.value.d : a.key < b.key
            }
            .map { ($0.key, $0.value) }
    }

    /// Moves films within one rating, for that period only.
    func moveInHall(year: Int?, rating: Double, from: IndexSet, to: Int) {
        let key = year.map { String($0) } ?? "all"
        var group = hallRanking(year: year).filter { $0.1.value == rating }.map(\.0)
        group.move(fromOffsets: from, toOffset: to)
        var order = (hallOrder[key] ?? []).filter { !group.contains($0) }
        order.append(contentsOf: group)
        hallOrder[key] = order
    }

    func resetHallOrder(year: Int?) {
        hallOrder[year.map { String($0) } ?? "all"] = nil
    }
}

/// Drag films that share a rating into the order you like; the podium and top 10 follow.
struct HallTiesView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let year: Int?

    var body: some View {
        let ranking = store.hallRanking(year: year)
        let values = Array(Set(ranking.map { $0.1.value })).sorted(by: >)
        let groups = values.map { v in (v, ranking.filter { $0.1.value == v }) }.filter { $0.1.count > 1 }
        NavigationStack {
            List {
                Section {
                    Text("Films with the same rating: drag them into the order you like. The podium and the top 10 follow.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.0) { group in
                    Section {
                        ForEach(group.1, id: \.0) { item in
                            HStack(spacing: 12) {
                                PosterTile(title: store.index[item.0]?.title ?? item.1.t ?? "?", cat: Cat.from(item.1.c), width: 30,
                                           url: store.index[item.0]?.poster ?? item.1.p)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.index[item.0]?.title ?? item.1.t ?? "?").font(.subheadline.weight(.semibold))
                                    Text(D.fmt(item.1.d, "d MMM yyyy")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onMove { from, to in store.moveInHall(year: year, rating: group.0, from: from, to: to) }
                    } header: {
                        HStack {
                            RatingStars(value: group.0, size: 11)
                            Text("\(group.1.count) films")
                        }
                    }
                }
                if store.hallOrder[year.map { String($0) } ?? "all"] != nil {
                    Section {
                        Button("Back to the usual order (latest watched first)", role: .destructive) { store.resetHallOrder(year: year) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(year.map { String(localized: "Same ratings · \(String($0))") } ?? String(localized: "Same ratings · All time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
