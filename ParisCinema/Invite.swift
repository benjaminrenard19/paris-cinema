import SwiftUI
import UIKit

/// "Would you join me…?": a picture of the poster with the plan, and the sentence, to send in any app.
struct InviteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userName") private var userName = ""
    let filmId: String

    @State private var poster: UIImage?
    @State private var image: Image?

    private var film: Film? { store.index[filmId] }
    private var plan: Plan? { store.plans[filmId] }

    private var address: String {
        guard let p = plan else { return "" }
        if let a = p.ca, !a.isEmpty { return a }
        return store.cinema(named: p.cn)?.address ?? ""
    }

    /// "Would you join me to go to the movies at UGC Ciné Cité Les Halles at 20:30 on Friday 27 November? 7 place de la Rotonde, 75001"
    private var sentence: String {
        guard let p = plan else { return "" }
        let base = String(localized: "Would you join me to go to the movies at \(p.cn) at \(p.t) on \(D.fmt(p.d, "EEEE d MMMM"))?")
        return address.isEmpty ? base : base + " " + address
    }

    /// The sentence, then a link that opens the invitation in Sloth Cinema (for friends who have the app).
    private var message: String {
        guard let f = film, let p = plan,
              let url = store.inviteLink(f, p, version: store.version(f.id, at: p.cn, day: p.d, time: p.t), from: userName)
        else { return sentence }
        return sentence + "\n\n" + String(localized: "In Sloth Cinema: \(url.absoluteString)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let f = film, let p = plan {
                        card(f, p)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(radius: 10)
                            .padding(.horizontal, 40)
                        Text(sentence)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        CompanionPicker(selected: Binding(get: { store.plans[f.id]?.w ?? [] }, set: { store.setPlanCompanions(f.id, $0) }),
                                        title: "Who are you inviting?")
                            .padding(.horizontal, 24)
                        if let image {
                            ShareLink(item: image, subject: Text(f.title), message: Text(message),
                                      preview: SharePreview(Text(f.title), image: image)) {
                                Label("Send the invitation", systemImage: "paperplane.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.theme, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 24)
                        } else {
                            ProgressView()
                        }
                        ShareLink(item: message) {
                            Label("Send the text only", systemImage: "text.bubble")
                        }
                    } else {
                        Text("Plan the film first: choose a cinema, a day and a time.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Invite someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await prepare() }
        }
    }

    private func card(_ f: Film, _ p: Plan) -> InviteCard {
        InviteCard(film: f, plan: p, address: address, poster: poster,
                   version: store.version(f.id, at: p.cn, day: p.d, time: p.t),
                   accent: Theme.shared.color, deep: Theme.shared.deep)
    }

    /// Loads the poster, then draws the card as a 1080 × 1350 picture.
    @MainActor
    private func prepare() async {
        guard let f = film, let p = plan else { return }
        if poster == nil, let s = f.poster, let url = URL(string: s) {
            let result = try? await URLSession.shared.data(from: url)
            if let data = result?.0 { poster = UIImage(data: data) }
        }
        let content = card(f, p)
            .frame(width: 360, height: 450)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}

/// The picture sent with an invitation: poster, film, day, time, cinema and address.
struct InviteCard: View {
    let film: Film
    let plan: Plan
    let address: String
    let poster: UIImage?
    let version: String?
    let accent: Color
    let deep: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [accent, deep, .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 12) {
                Text("Would you join me?")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                HStack(alignment: .center, spacing: 14) {
                    Group {
                        if let poster {
                            Image(uiImage: poster).resizable().scaledToFill()
                        } else {
                            PosterTile(title: film.title, cat: film.category, width: 120)
                        }
                    }
                    .frame(width: 120, height: 174)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(film.title)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        Text(D.fmtCap(plan.d, "EEEE d MMMM"))
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 6) {
                            Text(plan.t).font(.system(size: 26, weight: .black, design: .rounded))
                            if let v = VersionPrefs.label(version) {
                                Text(v).font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.white.opacity(0.2), in: Capsule())
                            }
                        }
                        if let d = film.durationText { Text(d).font(.caption).opacity(0.8) }
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 2) {
                    Text(plan.cn).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.center)
                    if !address.isEmpty { Text(address).font(.caption).opacity(0.85).multilineTextAlignment(.center) }
                }
                Spacer(minLength: 0)
                Text("Sloth Cinema").font(.caption2.weight(.semibold)).opacity(0.7)
            }
            .padding(20)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Invitations between two phones with the app

/// An invitation opened from a slothcinema://invite link a friend sent.
struct ReceivedInvite: Identifiable {
    let id = UUID()
    var filmId: String?     // nil when the film isn't in this phone's list
    var title: String
    var day: String         // yyyy-MM-dd
    var time: String        // HH:mm
    var cinema: String
    var address: String?
    var version: String?
    var from: String        // the sender's first name, from their profile
}

extension Store {
    static let inviteScheme = "slothcinema"

    /// slothcinema://invite?f=…&t=…&d=…&h=…&c=…&a=…&v=…&n=…
    func inviteLink(_ f: Film, _ p: Plan, version: String?, from: String) -> URL? {
        var c = URLComponents()
        c.scheme = Store.inviteScheme
        c.host = "invite"
        var q = [URLQueryItem(name: "f", value: f.id), URLQueryItem(name: "t", value: f.title),
                 URLQueryItem(name: "d", value: p.d), URLQueryItem(name: "h", value: p.t),
                 URLQueryItem(name: "c", value: p.cn)]
        if let a = p.ca, !a.isEmpty { q.append(URLQueryItem(name: "a", value: a)) }
        if let v = version, !v.isEmpty { q.append(URLQueryItem(name: "v", value: v)) }
        let n = from.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { q.append(URLQueryItem(name: "n", value: n)) }
        c.queryItems = q
        return c.url
    }

    func openInvitation(_ url: URL) {
        guard url.scheme?.lowercased() == Store.inviteScheme, url.host?.lowercased() == "invite",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        func value(_ k: String) -> String? {
            guard let v = items.first(where: { $0.name == k })?.value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
            return v
        }
        guard let day = value("d"), let time = value("h"), let cinema = value("c") else { return }
        let title = value("t") ?? ""
        var id: String? = nil
        if let f = value("f"), index[f] != nil { id = f }
        if id == nil, !title.isEmpty { id = matchFilm(title: title, year: "")?.id }
        receivedInvite = ReceivedInvite(filmId: id, title: title, day: day, time: time, cinema: cinema,
                                        address: value("a"), version: value("v"), from: value("n") ?? "")
    }

    /// Plans the film at the invitation's session with the sender as a companion
    /// (or, for a session that has passed, marks it as seen with them).
    func acceptInvitation(_ i: ReceivedInvite, from name: String) {
        guard let id = i.filmId, let f = index[id] else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { addCompanion(n) }
        if i.day < D.today {
            if seen[id] == nil { setSeen(f, rating: 0, on: i.day) }
            if !n.isEmpty {
                var w = seen[id]?.w ?? []
                if !w.contains(n) { w.append(n) }
                setCompanions(id, w)
            }
            return
        }
        planFilm(f, day: i.day, time: i.time, cinemaName: i.cinema)
        if plans[id]?.ca == nil, let a = i.address { plans[id]?.ca = a }
        if !n.isEmpty {
            var w = plans[id]?.w ?? []
            if !w.contains(n) { w.append(n) }
            plans[id]?.w = w
        }
        saveUser()
    }
}

/// What you see when you open a friend's invitation link.
struct InvitationReceivedView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let invite: ReceivedInvite

    @State private var from = ""
    @State private var poster: UIImage?

    private var film: Film? { invite.filmId.flatMap { store.index[$0] } }
    private var past: Bool { invite.day < D.today }
    private var address: String { invite.address ?? store.cinema(named: invite.cinema)?.address ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let f = film {
                        InviteCard(film: f, plan: Plan(d: invite.day, t: invite.time, cn: invite.cinema, ca: invite.address),
                                   address: address, poster: poster, version: invite.version,
                                   accent: Theme.shared.color, deep: Theme.shared.deep)
                            .environment(\.colorScheme, .dark)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(radius: 10)
                            .padding(.horizontal, 40)
                    } else {
                        ContentUnavailableView {
                            Label(invite.title.isEmpty ? String(localized: "A film") : invite.title, systemImage: "film")
                        } description: {
                            Text("\(D.fmtCap(invite.day, "EEEE d MMMM")) at \(invite.time), \(invite.cinema).")
                            Text("This film isn't in the app's list on your phone yet. Refresh the Films tab and open the invitation again.")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invited by").font(.subheadline).foregroundStyle(.secondary)
                        TextField("First name", text: $from)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                        Text("Added to the people you go with, and ticked for this film.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    if film != nil {
                        Button {
                            store.acceptInvitation(invite, from: from)
                            dismiss()
                        } label: {
                            Label(past ? String(localized: "Add to watched") : String(localized: "Add to my week"),
                                  systemImage: past ? "checkmark.circle" : "calendar.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.theme, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 24)
                        if past {
                            Text("This session has passed: it goes into your watched films, seen with them.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                        } else if let p = invite.filmId.flatMap({ store.plans[$0] }), p.d != invite.day || p.t != invite.time || p.cn != invite.cinema {
                            Text("You had planned it for \(D.fmt(p.d, "EEEE d MMMM")) at \(p.t), \(p.cn). This replaces it.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle(invite.from.isEmpty ? String(localized: "You're invited") : String(localized: "\(invite.from) invites you"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .onAppear { if from.isEmpty { from = invite.from } }
            .task {
                guard poster == nil, let s = film?.poster, let url = URL(string: s) else { return }
                let result = try? await URLSession.shared.data(from: url)
                if let data = result?.0 { poster = UIImage(data: data) }
            }
        }
    }
}
