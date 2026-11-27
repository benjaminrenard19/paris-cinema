import SwiftUI

// MARK: - First launch: your name, your cinemas, how to sort the Films page

struct WelcomeView: View {
    @Environment(Store.self) private var store
    let onDone: () -> Void

    @AppStorage("userName") private var userName = ""
    @AppStorage("weekSort") private var sortRaw = WeekSort.standard.rawValue
    @AppStorage("filmsShow") private var showRaw = FilmsShow.recent.rawValue
    @State private var step = 0
    private let lastStep = 4
    @State private var name = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch step {
                case 0: nameStep
                case 1: Form {
                    AnimalAndBirthdayFields()
                    Section {
                        CompanionPicker(selected: .constant([]), title: "Who do you usually go with?")
                    } footer: {
                        Text("Tick them when you mark a film as seen. Your stats and year review then name your best cinema buddy.")
                    }
                }
                case 2: FavouriteCinemasList(intro: String(localized: "Star the cinemas you go to. They come first everywhere, with their session times."))
                case 3: List { VersionQuestions() }
                default: sortStep
                }
                Button {
                    next()
                } label: {
                    Text(step < lastStep ? String(localized: "Next") : String(localized: "Start"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.theme, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { withAnimation { step -= 1 } }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") { finish() }
                }
            }
            .onAppear { name = userName }
        }
    }

    private var title: String {
        switch step {
        case 0: return String(localized: "Welcome")
        case 1: return String(localized: "About you")
        case 2: return String(localized: "Your cinemas")
        case 3: return String(localized: "VO or VF?")
        default: return String(localized: "Your Films page")
        }
    }

    private var nameStep: some View {
        ScrollView {
            VStack(spacing: 22) {
                StageHeader(name: name.trimmingCharacters(in: .whitespaces))
                    .padding(.top, 12)
                Text("What should we call you?")
                    .font(.title2.weight(.bold))
                TextField("Your first name", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.next)
                    .focused($typing)
                    .onSubmit { next() }
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                Text("Your name stays on this iPhone. It appears on the stage of the Films page and on your stats.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .onAppear { typing = true }
    }

    private var sortStep: some View {
        List {
            Section {
                ForEach(FilmsShow.allCases) { m in
                    Button { showRaw = m.rawValue } label: {
                        HStack {
                            Text(m.label).foregroundStyle(.primary)
                            Spacer()
                            if showRaw == m.rawValue { Image(systemName: "checkmark").foregroundStyle(Color.theme) }
                        }
                    }
                }
            } header: {
                Text("Films page shows")
            } footer: {
                Text("Also used for the weekly releases slideshow. One tap on Films changes it.")
            }
            Section {
                ForEach(WeekSort.allCases) { s in
                    Button { sortRaw = s.rawValue } label: {
                        HStack {
                            Text(s.label).foregroundStyle(.primary)
                            Spacer()
                            if sortRaw == s.rawValue { Image(systemName: "checkmark").foregroundStyle(Color.theme) }
                        }
                    }
                }
            } header: {
                Text("How should films be sorted?")
            } footer: {
                Text("You can change it any time with the ⇅ button at the top left of Films.")
            }
        }
    }

    private func next() {
        if step == 0 { userName = name.trimmingCharacters(in: .whitespaces) }
        if step < lastStep { withAnimation { step += 1 } } else { finish() }
    }

    private func finish() {
        if step == 0 { userName = name.trimmingCharacters(in: .whitespaces) }
        onDone()
    }
}

// MARK: - Star your cinemas (first launch and My profile)

struct FavouriteCinemasList: View {
    @Environment(Store.self) private var store
    var intro: String? = nil
    @State private var query = ""

    private var filtered: [Cinema] {
        let q = query.folded
        let list = store.allCinemas.filter { q.isEmpty || $0.name.folded.contains(q) || $0.address.folded.contains(q) }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if let intro { Section { Text(intro).font(.subheadline).foregroundStyle(.secondary) } }
            let mine = store.myCinemas.compactMap { store.cinema(named: $0) }
            if !mine.isEmpty && query.isEmpty {
                Section("My cinemas") { ForEach(mine) { c in row(c) } }
            }
            ForEach(Cinema.types + ["Other"], id: \.self) { t in
                let list = filtered.filter { t == "Other" ? !Cinema.types.contains($0.type) : $0.type == t }
                if !list.isEmpty {
                    Section(LocalizedStringKey(t)) { ForEach(list) { c in row(c) } }
                }
            }
        }
        .searchable(text: $query, prompt: "Cinema or address")
    }

    private func row(_ c: Cinema) -> some View {
        Button { store.togglePreferred(c) } label: {
            HStack(spacing: 12) {
                Image(systemName: store.isPreferred(c.name) ? "star.fill" : "star")
                    .foregroundStyle(store.isPreferred(c.name) ? Color(hex: 0xE0A800) : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).foregroundStyle(.primary)
                    Text(c.address).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityAddTraits(store.isPreferred(c.name) ? .isSelected : [])
    }
}

// MARK: - My profile: name, cinemas, habits and all-time stats

struct ProfileView: View {
    @Environment(Store.self) private var store
    @AppStorage("userName") private var userName = ""
    @AppStorage("weekSort") private var sortRaw = WeekSort.standard.rawValue
    @AppStorage("filmsShow") private var showRaw = FilmsShow.recent.rawValue
    @AppStorage("hideSeen") private var hideSeen = true
    @AppStorage("animal") private var animal = Animal.sloth
    @AppStorage("birthday") private var birthday = ""
    @State private var scope = 0

    private var birthdayLabel: String { D.fmt("2024-" + birthday, "d MMMM") }
    @State private var year = D.cal.component(.year, from: Date())
    @State private var month = D.cal.component(.month, from: Date())
    @State private var story: StatsPeriod?

    private var period: StatsPeriod {
        switch scope {
        case 1: return .year(year)
        case 2: return .month(year, month)
        default: return .all
        }
    }

    private var years: [Int] {
        var ys = Set(store.seen.values.compactMap { Int($0.d.prefix(4)) })
        ys.insert(D.cal.component(.year, from: Date()))
        return ys.sorted(by: >)
    }

    var body: some View {
        Form {
            Section("You") {
                TextField("Your first name", text: $userName)
                    .textContentType(.givenName)
                NavigationLink {
                    FavouriteCinemasList()
                        .navigationTitle("My cinemas")
                } label: {
                    LabeledContent("My cinemas", value: store.myCinemas.isEmpty ? String(localized: "None yet") : "\(store.myCinemas.count)")
                }
                NavigationLink {
                    Form { AnimalAndBirthdayFields() }.navigationTitle("Your animal and birthday")
                } label: {
                    LabeledContent("Your animal and birthday", value: animal + (birthday.isEmpty ? "" : "  🎂 " + birthdayLabel))
                }
                NavigationLink {
                    CompanionsEditor().navigationTitle("People you go with")
                } label: {
                    LabeledContent("People you go with", value: store.companions.isEmpty ? String(localized: "None yet") : "\(store.companions.count)")
                }
                Picker("Films page shows", selection: $showRaw) {
                    ForEach(FilmsShow.allCases) { m in Text(m.label).tag(m.rawValue) }
                }
                Picker("Films page order", selection: $sortRaw) {
                    ForEach(WeekSort.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
            }
            Section {
                Toggle("Hide films I've seen", isOn: $hideSeen)
            } footer: {
                Text("When on, films you've marked as watched leave the Films list, the search and the cinema pages, so you only see what's left to watch.")
            }
            Section {
                Text(store.habits.summary ?? String(localized: "Plan your films and mark them as watched: Sloth Cinema learns when and where you like to go, and suggests sessions to match."))
            } header: {
                Text("Your habits")
            }
            Section {
                Picker("Period", selection: $scope) {
                    Text("All time").tag(0)
                    Text("Yearly").tag(1)
                    Text("Monthly").tag(2)
                }
                .pickerStyle(.segmented)
                if scope >= 1 {
                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { y in Text(String(y)).tag(y) }
                    }
                }
                if scope == 2 {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text(D.fmtCap(String(format: "2026-%02d-01", m), "LLLL")).tag(m)
                        }
                    }
                }
                Button { story = period } label: {
                    Label("Open as a story to share", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                }
            } header: {
                Text("My stats")
            }
            StatsList(stats: store.stats(period))
        }
        .navigationTitle("My profile")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $story) { p in StoryView(period: p).environment(store) }
    }
}
