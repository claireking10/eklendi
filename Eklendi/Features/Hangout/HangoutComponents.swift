import SwiftUI

// Small building blocks shared by the hangout screens.

/// Eyebrow + title + optional subtitle (same styling as ScreenScaffold's header), for
/// screens that lay themselves out without ScreenScaffold (swipe screens).
@MainActor
struct HFHeader: View {
    let eyebrow: String?
    let title: String
    var subtitle: String? = nil

    init(eyebrow: String?, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow = eyebrow {
                SectionHeader(eyebrow)
            }
            Text(title)
                .font(EKFont.title)
                .foregroundStyle(EKColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Teal-tinted info banner ("We'll look for times over the next 2 weeks…").
@MainActor
struct HFInfoBanner: View {
    let text: String
    var systemImage: String = "info.circle"
    var tint: Color = EKColor.teal
    var background: Color = Color(hex: "#13292B")
    var border: Color = Color(hex: "#1F4A4D")
    var foreground: Color = EKColor.pillTealFg

    init(_ text: String, systemImage: String = "info.circle", tint: Color = EKColor.teal,
         background: Color = Color(hex: "#13292B"), border: Color = Color(hex: "#1F4A4D"),
         foreground: Color = EKColor.pillTealFg) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.background = background
        self.border = border
        self.foreground = foreground
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(foreground)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(border, lineWidth: 1))
    }
}

/// Big selectable option card with an icon and a radio dot (Plan / Origin screens).
@MainActor
struct HFRadioOption: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? EKColor.teal : EKColor.raised)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? EKColor.onTeal : EKColor.textSecondary)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(EKColor.textPrimary)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(EKColor.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(isSelected ? EKColor.teal : EKColor.divider, lineWidth: 2)
                    if isSelected {
                        Circle().fill(EKColor.teal).frame(width: 12, height: 12)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color(hex: "#13292B") : EKColor.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? EKColor.teal : EKColor.raisedBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Square checkbox used in multi-select rows.
@MainActor
struct HFCheckBox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? EKColor.teal : Color.clear)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isOn ? EKColor.teal : Color(hex: "#4A5B5D"), lineWidth: 2)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(EKColor.onTeal)
            }
        }
        .frame(width: 26, height: 26)
    }
}

/// Bottom sheet "Decline this hangout?" (KAL-21).
@MainActor
struct HFDeclineSheet: View {
    let hangoutName: String
    let ownerFirstName: String
    let isWorking: Bool
    let onKeep: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Decline this hangout?")
                .font(EKFont.title2)
                .foregroundStyle(EKColor.textPrimary)
            Text("You’ll be removed from \(hangoutName), and \(ownerFirstName) will see that you declined. The others can keep planning without you.")
                .font(EKFont.callout)
                .foregroundStyle(EKColor.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Keep me in", action: onKeep)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("keepMeInButton")
                Button(action: onDecline) {
                    HStack(spacing: 8) {
                        if isWorking { ProgressView().tint(Color.white) }
                        Text("Decline")
                    }
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("confirmDeclineButton")
            }
            .padding(.top, 6)
        }
        .padding(EKSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EKColor.sheet.ignoresSafeArea())
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(EKColor.sheet)
    }
}

/// Owner hand-off picker (KAL-47).
@MainActor
struct HFHandOffSheet: View {
    let candidates: [HangoutMember]
    let onPick: (HangoutMember) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hand off ownership")
                .font(EKFont.title2)
                .foregroundStyle(EKColor.textPrimary)
            Text("The new owner can nudge, remove, cancel and reopen. You stay in the hangout.")
                .font(EKFont.callout)
                .foregroundStyle(EKColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if candidates.isEmpty {
                Text("There’s nobody else in the hangout yet.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.placeholder)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(candidates) { m in
                            Button {
                                onPick(m)
                            } label: {
                                HStack(spacing: 14) {
                                    Avatar(name: m.name, size: 40)
                                    Text(m.name)
                                        .font(EKFont.bodyBold)
                                        .foregroundStyle(EKColor.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(EKColor.placeholder)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("handOff_\(m.id)")
                            if m.id != candidates.last?.id {
                                Rectangle().fill(EKColor.cardBorder).frame(height: 1)
                            }
                        }
                    }
                }
            }
            Button("Not now", action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(EKSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EKColor.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(EKColor.sheet)
    }
}

/// Background for hangout cards: the Places photo, or a category-tinted gradient.
@MainActor
struct HFVenueBackground: View {
    let photoUrl: String?
    let category: String

    static func gradientColors(for category: String) -> [Color] {
        switch category.lowercased() {
        case "food": return [Color(hex: "#2A4A4E"), Color(hex: "#13292B")]
        case "active": return [Color(hex: "#3A3358"), Color(hex: "#1D1A2E")]
        case "games": return [Color(hex: "#4A3A22"), Color(hex: "#251D11")]
        case "arts": return [Color(hex: "#4A2A4E"), Color(hex: "#241326")]
        case "nature": return [Color(hex: "#3B4A22"), Color(hex: "#1C2410")]
        case "markets": return [Color(hex: "#4E3A2A"), Color(hex: "#271D15")]
        default: return [Color(hex: "#24484B"), Color(hex: "#0E1617")]
        }
    }

    private var gradient: some View {
        LinearGradient(colors: HFVenueBackground.gradientColors(for: category),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Color.clear
            .overlay {
                if let photoUrl = photoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            gradient
                        }
                    }
                } else {
                    gradient
                }
            }
            .clipped()
    }
}

/// Generic centered status screen (cancelled, not a member, generating).
@MainActor
struct HFStatusView: View {
    let systemImage: String
    let title: String
    let message: String
    var showsSpinner: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            if showsSpinner {
                ProgressView()
                    .tint(EKColor.teal)
                    .controlSize(.large)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(EKColor.teal)
            }
            Text(title)
                .font(EKFont.title2)
                .foregroundStyle(EKColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(EKFont.callout)
                .foregroundStyle(EKColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, EKSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
