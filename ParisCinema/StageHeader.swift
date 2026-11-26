import SwiftUI

/// The top of the Films page: a little theatre stage, red curtains on a black background,
/// with the sloth, the theatre masks and your name.
struct StageHeader: View {
    let name: String

    private var greeting: String {
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
                // On stage.
                VStack(spacing: 2) {
                    Text("🦥🎭").font(.system(size: min(54, h * 0.3)))
                    Text(greeting)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, w * 0.25)
                    Text("Sloth Cinema")
                        .font(.caption2.weight(.semibold)).textCase(.uppercase).tracking(2.5)
                        .foregroundStyle(Color(hex: 0xE8B931))
                }
                .offset(y: h * 0.04)
            }
        }
        .frame(height: 172)
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
