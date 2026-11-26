import SwiftUI
import UIKit
import Observation

/// The app's colour (Sloth red by default) and light or dark appearance, chosen in Settings › Colours.
@Observable
final class Theme {
    static let shared = Theme()
    static let slothRed: UInt32 = 0xA3142F

    /// Ready-made colours; any other can be picked with the colour wheel.
    static let presets: [(name: String, hex: UInt32)] = [
        ("Sloth red", 0xA3142F), ("Velvet", 0x6B1E3A), ("Popcorn", 0xD98200), ("Neon", 0xE0217A),
        ("Ocean", 0x1F5FBF), ("Forest", 0x1D7A4A), ("Violet", 0x6B3FD6), ("Graphite", 0x4A4A55),
    ]

    var hex: UInt32 {
        didSet { UserDefaults.standard.set(Int(hex), forKey: "accentHex") }
    }

    /// 0: like the iPhone, 1: light, 2: dark.
    var appearance: Int {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }

    private init() {
        let stored = UserDefaults.standard.integer(forKey: "accentHex")
        hex = stored == 0 ? Theme.slothRed : UInt32(truncatingIfNeeded: stored)
        appearance = UserDefaults.standard.integer(forKey: "appearance")
    }

    var color: Color { Color(hex: hex) }

    var scheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    /// A darker shade of the colour, for gradients.
    var deep: Color {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        return Color(red: r * 0.55, green: g * 0.55, blue: b * 0.55)
    }

    /// For the colour wheel.
    var binding: Binding<Color> {
        Binding(get: { self.color }, set: { self.hex = Theme.hex(of: $0) ?? self.hex })
    }

    static func hex(of color: Color) -> UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}

extension Color {
    /// The colour chosen in Settings › Colours.
    static var theme: Color { Theme.shared.color }
}
