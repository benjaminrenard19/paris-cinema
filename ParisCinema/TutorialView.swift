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
        Step(icon: "star.fill", emoji: false, title: "Star what you want to see",
             text: "Tap the star at the top right of any film. A starred film gets a provisional day to go, which you can change."),
        Step(icon: "photo.on.rectangle.angled", emoji: false, title: "Posters and details",
             text: "Tap a poster to see it full screen. Tap or swipe for the running time, critics and audience ratings, the story and the cast."),
        Step(icon: "arrow.up.arrow.down", emoji: false, title: "Sort each week",
             text: "Sort a week by name, critics, audience or average rating, or running time."),
        Step(icon: "calendar", emoji: false, title: "Plan your week",
             text: "On a film or in My week, choose a cinema, then a day, then a time. Plans can go straight into your calendar, Google Calendar included."),
        Step(icon: "bell.badge.fill", emoji: false, title: "After the film",
             text: "When the film should be over, Sloth Cinema asks how it was. Rate it, or pick another day if you didn't go."),
        Step(icon: "map.fill", emoji: false, title: "Your cinemas",
             text: "Star your cinemas so they come first and show today's screenings. Sort cinemas by distance from you or from any place."),
        Step(icon: "checkmark.seal.fill", emoji: false, title: "Your year at the cinema",
             text: "Watched keeps your ratings by year. My list shows films watched and, in brackets, watched plus planned: 25 (28)."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0xA3142F), Color(hex: 0x5E0919)], startPoint: .top, endPoint: .bottom)
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
                        Text(Self.steps[i].title).font(.title.bold()).multilineTextAlignment(.center)
                        Text(Self.steps[i].text).font(.body).multilineTextAlignment(.center).opacity(0.92)
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
                        .foregroundStyle(Color(hex: 0xA3142F))
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
