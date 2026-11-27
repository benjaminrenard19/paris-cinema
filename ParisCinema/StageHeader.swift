import SwiftUI

/// The top of the Films page: a little theatre stage, red curtains on a black background,
/// a sloth hanging from the curtain rod, and your name.
struct StageHeader: View {
    let name: String
    @AppStorage("animal") private var animal = Animal.sloth
    @AppStorage("animalOnStage") private var animalOnStage = true
    @AppStorage("birthday") private var birthday = ""

    private var mood: StageMood { StageMood.now(birthday: birthday) }

    private var greeting: String {
        if mood == .birthday {
            return name.isEmpty ? String(localized: "Happy birthday!") : String(localized: "Happy birthday, \(name)!")
        }
        let hour = D.cal.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = String(localized: "Good morning")
        case 12..<18: base = String(localized: "Good afternoon")
        default: base = String(localized: "Good evening")
        }
        return name.isEmpty ? base : "\(base), \(name)"
    }

    var body: some View {
        let theme = Theme.shared
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // The dark stage, lit from above.
                LinearGradient(colors: [Color(white: 0.02), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xFFF3C4).opacity(0.28), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42), startRadius: 2, endRadius: w * 0.42)
                // The boards.
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(colors: [Color(hex: 0x4A2512), Color(hex: 0x1E0D05)], startPoint: .top, endPoint: .bottom)
                        .frame(height: h * 0.14)
                }
                // Curtains, drawn back on each side.
                HStack(spacing: 0) {
                    Curtain(left: true).fill(curtainFill(theme)).frame(width: w * 0.25)
                    Spacer(minLength: 0)
                    Curtain(left: false).fill(curtainFill(theme)).frame(width: w * 0.25)
                }
                // Gold tie-backs.
                Circle().fill(Color(hex: 0xE8B931)).frame(width: 9, height: 9).position(x: w * 0.11, y: h * 0.62)
                Circle().fill(Color(hex: 0xE8B931)).frame(width: 9, height: 9).position(x: w * 0.89, y: h * 0.62)
                // The pelmet along the top.
                VStack(spacing: 0) {
                    Valance().fill(LinearGradient(colors: [theme.color, theme.deep], startPoint: .top, endPoint: .bottom))
                        .frame(height: h * 0.17)
                    Rectangle().fill(Color(hex: 0xE8B931).opacity(0.85)).frame(height: 1.5).offset(y: -h * 0.06)
                    Spacer()
                }
                // The curtain rod, with the sloth hanging from the middle.
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xF6D46B), Color(hex: 0xB8871A)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.66, height: 4)
                    .position(x: w / 2, y: h * 0.205)
                ForEach([w * 0.17, w * 0.83], id: \.self) { x in
                    Circle().fill(Color(hex: 0xE8B931)).frame(width: 9, height: 9).position(x: x, y: h * 0.205)
                }
                if animal != Animal.sloth && animalOnStage {
                    HangingAnimal(emoji: animal)
                        .frame(width: 54, height: 64)
                        .position(x: w / 2, y: h * 0.205 - 1 + 30)
                } else {
                    HangingSloth()
                        .frame(width: 54, height: 64)
                        .position(x: w / 2, y: h * 0.205 - 3 + 32)
                }
                // The season (or your birthday) on stage.
                StageEffects(mood: mood, lights: StageMood.isDecember && mood != .birthday)
                // On stage.
                VStack(spacing: 2) {
                    Text(greeting)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, w * 0.25)
                    Text(mood == .birthday ? "🎂 Sloth Cinema 🎈" : "Sloth Cinema")
                        .font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(2.5)
                        .foregroundStyle(Color(hex: 0xE8B931))
                }
                .position(x: w / 2, y: h * 0.69)
            }
        }
        .frame(height: 186)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(greeting)
    }

    /// Velvet folds: alternating light and dark stripes of the app colour.
    private func curtainFill(_ theme: Theme) -> LinearGradient {
        var stops: [Gradient.Stop] = []
        let folds = 5
        for i in 0..<folds {
            let start = Double(i) / Double(folds)
            stops.append(.init(color: theme.deep, location: start))
            stops.append(.init(color: theme.color, location: start + 0.5 / Double(folds)))
        }
        stops.append(.init(color: theme.deep, location: 1))
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

/// One side curtain, gathered towards its tie-back.
struct Curtain: Shape {
    let left: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // Drawn for the left side, mirrored for the right.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: left ? x : w - x, y: y) }
        p.move(to: pt(0, 0))
        p.addLine(to: pt(w, 0))
        p.addCurve(to: pt(w * 0.42, h * 0.62), control1: pt(w * 1.02, h * 0.3), control2: pt(w * 0.55, h * 0.5))
        p.addCurve(to: pt(w * 0.62, h), control1: pt(w * 0.3, h * 0.75), control2: pt(w * 0.5, h * 0.9))
        p.addLine(to: pt(0, h))
        p.closeSubpath()
        return p
    }
}

