import SwiftUI

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
    /// Text/icons on top of teal.
    static let onTeal = Color(hex: "#00282B")
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

enum EKFont {
    /// "eklendi" wordmark.
    static let wordmark: Font = .system(size: 30, weight: .heavy, design: .rounded)
    static let largeTitle: Font = .system(size: 34, weight: .bold)
    /// Screen titles (28 bold in the design).
    static let title: Font = .system(size: 28, weight: .bold)
    static let title2: Font = .system(size: 24, weight: .bold)
    static let headline: Font = .system(size: 18, weight: .bold)
    static let button: Font = .system(size: 17, weight: .bold)
    static let body: Font = .system(size: 17, weight: .regular)
    static let bodyBold: Font = .system(size: 17, weight: .semibold)
    static let callout: Font = .system(size: 15, weight: .regular)
    static let calloutBold: Font = .system(size: 15, weight: .bold)
    static let caption: Font = .system(size: 13, weight: .semibold)
    /// Uppercase teal section labels ("COMING UP").
    static let section: Font = .system(size: 13, weight: .bold)
    /// Huge weekday on time-slot cards.
    static let display: Font = .system(size: 46, weight: .black)
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
