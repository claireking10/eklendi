import SwiftUI

// Buttons. Two ways to use them:
//   PrimaryButton("Continue", systemImage: "plus", isLoading: busy) { ... }
//   Button("Continue") { ... }.buttonStyle(PrimaryButtonStyle())

/// Full-width teal button, 56pt tall, dark text.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EKFont.button)
            .foregroundStyle(EKColor.onTeal)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: EKRadius.button, style: .continuous)
                    .fill(configuration.isPressed ? EKColor.tealPressed : EKColor.teal)
            )
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Full-width dark button with a subtle border, white text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EKFont.button)
            .foregroundStyle(EKColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: EKRadius.button, style: .continuous)
                    .fill(configuration.isPressed ? EKColor.raisedBorder : EKColor.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EKRadius.button, style: .continuous)
                    .stroke(EKColor.raisedBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Full-width red button for destructive actions (Decline, Delete account, Cancel hangout).
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EKFont.button)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EKColor.danger.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
            .opacity(isEnabled ? 1.0 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Inline teal text button ("Redo my swipes", "Skip for now"). Min 44pt tap target.
struct LinkButtonStyle: ButtonStyle {
    var color: Color = EKColor.teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EKFont.calloutBold)
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Convenience wrapper around PrimaryButtonStyle with optional icon and loading spinner.
/// While `isLoading` is true the button is disabled and shows a spinner.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(EKColor.onTeal)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .bold))
                }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }
}

/// Convenience wrapper around SecondaryButtonStyle.
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(EKColor.textPrimary)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .bold))
                }
                Text(title)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: 12) {
        PrimaryButton("Plan a hangout", systemImage: "plus") {}
        PrimaryButton("Loading", isLoading: true) {}
        SecondaryButton("Keep me in") {}
        Button("Decline") {}.buttonStyle(DestructiveButtonStyle())
        Button("Skip for now") {}.buttonStyle(LinkButtonStyle())
    }
    .padding(24)
    .ekScreenBackground()
}
