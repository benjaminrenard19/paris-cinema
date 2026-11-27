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
        didSet {
            UserDefaults.standard.set(Int(hex), forKey: "accentHex")
            scheduleIcon()
        }
    }

    @ObservationIgnored private var iconTask: Task<Void, Never>?

    /// The app icon follows the colour, a moment after the last change (the colour wheel sends many),
    /// since iOS shows a short notice each time the icon changes.
    func scheduleIcon() {
        iconTask?.cancel()
        let name = Theme.iconName(for: hex)
        iconTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            let app = UIApplication.shared
            guard app.supportsAlternateIcons, app.alternateIconName != name else { return }
            app.setAlternateIconName(name) { _ in }
        }
    }

    /// The icon for a colour: the preset nearest to it (nil is the main, Sloth red icon).
    /// The icons are made by scripts/icons.py, named AppIcon-<preset name>.
    static func iconName(for hex: UInt32) -> String? {
        func parts(_ h: UInt32) -> (Int, Int, Int) { (Int((h >> 16) & 0xFF), Int((h >> 8) & 0xFF), Int(h & 0xFF)) }
        func distance(_ a: UInt32, _ b: UInt32) -> Int {
            let x = parts(a), y = parts(b)
            return (x.0 - y.0) * (x.0 - y.0) + (x.1 - y.1) * (x.1 - y.1) + (x.2 - y.2) * (x.2 - y.2)
        }
        guard let best = presets.min(by: { distance($0.hex, hex) < distance($1.hex, hex) }), best.hex != slothRed else { return nil }
        return "AppIcon-" + best.name.replacingOccurrences(of: " ", with: "")
    }

    /// 0: like the iPhone, 1: light, 2: dark.
    var appearance: Int {
        didSet {
            UserDefaults.standard.set(appearance, forKey: "appearance")
            apply()
        }
    }

    /// Sets light, dark or automatic on the app's windows. (SwiftUI's preferredColorScheme
    /// doesn't go back to automatic once light or dark has been set, so the window's own
    /// style is used instead.) Call on the main thread.
    func apply() {
        let style: UIUserInterfaceStyle = appearance == 1 ? .light : appearance == 2 ? .dark : .unspecified
        MainActor.assumeIsolated {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                for window in scene.windows { window.overrideUserInterfaceStyle = style }
            }
        }
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
