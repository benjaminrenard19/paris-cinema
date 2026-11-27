import SwiftUI

/// Shown on first launch. Skip it at any time; it can be shown again from Settings.
struct TutorialView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct Step {
        let icon: String
        let emoji: Bool
        let title: String
        let text: String
    }

    private static let steps: [Step] = [
        Step(icon: "🦥", emoji: true, title: "Welcome to Sloth Cinema",
             text: "Every film released in Paris cinemas this year, week by week. New films, posters and showtimes arrive by themselves."),
        Step(icon: "popcorn.fill", emoji: false, title: "Add what you want to see to OTW",
             text: "Tap the popcorn at the top right of any film to add it to One To Watch. It gets a provisional day to go, which you can change."),
        Step(icon: "photo.on.rectangle.angled", emoji: false, title: "Posters and details",
             text: "Tap a poster to see it full screen. Tap or swipe for the running time, critics and audience ratings, the story and the cast."),
        Step(icon: "arrow.up.arrow.down", emoji: false, title: "Sort each week",
             text: "Sort a week by name, critics, audience or average rating, or running time."),
        Step(icon: "calendar", emoji: false, title: "Plan your week",
             text: "Choose a film and a cinema: Sloth Cinema shows its first session. No session that day? It offers the next one there, or another cinema, your favourites first. Plans can go straight into your calendar."),
        Step(icon: "🧠", emoji: true, title: "It learns your habits",
             text: "The more you use it, the better it knows when and where you like to go, and suggests sessions to match."),
        Step(icon: "bell.badge.fill", emoji: false, title: "After the film",
             text: "When the film should be over, Sloth Cinema asks how it was. Rate it, or pick another day if you didn't go."),
        Step(icon: "map.fill", emoji: false, title: "Your cinemas",
             text: "Star your cinemas so they come first and show today's screenings. Sort cinemas by distance from you or from any place."),
        Step(icon: "checkmark.seal.fill", emoji: false, title: "Your year at the cinema",
             text: "Watched keeps your ratings by year. My list shows films watched and, in brackets, watched plus planned: 25 (28)."),
        Step(icon: "📊", emoji: true, title: "Your stats, as a story",
             text: "The button at the top of Films sums up your month with fun facts, ready to share on Instagram. Swipe back through past months and years."),
        Step(icon: "🎥", emoji: true, title: "What's new",
             text: "The camera at the top right gathers films to rate, today's plans and your OTW films on today. Settings let you choose your colour."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Theme.shared.color, Theme.shared.deep], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Self.steps.indices, id: \.self) { i in
                    VStack(spacing: 22) {
                        Spacer()
                        if Self.steps[i].emoji {
                            Text(Self.steps[i].icon).font(.system(size: 110))
                        } else {
                            Image(systemName: Self.steps[i].icon).font(.system(size: 76, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xFFD23F))
                        }
                        Text(LocalizedStringKey(Self.steps[i].title)).font(.title.bold()).multilineTextAlignment(.center)
                        Text(LocalizedStringKey(Self.steps[i].text)).font(.body).multilineTextAlignment(.center).opacity(0.92)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack {
                Spacer()
                Button {
                    if page >= Self.steps.count - 1 { onDone() } else { withAnimation { page += 1 } }
                } label: {
                    Text(page >= Self.steps.count - 1 ? "Start" : "Next")
                        .font(.headline)
                        .foregroundStyle(Theme.shared.color)
                        .frame(minWidth: 180)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .padding(.bottom, 56)
            }
            .frame(maxWidth: .infinity)

            Button("Skip") { onDone() }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(20)
        }
    }
}
