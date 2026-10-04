import SwiftUI
import PhotosUI
import UIKit

// Building blocks shared by onboarding (03 / 03a) and Settings (04b).

// MARK: - Local profile photo (no upload for the hackathon)

/// Stores the profile picture on this device only (Documents/profile-<uid>.jpg).
/// `UserProfile.photoURL` is left untouched, so friends see initials.
enum AccountPhotoStore {
    static func fileURL(uid: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let safe: String = String(uid.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        return dir.appendingPathComponent("profile-\(safe).jpg")
    }

    static func load(uid: String) -> UIImage? {
        guard let url = fileURL(uid: uid), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Downscales to ≤ 600px and saves as JPEG. Returns the image to display.
    @discardableResult
    static func save(_ data: Data, uid: String) -> UIImage? {
        guard let original = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 600
        let size: CGSize = original.size
        let scale: CGFloat = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized: UIImage = renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: target))
        }
        if let url = fileURL(uid: uid), let jpeg = resized.jpegData(compressionQuality: 0.8) {
            try? jpeg.write(to: url, options: .atomic)
        }
        return resized
    }

    static func remove(uid: String) {
        guard let url = fileURL(uid: uid) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Round avatar: the local photo if set, otherwise initials.
struct AccountAvatar: View {
    let name: String
    let image: UIImage?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Avatar(name: name.isEmpty ? "?" : name, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Avatar with a small camera badge; tapping opens the photo picker.
struct ProfilePhotoPickerButton: View {
    let uid: String
    let name: String
    @Binding var image: UIImage?
    var size: CGFloat = 72

    @State private var item: PhotosPickerItem? = nil

    init(uid: String, name: String, image: Binding<UIImage?>, size: CGFloat = 72) {
        self.uid = uid
        self.name = name
        self._image = image
        self.size = size
    }

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                AccountAvatar(name: name, image: image, size: size)
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(EKColor.onTeal)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(EKColor.teal))
                    .overlay(Circle().stroke(EKColor.background, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change profile picture")
        .accessibilityIdentifier("profilePhotoButton")
        .onChange(of: item) { _, newItem in
            guard let newItem = newItem else { return }
            Task { @MainActor in
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    image = AccountPhotoStore.save(data, uid: uid)
                }
            }
        }
    }
}

// MARK: - Buffer stepper

/// "− 15 min +" card with the live example line (design 03 / 04b).
struct AccountBufferStepper: View {
    @Binding var minutes: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    stepButton(systemImage: "minus", label: "Shorter buffer", id: "bufferMinus") {
                        minutes = BufferSetting.decrement(minutes)
                    }
                    .disabled(minutes <= BufferSetting.range.lowerBound)
                    Spacer()
                    Text("\(minutes) min")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(EKColor.textPrimary)
                        .monospacedDigit()
                        .accessibilityIdentifier("bufferValue")
                    Spacer()
                    stepButton(systemImage: "plus", label: "Longer buffer", id: "bufferPlus") {
                        minutes = BufferSetting.increment(minutes)
                    }
                    .disabled(minutes >= BufferSetting.range.upperBound)
                }
                Text(BufferSetting.example(minutes))
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepButton(systemImage: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(EKColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: EKRadius.small, style: .continuous).fill(EKColor.raised))
                .overlay(RoundedRectangle(cornerRadius: EKRadius.small, style: .continuous).stroke(EKColor.raisedBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Calendar row

/// Calendar connection row: date badge, name + status, and a switch-looking button.
struct AccountCalendarRow: View {
    let name: String
    let isConnected: Bool
    var isComingSoon: Bool = false
    var isBusy: Bool = false
    var accessibilityId: String
    let action: () -> Void

    private var status: String {
        if isComingSoon { return "Coming soon" }
        return isConnected ? "Connected · reading busy times" : "Not connected"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(AccountFormat.weekdayShortMonth(Date()))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(EKColor.danger)
                Text(AccountFormat.dayNumber(Date()))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: "#0B0B0B"))
            }
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .opacity(isComingSoon ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(EKFont.bodyBold)
                    .foregroundStyle(EKColor.textPrimary)
                Text(status)
                    .font(.system(size: 14))
                    .foregroundStyle(isConnected ? EKColor.teal : EKColor.muted)
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().tint(EKColor.teal)
            } else {
                Button(action: action) {
                    ZStack(alignment: isConnected ? .trailing : .leading) {
                        Capsule().fill(isConnected ? EKColor.teal : EKColor.divider)
                            .frame(width: 51, height: 31)
                        Circle().fill(Color.white)
                            .frame(width: 27, height: 27)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: isConnected)
                }
                .buttonStyle(.plain)
                .disabled(isComingSoon)
                .opacity(isComingSoon ? 0.4 : 1)
                .accessibilityLabel(name)
                .accessibilityValue(isConnected ? "On" : "Off")
                .accessibilityIdentifier(accessibilityId)
            }
        }
        .padding(.vertical, 12)
    }
}

extension AccountFormat {
    /// "OCT".
    static func weekdayShortMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Home location field

struct AccountHomeLocationField: View {
    @Binding var text: String
    var error: String? = nil
    var accessibilityId: String = "homeLocationField"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EKTextField("Neighborhood or nearest cross streets", text: $text, systemImage: "mappin.and.ellipse",
                        accessibilityId: accessibilityId)
            if let error = error {
                Text(error)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Close enough to find places near you. No exact address needed.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Interests editor

struct AccountInterestsEditor: View {
    @Binding var text: String
    var accessibilityId: String = "interestsField"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EKTextField("e.g. trying new coffee shops, board game cafés, hiking on weekends, anything with tacos",
                        text: $text, kind: .multiline, accessibilityId: accessibilityId)
            let ideas: [String] = InterestSuggestions.remaining(for: text)
            if !ideas.isEmpty {
                SectionHeader("Need a nudge? Tap to add", color: EKColor.muted)
                FlowLayout(spacing: 8) {
                    ForEach(ideas, id: \.self) { idea in
                        Chip(idea, style: .suggestion) {
                            text = InterestSuggestions.append(idea, to: text)
                        }
                        .accessibilityIdentifier("interestChip_\(idea)")
                    }
                }
            }
        }
    }
}
