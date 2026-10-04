import SwiftUI

// MARK: - SectionHeader

/// Uppercase teal label ("COMING UP"). `SectionHeader("Needs your swipes", color: EKColor.yellow)`
struct SectionHeader: View {
    let title: String
    var color: Color = EKColor.teal

    init(_ title: String, color: Color = EKColor.teal) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title.uppercased())
            .font(EKFont.section)
            .tracking(1.0)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - BackButton

/// Top-left chevron arrow (CLAUDE.md: every back-to-home is a top-left arrow).
/// Default action pops the NavigationStack (`dismiss`). `BackButton()` or `BackButton { path.removeLast() }`.
struct BackButton: View {
    var action: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        Button {
            if let action = action { action() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(EKColor.textPrimary)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("backButton")
    }
}

// MARK: - Card

/// Rounded dark container (card fill, 1pt border, 22pt radius, 18pt padding).
/// `Card { Text("Thursday crew") }`; `Card(padding: 0) { rows }`
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = EKRadius.card
    var borderColor: Color = EKColor.cardBorder
    let content: Content

    init(padding: CGFloat = 18, cornerRadius: CGFloat = EKRadius.card, borderColor: Color = EKColor.cardBorder,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(EKColor.card))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(borderColor, lineWidth: 1))
    }
}

// MARK: - Avatar

/// Circle with initials on a palette color, or the photo if `photoURL` loads.
/// `Avatar(name: "Seth Fox", photoURL: user.photoURL, size: 40)`
struct Avatar: View {
    let name: String
    var photoURL: String? = nil
    var size: CGFloat = 40
    /// Optional ring (e.g. teal on time cards, card color on Home tiles).
    var ringColor: Color? = nil

    init(name: String, photoURL: String? = nil, size: CGFloat = 40, ringColor: Color? = nil) {
        self.name = name
        self.photoURL = photoURL
        self.size = size
        self.ringColor = ringColor
    }

    static func initials(for name: String) -> String {
        let parts: [Substring] = name.split(separator: " ")
        let letters: [String] = parts.prefix(2).compactMap { part in part.first.map { String($0) } }
        let joined: String = letters.joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    /// Deterministic palette color for a name (stable across launches).
    static func color(for name: String) -> Color {
        let sum: Int = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let palette: [Color] = EKColor.avatarPalette
        return palette[sum % palette.count]
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(Avatar.color(for: name))
            Text(Avatar.initials(for: name))
                .font(EKFont.inter(size * 0.36, .heavy))
                .foregroundStyle(EKColor.avatarText)
        }
    }

    var body: some View {
        Group {
            if let photoURL = photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(ringColor ?? Color.clear, lineWidth: ringColor == nil ? 0 : 2)
        )
        .accessibilityLabel(name)
    }
}

/// Overlapping row of avatars. `AvatarStack(names: ["Seth", "Matt"], size: 34, ringColor: EKColor.card)`
struct AvatarStack: View {
    let names: [String]
    var size: CGFloat = 34
    var ringColor: Color = EKColor.card
    var maxVisible: Int = 5

    init(names: [String], size: CGFloat = 34, ringColor: Color = EKColor.card, maxVisible: Int = 5) {
        self.names = names
        self.size = size
        self.ringColor = ringColor
        self.maxVisible = maxVisible
    }

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Array(names.prefix(maxVisible).enumerated()), id: \.offset) { pair in
                Avatar(name: pair.element, size: size, ringColor: ringColor)
            }
            if names.count > maxVisible {
                ZStack {
                    Circle().fill(EKColor.raised)
                    Text("+\(names.count - maxVisible)")
                        .font(EKFont.inter(size * 0.34, .bold))
                        .foregroundStyle(EKColor.textPrimary)
                }
                .frame(width: size, height: size)
                .overlay(Circle().stroke(ringColor, lineWidth: 2))
            }
        }
    }
}

// MARK: - Progress

/// Thin teal progress bar with optional counter ("3 of 8").
struct EKProgressBar: View {
    /// 0...1
    let progress: Double
    var label: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(EKColor.raised)
                    Capsule().fill(EKColor.teal)
                        .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                }
            }
            .frame(height: 6)
            if let label = label {
                Text(label)
                    .font(EKFont.caption)
                    .foregroundStyle(EKColor.muted)
            }
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

// MARK: - LoadingView

/// Centered spinner on black. `LoadingView("Finding times…")`
struct LoadingView: View {
    var message: String? = nil

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(EKColor.teal)
                .controlSize(.large)
            if let message = message {
                Text(message)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(EKSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ekScreenBackground()
        .accessibilityIdentifier("loadingView")
    }
}

// MARK: - ErrorBanner

/// Red-tinted inline error. `ErrorBanner(message: err) { err = nil }`
/// Or as an overlay at the top of a screen: `.errorBanner($errorMessage)`.
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(EKColor.dangerText)
            Text(message)
                .font(EKFont.callout)
                .foregroundStyle(EKColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(EKColor.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#3A1416")))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(EKColor.danger.opacity(0.6), lineWidth: 1))
        .accessibilityIdentifier("errorBanner")
    }
}

private struct ErrorBannerModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let text = message {
                ErrorBanner(message: text) { message = nil }
                    .padding(.horizontal, EKSpacing.md)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: message)
    }
}

