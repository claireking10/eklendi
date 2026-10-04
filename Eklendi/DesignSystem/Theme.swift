import SwiftUI
import CoreText

// Design tokens for Eklendi (from docs/design/*.dc.html). The app is dark-only.
// Usage: `.foregroundStyle(EKColor.teal)`, `.font(EKFont.title)`, `.padding(EKSpacing.screen)`.

extension Color {
    /// `Color(hex: "#00C3D0")` or `Color(hex: "00C3D0")`. Supports RRGGBB and AARRGGBB.
    init(hex: String) {
        var cleaned: String = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let a: Double
        let r: Double
        let g: Double
        let b: Double
        if cleaned.count == 8 {
            a = Double((value >> 24) & 0xFF) / 255.0
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum EKColor {
    // Surfaces
    static let background = Color(hex: "#000000")
    static let card = Color(hex: "#162022")
    static let cardBorder = Color(hex: "#243133")
    /// Border of swipe cards (slightly lighter than cardBorder).
    static let swipeCardBorder = Color(hex: "#2A3739")
    /// Raised controls inside cards (steppers, small buttons, progress track).
    static let raised = Color(hex: "#1E2B2D")
    static let raisedBorder = Color(hex: "#2C3A3C")
    static let divider = Color(hex: "#3A4A4C")
    static let sheet = Color(hex: "#0E1617")

    // Brand
    static let teal = Color(hex: "#00C3D0")
    static let tealPressed = Color(hex: "#2BD3DE")
    /// Text/icons on top of teal (buttons, selected chips, badges): white.
    static let onTeal = Color(hex: "#FFFFFF")
    static let yellow = Color(hex: "#FFCC00")
    static let purple = Color(hex: "#CB30E0")
    static let blue = Color(hex: "#6E8BFF")

    // Text
    static let textPrimary = Color(hex: "#FFFFFF")
    static let textSecondary = Color(hex: "#E8ECEC")
    static let muted = Color(hex: "#A3AFB1")
    static let placeholder = Color(hex: "#8A9799")
    static let body = Color(hex: "#C9D2D3")

    // Status
    static let danger = Color(hex: "#E5484D")
    static let dangerText = Color(hex: "#FF8A8A")

    // Votes (swipe glow + buttons). Yes = teal glow, Maybe = white glow, No = shadow from top-left.
    static let yesGlow = Color(hex: "#00C3D0")
    static let maybeGlow = Color(hex: "#FFFFFF")
    static let noRing = Color(hex: "#E8ECEC")
    static let maybeRing = Color(hex: "#FFCC00")

    // Pills / tallies
    static let pillTealBg = Color(hex: "#24484B")
    static let pillTealFg = Color(hex: "#CFF6F8")
    static let pillYellowBg = Color(hex: "#4A3F12")
    static let pillYellowFg = Color(hex: "#FFE58A")
    static let pillGrayBg = Color(hex: "#2A3436")
    static let pillGrayFg = Color(hex: "#E8ECEC")

    /// Avatar background palette (text on top is #0B0B0B).
    static let avatarPalette: [Color] = [
        Color(hex: "#E8ECEC"), Color(hex: "#FFCC00"), Color(hex: "#CB30E0"),
        Color(hex: "#6E8BFF"), Color(hex: "#00C3D0"), Color(hex: "#FF8A5B"),
    ]
    static let avatarText = Color(hex: "#0B0B0B")
}

/// Bundled fonts (Eklendi/Resources/Fonts): Inter for all text, Outfit ExtraBold for the
/// "eklendi" logo (both SIL OFL). Registered at runtime, so no Info.plist entry is needed.
/// Missing files fall back to the system font.
enum EKFontRegistry {
    /// PostScript names of every bundled font that registered.
    static let names: Set<String> = registerBundledFonts()

    /// The logo font (nil if the file isn't bundled).
    static var logoFontName: String? {
        names.contains("Outfit-ExtraBold") ? "Outfit-ExtraBold" : nil
    }

    private static func registerBundledFonts() -> Set<String> {
        var urls: [URL] = []
        for ext in ["ttf", "otf"] {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
        }
        var out: Set<String> = []
        for url in urls {
            guard let provider = CGDataProvider(url: url as CFURL),
                  let cgFont = CGFont(provider),
                  let cfName = cgFont.postScriptName else { continue }
            let name: String = cfName as String
            // Already registered (e.g. a second call) is fine; we only need the name.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            out.insert(name)
        }
        return out
    }
}

enum EKFont {
    /// Inter at a size and weight (falls back to the system font if Inter isn't bundled).
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .black: name = "Inter-Black"
        case .heavy: name = "Inter-ExtraBold"
        case .bold: name = "Inter-Bold"
        case .semibold: name = "Inter-SemiBold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        guard EKFontRegistry.names.contains(name) else { return .system(size: size, weight: weight) }
        return .custom(name, size: size)
    }

    /// "eklendi" logo in Outfit ExtraBold (system rounded heavy if the font is missing).
    static func logo(_ size: CGFloat) -> Font {
        if let name = EKFontRegistry.logoFontName {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .heavy, design: .rounded)
    }

    /// "eklendi" wordmark.
    static var wordmark: Font { logo(30) }
    static var largeTitle: Font { inter(34, .bold) }
    /// Screen titles (28 bold in the design).
    static var title: Font { inter(28, .bold) }
    static var title2: Font { inter(24, .bold) }
    static var headline: Font { inter(18, .bold) }
    static var button: Font { inter(17, .bold) }
    static var body: Font { inter(17) }
    static var bodyBold: Font { inter(17, .semibold) }
    static var callout: Font { inter(15) }
    static var calloutBold: Font { inter(15, .bold) }
    static var caption: Font { inter(13, .semibold) }
    /// Uppercase teal section labels ("COMING UP").
    static var section: Font { inter(13, .bold) }
    /// Huge weekday on time-slot cards.
    static var display: Font { inter(46, .black) }
}

enum EKSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    /// Horizontal screen padding.
    static let screen: CGFloat = 24
}

enum EKRadius {
    static let small: CGFloat = 12
    static let field: CGFloat = 18
    static let button: CGFloat = 16
    static let card: CGFloat = 22
    static let swipeCard: CGFloat = 28
}

extension View {
    /// Black full-screen background used by every screen.
    func ekScreenBackground() -> some View {
        self.background(EKColor.background.ignoresSafeArea())
    }
}
