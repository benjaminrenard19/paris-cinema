import SwiftUI
import UIKit

/// "Would you join me…?": a picture of the poster with the plan, and the sentence, to send in any app.
struct InviteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
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
                        if let image {
                            ShareLink(item: image, subject: Text(f.title), message: Text(sentence),
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
                        ShareLink(item: sentence) {
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