extension View {
    /// Shows a dismissable ErrorBanner at the top while `message` is non-nil.
    func errorBanner(_ message: Binding<String?>) -> some View {
        modifier(ErrorBannerModifier(message: message))
    }
}

// MARK: - ScreenScaffold

/// Standard screen: optional top-left back arrow + trailing accessory, optional eyebrow
/// (teal section label), large title, optional subtitle, content, and an optional footer
/// pinned to the bottom (usually a PrimaryButton). Hides the system navigation bar.
///
///     ScreenScaffold(title: "Who's coming?", eyebrow: "New hangout", showsBack: true) {
///         ...content...
///     } footer: {
///         PrimaryButton("Continue") { ... }
///     }
struct ScreenScaffold<Content: View, Footer: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var eyebrow: String? = nil
    var showsBack: Bool = false
    var onBack: (() -> Void)? = nil
    var scrolls: Bool = true
    let content: Content
    let footer: Footer
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, eyebrow: String? = nil, showsBack: Bool = false,
         onBack: (() -> Void)? = nil, scrolls: Bool = true,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.showsBack = showsBack
        self.onBack = onBack
        self.scrolls = scrolls
        self.content = content()
        self.footer = footer()
        self.trailing = trailing()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow = eyebrow {
                SectionHeader(eyebrow)
            }
            if !title.isEmpty {
                Text(title)
                    .font(EKFont.title)
                    .foregroundStyle(EKColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(EKFont.inter(16))
                    .foregroundStyle(EKColor.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var body1: some View {
        VStack(alignment: .leading, spacing: EKSpacing.lg) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, EKSpacing.screen)
        .padding(.bottom, EKSpacing.md)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsBack {
                    BackButton(action: onBack)
                }
                Spacer(minLength: 0)
                trailing
            }
            .frame(minHeight: showsBack ? 44 : 8)
            .padding(.horizontal, EKSpacing.screen - 4)

            if scrolls {
                ScrollView {
                    body1.padding(.top, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { floatingFooter }
            } else {
                VStack(spacing: 0) {
                    body1.padding(.top, 4)
                    Spacer(minLength: 0)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { floatingFooter }
            }
        }
        .ekScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .foregroundStyle(EKColor.textPrimary)
    }

    /// The footer floats over the scrolling content (which scrolls up behind it), so the
    /// buttons stay on screen on every phone size.
    @ViewBuilder
    private var floatingFooter: some View {
        if Footer.self != EmptyView.self {
            FloatingFooter { footer }
        }
    }
}

/// Bottom action area layered over scrolling content: a short fade so content scrolling
/// underneath stays readable, then the buttons. Use with `.safeAreaInset(edge: .bottom)`
/// so the scroll view's last item can still scroll above it.
struct FloatingFooter<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, EKSpacing.screen)
                .padding(.top, 10)
                .padding(.bottom, EKSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .background(EKColor.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            LinearGradient(colors: [EKColor.background.opacity(0), EKColor.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
                .offset(y: -24)
                .allowsHitTesting(false)
        }
    }
}

/// Shows `content` at full size when it fits the available height; otherwise scales it
/// down to fit (short phones, large text) so nothing below it is pushed off screen.
struct ShrinkToFit<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScaledToFitHeight(content: content)
        }
    }
}

private struct FitContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScaledToFitHeight<Content: View>: View {
    let content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = (contentHeight > geo.size.height && contentHeight > 0)
                ? geo.size.height / contentHeight : 1
            content
                .frame(width: geo.size.width)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { inner in
                    Color.clear.preference(key: FitContentHeightKey.self, value: inner.size.height)
                })
                .scaleEffect(scale, anchor: .top)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onPreferenceChange(FitContentHeightKey.self) { contentHeight = $0 }
    }
}

extension ScreenScaffold where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, eyebrow: String? = nil, showsBack: Bool = false,
         onBack: (() -> Void)? = nil, scrolls: Bool = true,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.init(title: title, subtitle: subtitle, eyebrow: eyebrow, showsBack: showsBack, onBack: onBack,
                  scrolls: scrolls, content: content, footer: footer, trailing: { EmptyView() })
    }
}

extension ScreenScaffold where Footer == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, eyebrow: String? = nil, showsBack: Bool = false,
         onBack: (() -> Void)? = nil, scrolls: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, eyebrow: eyebrow, showsBack: showsBack, onBack: onBack,
                  scrolls: scrolls, content: content, footer: { EmptyView() }, trailing: { EmptyView() })
    }
}

// MARK: - Previews

#Preview("Scaffold") {
    NavigationStack {
        ScreenScaffold(title: "Who's coming?", subtitle: "Pick 1 to 7 friends.", eyebrow: "New hangout", showsBack: true) {
            Card {
                HStack(spacing: 14) {
                    Avatar(name: "Seth Fox")
                    Text("Seth Fox").font(EKFont.bodyBold)
                }
            }
            AvatarStack(names: ["Zach W", "Seth F", "Matt H", "Claire K", "Ava L", "X Y"], maxVisible: 4)
            EKProgressBar(progress: 0.4, label: "2 of 5")
            ErrorBanner(message: "That code didn't work. Try again.") {}
        } footer: {
            PrimaryButton("Continue") {}
        }
    }
}

#Preview("Loading") {
    LoadingView("Finding times that work…")
}
