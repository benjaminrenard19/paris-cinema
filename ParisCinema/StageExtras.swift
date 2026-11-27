import SwiftUI

// MARK: - Your animal, your birthday, and the stage through the seasons

/// Your animal: your profile picture and, if you like, it hangs from the curtain rod instead of the sloth.
enum Animal {
    static let all = ["🦥", "🐼", "🦊", "🐨", "🐯", "🦁", "🐸", "🐵", "🐧", "🦉", "🐙", "🐶", "🐱", "🐰", "🦄", "🐢", "🦦", "🐻"]
    static let sloth = "🦥"
}

/// The stage's mood: the season, December lights, or your birthday party.
enum StageMood: Equatable {
    case winter, spring, summer, autumn, birthday

    /// Your birthday is "MM-dd" (no year), empty when you haven't said.
    static func now(birthday: String, date: Date = Date()) -> StageMood {
        if !birthday.isEmpty, birthday == String(D.str(date).suffix(5)) { return .birthday }
        switch D.cal.component(.month, from: date) {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .autumn
        }
    }

    static var isDecember: Bool { D.cal.component(.month, from: Date()) == 12 }
}

/// Light effects on the stage: snow, spring petals, summer fireflies, autumn maple leaves falling
/// from the top of the curtain, confetti on your birthday, and string lights in December.
/// A few particles drawn on a Canvas, 30 times a second; still when Reduce Motion is on.
struct StageEffects: View {
    let mood: StageMood
    var lights = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas { ctx, size in
                let t = reduceMotion ? 4.0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                draw(&ctx, size, t)
                if lights { drawLights(&ctx, size, t) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A stable pseudo-random number in 0..<1 for particle i.
    private func r(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i * 127 + k * 311) * 12.9898) * 43758.5453
        return x - floor(x)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        switch mood {
        case .winter:
            for i in 0..<22 {
                let speed = 10 + r(i, 1) * 14, x0 = r(i, 2) * w, d = 2 + r(i, 3) * 2.5
                let y = (t * speed + r(i, 4) * h).truncatingRemainder(dividingBy: h + 10) - 5
                let x = x0 + sin(t * 0.8 + r(i, 5) * 6) * 8
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(0.55 + r(i, 6) * 0.4)))
            }
        case .spring:
            for i in 0..<14 {
                let speed = 8 + r(i, 1) * 10, x0 = r(i, 2) * w
                let y = (t * speed + r(i, 4) * h).truncatingRemainder(dividingBy: h + 12) - 6
                let x = x0 + sin(t * 0.7 + r(i, 5) * 6) * 14
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * 0.9 + r(i, 6) * 6))
                let pink = i % 2 == 0 ? Color(hex: 0xFFB7C9) : Color(hex: 0xFFE3EC)
                c.fill(Path(ellipseIn: CGRect(x: -4, y: -2.5, width: 8, height: 5)), with: .color(pink.opacity(0.9)))
            }
        case .summer:
            for i in 0..<12 {
                let x = r(i, 2) * w + sin(t * 0.35 + r(i, 5) * 6) * 18
                let y = h * (0.35 + r(i, 3) * 0.5) + cos(t * 0.3 + r(i, 4) * 6) * 10
                let glow = max(0, sin(t * (1.2 + r(i, 6)) + r(i, 7) * 6))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)),
                         with: .color(Color(hex: 0xFFD60A).opacity(0.18 * glow)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)),
                         with: .color(Color(hex: 0xFFF3A0).opacity(0.25 + 0.75 * glow)))
            }
        case .autumn:
            let leaf = ctx.resolve(Text("🍁").font(.system(size: 13)))
            for i in 0..<9 {
                let speed = 12 + r(i, 1) * 12, x0 = r(i, 2) * w
                let y = (t * speed + r(i, 4) * h).truncatingRemainder(dividingBy: h + 16) - 8
                let x = x0 + sin(t * 0.9 + r(i, 5) * 6) * 16
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(sin(t * 1.3 + r(i, 6) * 6) * 0.9))
                let s = 0.7 + r(i, 7) * 0.5
                c.scaleBy(x: s, y: s)
                c.draw(leaf, at: .zero)
            }
        case .birthday:
            let colors: [Color] = [Color(hex: 0xFF453A), Color(hex: 0xFFD60A), Color(hex: 0x30D158), Color(hex: 0x0A84FF),
                                   Color(hex: 0xBF5AF2), .white]
            for i in 0..<26 {
                let speed = 18 + r(i, 1) * 22, x0 = r(i, 2) * w
                let y = (t * speed + r(i, 4) * h).truncatingRemainder(dividingBy: h + 10) - 5
                let x = x0 + sin(t * 1.4 + r(i, 5) * 6) * 10
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(t * (2 + r(i, 6) * 3)))
                let rect = i % 3 == 0 ? CGRect(x: -2, y: -2, width: 4, height: 4) : CGRect(x: -3, y: -1.2, width: 6, height: 2.4)
                c.fill(i % 3 == 0 ? Path(ellipseIn: rect) : Path(rect), with: .color(colors[i % colors.count]))
            }
        }
    }

    /// A string of little bulbs along the bottom of the pelmet, twinkling.
    private func drawLights(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, y0 = size.height * 0.135
        let colors: [Color] = [Color(hex: 0xFF453A), Color(hex: 0xFFD60A), Color(hex: 0x30D158), Color(hex: 0x64D2FF)]
        var wire = Path()
        let n = 15
        for i in 0...n {
            let x = w * (0.04 + 0.92 * Double(i) / Double(n))
            let y = y0 + sin(Double(i) / Double(n) * .pi * 3) * 3
            if i == 0 { wire.move(to: CGPoint(x: x, y: y)) } else { wire.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(wire, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
        for i in 0..<n {
            let x = w * (0.04 + 0.92 * (Double(i) + 0.5) / Double(n))
            let y = y0 + sin((Double(i) + 0.5) / Double(n) * .pi * 3) * 3 + 2.5
            let on = 0.45 + 0.55 * max(0, sin(t * 2.2 + Double(i) * 1.7))
            let c = colors[i % colors.count]
            ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(c.opacity(0.25 * on)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2.6, width: 4, height: 5.2)), with: .color(c.opacity(on)))
        }
    }
}

