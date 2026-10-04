import SwiftUI

/// Kind of text input.
enum EKFieldKind {
    case text
    /// Phone keypad, `.telephoneNumber` content type. Pair with `PhoneFormat.e164(from:)`.
    case phone
    /// SecureField (passwords) with a show/hide eye toggle.
    case secure
    /// Number pad, one-time-code content type (SMS code).
    case code
    /// Multi-line text (interests). Grows 4–8 lines.
    case multiline
}

/// Dark rounded input (card fill, 1pt border, 56pt tall), optional leading label.
/// `EKTextField("Name", text: $name)`
/// `EKTextField("(210) 555-0142", text: $phone, kind: .phone, label: "Phone")`
/// `EKTextField("Password", text: $pw, kind: .secure)`
struct EKTextField: View {
    let placeholder: String
    @Binding var text: String
    var kind: EKFieldKind = .text
    var label: String? = nil
    var systemImage: String? = nil
    var accessibilityId: String? = nil

    @State private var revealed: Bool = false

    init(_ placeholder: String, text: Binding<String>, kind: EKFieldKind = .text,
         label: String? = nil, systemImage: String? = nil, accessibilityId: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.kind = kind
        self.label = label
        self.systemImage = systemImage
        self.accessibilityId = accessibilityId
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(EKColor.placeholder)
    }

    @ViewBuilder
    private var input: some View {
        switch kind {
        case .text:
            TextField("", text: $text, prompt: prompt)
                .textInputAutocapitalization(.words)
        case .phone:
            TextField("", text: $text, prompt: prompt)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
        case .code:
            TextField("", text: $text, prompt: prompt)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        case .secure:
            if revealed {
                TextField("", text: $text, prompt: prompt)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } else {
                SecureField("", text: $text, prompt: prompt)
            }
        case .multiline:
            TextField("", text: $text, prompt: prompt, axis: .vertical)
                .lineLimit(4...8)
        }
    }

    var body: some View {
        HStack(alignment: kind == .multiline ? .top : .center, spacing: 12) {
            if let label = label {
                Text(label)
                    .font(EKFont.inter(15))
                    .foregroundStyle(EKColor.muted)
                    .frame(width: 72, alignment: .leading)
            }
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(EKColor.placeholder)
            }
            input
                .font(EKFont.body)
                .foregroundStyle(EKColor.textPrimary)
                .tint(EKColor.teal)
                .accessibilityIdentifier(accessibilityId ?? placeholder)
            if kind == .secure {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .foregroundStyle(EKColor.placeholder)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, kind == .multiline ? 16 : 0)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: EKRadius.field, style: .continuous).fill(EKColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EKRadius.field, style: .continuous).stroke(EKColor.cardBorder, lineWidth: 1)
        )
    }
}

/// Phone field with a fixed "+1" prefix (US numbers for the demo).
/// `EKPhoneField(text: $digits)`; convert with `PhoneFormat.e164(from: digits)`.
struct EKPhoneField: View {
    @Binding var text: String
    var placeholder: String = "(210) 555-0142"
    var accessibilityId: String = "phoneField"

    var body: some View {
        HStack(spacing: 12) {
            Text("+1")
                .font(EKFont.body)
                .foregroundStyle(EKColor.textPrimary)
            Rectangle().fill(EKColor.raisedBorder).frame(width: 1, height: 28)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(EKColor.placeholder))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(EKFont.body)
                .foregroundStyle(EKColor.textPrimary)
                .tint(EKColor.teal)
                .accessibilityIdentifier(accessibilityId)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: EKRadius.field, style: .continuous).fill(EKColor.card))
        .overlay(RoundedRectangle(cornerRadius: EKRadius.field, style: .continuous).stroke(EKColor.cardBorder, lineWidth: 1))
    }
}

/// Password field: `EKSecureField("Password", text: $pw)` (same as EKTextField kind .secure).
struct EKSecureField: View {
    let placeholder: String
    @Binding var text: String
    var accessibilityId: String? = nil

    init(_ placeholder: String, text: Binding<String>, accessibilityId: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.accessibilityId = accessibilityId
    }

    var body: some View {
        EKTextField(placeholder, text: $text, kind: .secure, accessibilityId: accessibilityId)
    }
}

enum PhoneFormat {
    /// Digits only.
    static func digits(_ s: String) -> String {
        String(s.filter { $0.isNumber })
    }

    /// "(210) 555-0142" → "+12105550142". Accepts 10 digits (adds +1), 11 digits starting
    /// with 1, or an already "+"-prefixed number. Returns nil if it doesn't look valid.
    static func e164(from input: String) -> String? {
        let trimmed: String = input.trimmingCharacters(in: .whitespaces)
        let d: String = digits(trimmed)
        if trimmed.hasPrefix("+") {
            return d.count >= 8 ? "+" + d : nil
        }
        if d.count == 10 { return "+1" + d }
        if d.count == 11 && d.hasPrefix("1") { return "+" + d }
        return nil
    }

    /// "+12105550142" → "(210) 555-0142" (US); other numbers returned unchanged.
    static func display(_ e164: String) -> String {
        let d: String = digits(e164)
        guard d.count == 11, d.hasPrefix("1") else { return e164 }
        let chars: [Character] = Array(d.dropFirst())
        let area = String(chars[0..<3])
        let mid = String(chars[3..<6])
        let last = String(chars[6..<10])
        return "(\(area)) \(mid)-\(last)"
    }
}

private struct FieldsPreviewDemo: View {
    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var pw: String = ""
    @State private var notes: String = ""
    var body: some View {
        VStack(spacing: 12) {
            EKTextField("Your first name", text: $name)
            EKPhoneField(text: $phone)
            EKSecureField("Password", text: $pw)
            EKTextField("Tacos, live music, hiking…", text: $notes, kind: .multiline)
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .ekScreenBackground()
    }
}

#Preview {
    FieldsPreviewDemo()
}