/// A scalloped pelmet.
struct Valance: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let scallops = 9
        let step = r.width / CGFloat(scallops)
        let base = r.height * 0.55
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: base))
        for i in (0..<scallops).reversed() {
            let x0 = CGFloat(i) * step
            p.addQuadCurve(to: CGPoint(x: x0, y: base), control: CGPoint(x: x0 + step / 2, y: r.height * 1.25))
        }
        p.closeSubpath()
        return p
    }
}

/// A sloth hanging by its arms, swaying a little.
struct HangingSloth: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swing = false

    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let fur = Color(hex: 0x8A6A4F), light = Color(hex: 0xAD8B6D), cream = Color(hex: 0xEDE0CA), dark = Color(hex: 0x38281D)
            func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
            }
            func turned(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ angle: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                    .applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: cx, y: cy))
            }
            // Dangling legs, then the body and its lighter belly.
            ctx.fill(oval(s * 0.37, s * 1.04, s * 0.15, s * 0.2), with: .color(fur))
            ctx.fill(oval(s * 0.63, s * 1.04, s * 0.15, s * 0.2), with: .color(fur))
            ctx.fill(oval(s * 0.5, s * 0.82, s * 0.52, s * 0.52), with: .color(fur))
            ctx.fill(oval(s * 0.5, s * 0.87, s * 0.3, s * 0.34), with: .color(light))
            // Long arms up to the rod.
            var arms = Path()
            arms.move(to: CGPoint(x: s * 0.38, y: s * 0.64))
            arms.addQuadCurve(to: CGPoint(x: s * 0.27, y: s * 0.07), control: CGPoint(x: s * 0.2, y: s * 0.38))
            arms.move(to: CGPoint(x: s * 0.62, y: s * 0.64))
            arms.addQuadCurve(to: CGPoint(x: s * 0.73, y: s * 0.07), control: CGPoint(x: s * 0.8, y: s * 0.38))
            ctx.stroke(arms, with: .color(fur), style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round))
            // Claws hooked over the rod.
            var claws = Path()
            for hx in [s * 0.27, s * 0.73] {
                for dx in [-s * 0.045, 0, s * 0.045] {
                    claws.move(to: CGPoint(x: hx + dx - s * 0.01, y: s * 0.1))
                    claws.addQuadCurve(to: CGPoint(x: hx + dx + s * 0.02, y: s * 0.0), control: CGPoint(x: hx + dx - s * 0.03, y: s * 0.0))
                }
            }
            ctx.stroke(claws, with: .color(cream), style: StrokeStyle(lineWidth: s * 0.028, lineCap: .round))
            // Head and face mask.
            ctx.fill(oval(s * 0.5, s * 0.5, s * 0.48, s * 0.41), with: .color(light))
            ctx.fill(oval(s * 0.5, s * 0.53, s * 0.37, s * 0.27), with: .color(cream))
            // The dark stripes that run back from the eyes.
            ctx.fill(turned(s * 0.405, s * 0.515, s * 0.15, s * 0.075, -0.38), with: .color(dark))
            ctx.fill(turned(s * 0.595, s * 0.515, s * 0.15, s * 0.075, 0.38), with: .color(dark))
            for ex in [s * 0.425, s * 0.575] {
                ctx.fill(oval(ex, s * 0.508, s * 0.045, s * 0.045), with: .color(.black))
                ctx.fill(oval(ex + s * 0.008, s * 0.5, s * 0.016, s * 0.016), with: .color(.white))
            }
            // Nose and a small smile.
            ctx.fill(oval(s * 0.5, s * 0.572, s * 0.075, s * 0.048), with: .color(dark))
            var smile = Path()
            smile.move(to: CGPoint(x: s * 0.46, y: s * 0.608))
            smile.addQuadCurve(to: CGPoint(x: s * 0.54, y: s * 0.608), control: CGPoint(x: s * 0.5, y: s * 0.645))
            ctx.stroke(smile, with: .color(dark), style: StrokeStyle(lineWidth: s * 0.02, lineCap: .round))
        }
        .rotationEffect(.degrees(swing ? 3 : -3), anchor: UnitPoint(x: 0.5, y: 0.05))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { swing = true }
        }
        .accessibilityHidden(true)
    }
}