/// Your animal hanging from the curtain rod by two little paws, swaying like the sloth.
struct HangingAnimal: View {
    let emoji: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swing = false

    var body: some View {
        VStack(spacing: -6) {
            Canvas { ctx, size in
                var arms = Path()
                arms.move(to: CGPoint(x: size.width * 0.3, y: 1))
                arms.addLine(to: CGPoint(x: size.width * 0.38, y: size.height))
                arms.move(to: CGPoint(x: size.width * 0.7, y: 1))
                arms.addLine(to: CGPoint(x: size.width * 0.62, y: size.height))
                ctx.stroke(arms, with: .color(Color(hex: 0xE8B931)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 40, height: 16)
            Text(emoji).font(.system(size: 38))
        }
        .rotationEffect(.degrees(swing ? 4 : -4), anchor: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { swing = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Choosing them (first launch and My profile)

/// Pick your animal, whether it replaces the sloth on the stage, and your birthday.
struct AnimalAndBirthdayFields: View {
    @AppStorage("animal") private var animal = Animal.sloth
    @AppStorage("animalOnStage") private var onStage = true
    @AppStorage("birthday") private var birthday = ""

    var body: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                ForEach(Animal.all, id: \.self) { a in
                    Button { animal = a } label: {
                        Text(a).font(.system(size: 30))
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(a == animal ? Color.theme.opacity(0.25) : Color.secondary.opacity(0.1)))
                            .overlay(Circle().stroke(a == animal ? Color.theme : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(a == animal ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            if animal != Animal.sloth {
                Toggle("Hang it from the curtain rod instead of the sloth", isOn: $onStage)
            }
        } header: {
            Text("Your animal")
        } footer: {
            Text("It's your profile picture, and it can take the sloth's place on the stage of the Films page.")
        }
        Section {
            Toggle("Tell Sloth Cinema my birthday", isOn: Binding(get: { !birthday.isEmpty }, set: { birthday = $0 ? (birthday.isEmpty ? "01-01" : birthday) : "" }))
            if !birthday.isEmpty {
                HStack {
                    Picker("Day", selection: part(day: true)) {
                        ForEach(1...31, id: \.self) { d in Text(String(d)).tag(d) }
                    }
                    Picker("Month", selection: part(day: false)) {
                        ForEach(1...12, id: \.self) { m in Text(D.fmtCap(String(format: "2026-%02d-01", m), "LLLL")).tag(m) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        } header: {
            Text("Your birthday")
        } footer: {
            Text("That day, the stage throws you a party. No year needed.")
        }
    }

    /// Day or month of "MM-dd" as a number.
    private func part(day: Bool) -> Binding<Int> {
        Binding(get: {
            let bits = birthday.split(separator: "-").compactMap { Int($0) }
            guard bits.count == 2 else { return 1 }
            return day ? bits[1] : bits[0]
        }, set: { v in
            let bits = birthday.split(separator: "-").compactMap { Int($0) }
            var m = bits.count == 2 ? bits[0] : 1, d = bits.count == 2 ? bits[1] : 1
            if day { d = v } else { m = v }
            let maxDay = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
            birthday = String(format: "%02d-%02d", m, min(d, maxDay))
        })
    }
}
