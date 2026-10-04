import Foundation

// Pure, testable helpers for the account screens (auth, onboarding, friends, settings).
// Tested in EklendiTests/AccountTests.swift.

enum AccountValidation {
    static let minPasswordLength: Int = 6
    static let codeLength: Int = 6
    /// Login username length (demo mode: the only login requirement).
    static let usernameLength: Int = 10

    /// The username's digits, without a leading US "1" country code ("+12105550142" →
    /// "2105550142"). Anything else typed in the field is ignored.
    static func demoUsernameDigits(_ input: String) -> String {
        let digits: String = String(input.filter { $0.isNumber })
        if digits.count == usernameLength + 1 && digits.hasPrefix("1") {
            return String(digits.dropFirst())
        }
        return digits
    }

    /// Login check: exactly 10 digits typed in the username field (no country code).
    static func isValidUsername(_ input: String) -> Bool {
        input.filter { $0.isNumber }.count == usernameLength
    }

    /// True when an E.164 number (or raw input) carries a 10-digit username.
    static func isDemoUsername(_ phone: String) -> Bool {
        demoUsernameDigits(phone).count == usernameLength
    }

    /// Normalizes user input to E.164. 10 digits → assumes +1 (US). Accepts "+1 (210) 555-0142",
    /// "1-210-555-0142", "210.555.0142", "+44 20 7946 0958". nil when it doesn't look like a number.
    static func normalizePhone(_ input: String) -> String? {
        let trimmed: String = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let digits: String = String(trimmed.filter { $0.isNumber })
        if trimmed.hasPrefix("+") {
            guard digits.count >= 8 && digits.count <= 15 else { return nil }
            return "+" + digits
        }
        if trimmed.hasPrefix("00") && digits.count >= 10 {
            // International dialing prefix (e.g. 0044…).
            let rest: String = String(digits.dropFirst(2))
            return (rest.count >= 8 && rest.count <= 15) ? "+" + rest : nil
        }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11 && digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    /// User-facing error for a password, or nil when it's fine.
    static func passwordError(_ password: String) -> String? {
        if password.count < minPasswordLength {
            return "Use at least \(minPasswordLength) characters."
        }
        return nil
    }

    /// Strips non-digits (pasted "123 456") and caps at 6.
    static func cleanCode(_ input: String) -> String {
        String(input.filter { $0.isNumber }.prefix(codeLength))
    }

    static func isValidCode(_ input: String) -> Bool {
        let digits: String = String(input.filter { $0.isNumber })
        return digits.count == codeLength
    }

    static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum HomeLocationValidation {
    /// True when the text is only a zip / postal code (5 or 9 digits, "78205-1234").
    static func isZipOnly(_ text: String) -> Bool {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let allowed: Bool = trimmed.allSatisfy { $0.isNumber || $0 == "-" || $0 == " " }
        let digitCount: Int = trimmed.filter { $0.isNumber }.count
        return allowed && digitCount >= 3
    }

    /// Error to show under the home location field, or nil when it's acceptable.
    static func error(_ text: String) -> String? {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Add your approximate home location." }
        if isZipOnly(trimmed) {
            return "A zip code alone isn't precise enough. Try a neighborhood or nearby cross streets."
        }
        if trimmed.count < 3 { return "Add a bit more detail, like a neighborhood." }
        return nil
    }
}

enum BufferSetting {
    static let step: Int = 5
    static let range: ClosedRange<Int> = 0...60
    static let defaultMinutes: Int = 15

    static func increment(_ minutes: Int) -> Int { min(range.upperBound, minutes + step) }
    static func decrement(_ minutes: Int) -> Int { max(range.lowerBound, minutes - step) }

    /// "Class ends at 3:00 PM → earliest hangout starts at 3:15 PM." (design 03).
    static func example(_ minutes: Int) -> String {
        if minutes <= 0 {
            return "No buffer: hangouts can start the minute another event ends."
        }
        return "Class ends at 3:00 PM → earliest hangout starts at \(clock(15 * 60 + minutes))."
    }

    /// Minutes after midnight → "3:15 PM".
    static func clock(_ minutesAfterMidnight: Int) -> String {
        let h: Int = (minutesAfterMidnight / 60) % 24
        let m: Int = minutesAfterMidnight % 60
        let hh: Int = ((h + 11) % 12) + 1
        let mm: String = m < 10 ? "0\(m)" : "\(m)"
        return "\(hh):\(mm) \(h >= 12 ? "PM" : "AM")"
    }
}

enum InterestSuggestions {
    static let all: [String] = ["Coffee shops", "Live music", "Board games", "Hiking", "Trying new restaurants", "Movies"]

    /// Suggestions not already mentioned in the text (case-insensitive).
    static func remaining(for text: String) -> [String] {
        let lower: String = text.lowercased()
        return all.filter { !lower.contains($0.lowercased()) }
    }

    /// Appends a suggestion like the design: "" → "Hiking"; "coffee." → "coffee, hiking".
    static func append(_ suggestion: String, to text: String) -> String {
        var trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return suggestion }
        while let last = trimmed.last, last == "," || last == "." {
            trimmed.removeLast()
        }
        return trimmed + ", " + suggestion.lowercased()
    }
}

enum InviteMessage {
    static let text: String = "Join me on Eklendi so we can plan hangouts without the group-chat back-and-forth."

    /// `sms:` URL that opens Messages with the invite pre-filled.
    static func smsURL(to phoneE164: String) -> URL? {
        let recipient: String = phoneE164.filter { $0.isNumber || $0 == "+" }
        guard !recipient.isEmpty else { return nil }
        var allowed: CharacterSet = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        let body: String = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "sms:\(recipient)&body=\(body)")
    }
}

/// One person picked from iPhone Contacts, reduced to what we need (no other contact data kept).
struct PickedContact: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let phoneNumbers: [String]   // raw strings from Contacts
}

enum ContactMatching {
    /// Unique E.164 numbers for a contact, in their original order.
    static func normalizedNumbers(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for r in raw {
            if let e = AccountValidation.normalizePhone(r), !seen.contains(e) {
                seen.insert(e)
                out.append(e)
            }
        }
        return out
    }
}

enum AccountFormat {
    /// "Seth Fox" → "Seth".
    static func firstName(_ name: String) -> String {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map { String($0) } ?? trimmed
    }

    /// "3:00 – 4:00 PM" (same half of day) or "11:00 AM – 1:00 PM".
    static func timeRange(_ start: Date, _ end: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let sh: Int = cal.component(.hour, from: start)
        let eh: Int = cal.component(.hour, from: end)
        let sameHalf: Bool = (sh < 12) == (eh < 12)
        let s: String = clock(start, cal: cal, withPeriod: !sameHalf)
        let e: String = clock(end, cal: cal, withPeriod: true)
        return "\(s) – \(e)"
    }

    private static func clock(_ date: Date, cal: Calendar, withPeriod: Bool) -> String {
        let h: Int = cal.component(.hour, from: date)
        let m: Int = cal.component(.minute, from: date)
        let hh: Int = ((h + 11) % 12) + 1
        let mm: String = m < 10 ? "0\(m)" : "\(m)"
        return withPeriod ? "\(hh):\(mm) \(h >= 12 ? "PM" : "AM")" : "\(hh):\(mm)"
    }

    /// "Saturday, Oct 3".
    static func longDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    /// "THU".
    static func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    /// "8".
    static func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}
