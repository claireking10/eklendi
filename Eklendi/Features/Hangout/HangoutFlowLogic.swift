import Foundation

// Pure, testable helpers for the hangout flow (routing, formatting, tallies, durations,
// day-view math, small local persistence). No SwiftUI here. Tests: EklendiTests/HangoutTests.swift.

// MARK: - Errors

/// Simple readable error for the hangout screens.
struct HFError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Routing

/// Which screen HangoutFlowView shows.
enum HFScreen: Equatable {
    case loading
    case notMember          // declined / removed / never in it
    case join               // invited → Join / Decline (KAL-21)
    case availability       // starting point (time+activity) then calendar upload (KAL-20)
    case waiting            // screen 10
    case swipeTimes         // screen 08
    case noMutualTime       // screen 08b
    case survey             // screen 09
    case generating
    case cards              // screen 11
    case noAgreement        // screen 11a
    case confirmed          // screen 12
    case cancelled
}

enum HFRouting {
    /// Routes by hangout status and the signed-in member's own progress.
    static func screen(hangout: Hangout?, me: HangoutMember?, membersLoaded: Bool) -> HFScreen {
        guard let h = hangout else { return .loading }
        if h.status == .cancelled { return .cancelled }
        guard let me = me else { return membersLoaded ? .notMember : .loading }
        if me.state == .declined || me.state == .removed { return .notMember }
        if me.state == .invited { return .join }
        switch h.status {
        case .collectingAvailability:
            return me.availabilitySubmitted ? .waiting : .availability
        case .votingTimes:
            return me.timesDone ? .waiting : .swipeTimes
        case .noMutualTime:
            return .noMutualTime
        case .survey:
            return me.surveyDone ? .waiting : .survey
        case .generating:
            return .generating
        case .votingCards:
            return me.cardsDoneRound >= h.round ? .waiting : .cards
        case .noAgreement:
            return .noAgreement
        case .confirmed:
            return .confirmed
        case .cancelled:
            return .cancelled
        }
    }

    /// Members who still count for "everyone" gates: active + invited (invited = pending).
    static func countable(_ members: [HangoutMember]) -> [HangoutMember] {
        members.filter { $0.state == .active || $0.state == .invited }
    }

    /// Whether a member finished the current step (for the waiting screen).
    static func stepDone(_ m: HangoutMember, hangout: Hangout) -> Bool {
        if m.state == .invited { return false }
        switch hangout.status {
        case .collectingAvailability: return m.availabilitySubmitted
        case .votingTimes: return m.timesDone
        case .survey: return m.surveyDone
        case .votingCards: return m.cardsDoneRound >= hangout.round
        default: return true
        }
    }

    /// Short name of the current step ("Picking a time").
    static func stepName(_ status: HangoutStatus) -> String {
        switch status {
        case .collectingAvailability: return "Sharing calendars"
        case .votingTimes: return "Picking a time"
        case .noMutualTime: return "Picking a time"
        case .survey: return "Activity questions"
        case .generating: return "Finding ideas"
        case .votingCards: return "Voting on ideas"
        case .noAgreement: return "Round results"
        case .confirmed: return "Confirmed"
        case .cancelled: return "Cancelled"
        }
    }

    /// "Step 1 of 3" style label (time-only hangouts have a single step).
    static func stepLabel(_ status: HangoutStatus, mode: HangoutMode) -> String {
        if mode == .timeOnly { return "Pick a time" }
        switch status {
        case .collectingAvailability, .votingTimes, .noMutualTime: return "Step 1 of 3"
        case .survey: return "Step 2 of 3"
        case .generating, .votingCards, .noAgreement, .confirmed: return "Step 3 of 3"
        case .cancelled: return "Cancelled"
        }
    }

    /// Headline for the waiting screen given the names (first names) still pending.
    static func waitingHeadline(pendingNames: [String]) -> String {
        switch pendingNames.count {
        case 0: return "Everyone’s in."
        case 1: return "Waiting on \(pendingNames[0])."
        case 2: return "Waiting on \(pendingNames[0]) and \(pendingNames[1])."
        default: return "Waiting on \(pendingNames.count) people."
        }
    }
}

// MARK: - Formatting

enum HFFormat {
    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// "3:00 PM"
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("h:mm a", timeZone).string(from: date)
    }

    /// "3:00 – 4:00 PM", or "11:00 AM – 1:00 PM" when the halves differ.
    static func timeRange(_ start: Date, _ end: Date, timeZone: TimeZone = .current) -> String {
        let a: String = formatter("a", timeZone).string(from: start)
        let b: String = formatter("a", timeZone).string(from: end)
        let endText: String = time(end, timeZone: timeZone)
        if a == b {
            let startText: String = formatter("h:mm", timeZone).string(from: start)
            return "\(startText) – \(endText)"
        }
        return "\(time(start, timeZone: timeZone)) – \(endText)"
    }

    /// Compact "3p" / "3:30p" (day view labels).
    static func shortTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let cal = calendar(timeZone)
        let minute: Int = cal.component(.minute, from: date)
        let hourText: String = formatter("h", timeZone).string(from: date)
        let suffix: String = cal.component(.hour, from: date) >= 12 ? "p" : "a"
        return minute == 0 ? "\(hourText)\(suffix)" : "\(hourText):\(String(format: "%02d", minute))\(suffix)"
    }

    /// Hour label for the day view grid: "9a", "12p".
    static func hourLabel(_ hour: Int) -> String {
        let h12: Int = ((hour + 11) % 12) + 1
        return "\(h12)\(hour >= 12 && hour < 24 ? "p" : "a")"
    }

    /// "THURSDAY"
    static func weekdayUpper(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("EEEE", timeZone).string(from: date).uppercased()
    }

    /// "October 8th"
    static func monthDayOrdinal(_ date: Date, timeZone: TimeZone = .current) -> String {
        let month: String = formatter("MMMM", timeZone).string(from: date)
        let day: Int = calendar(timeZone).component(.day, from: date)
        return "\(month) \(ordinal(day))"
    }

    /// "Thursday, October 8"
    static func longDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("EEEE, MMMM d", timeZone).string(from: date)
    }

    /// "Thursday, Oct 8"
    static func dayHeader(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("EEEE, MMM d", timeZone).string(from: date)
    }

    /// "Thu, Oct 8 · 3:00 – 4:00 PM"
    static func shortWhen(_ start: Date, _ end: Date, timeZone: TimeZone = .current) -> String {
        "\(formatter("EEE, MMM d", timeZone).string(from: start)) · \(timeRange(start, end, timeZone: timeZone))"
    }

    /// "Thu 3:00 PM"
    static func shortDayTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        "\(formatter("EEE", timeZone).string(from: date)) \(time(date, timeZone: timeZone))"
    }

    static func ordinal(_ n: Int) -> String {
        let mod100: Int = n % 100
        if mod100 >= 11 && mod100 <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// 30 → "30 min", 60 → "1 hr", 90 → "1 hr 30 min", 240 → "4 hr".
    static func durationLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h: Int = minutes / 60
        let m: Int = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    static func durationLabel(_ start: Date, _ end: Date) -> String {
        durationLabel(minutes: max(0, Int((end.timeIntervalSince(start) / 60).rounded())))
    }

    /// 0 → "Free", 1 → "$", 3 → "$$$"; nil → nil.
    static func priceLabel(_ level: Int?) -> String? {
        guard let level = level else { return nil }
        if level <= 0 { return "Free" }
        return String(repeating: "$", count: min(level, 4))
    }

    /// 0.62 → "0.6 mi", 12.4 → "12 mi"; nil → nil.
    static func distanceLabel(_ miles: Double?) -> String? {
        guard let miles = miles, miles >= 0 else { return nil }
        if miles >= 10 { return "\(Int(miles.rounded())) mi" }
        return String(format: "%.1f mi", miles)
    }

    static func firstName(_ name: String) -> String {
        let trimmed: String = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.split(separator: " ").first else { return trimmed.isEmpty ? "Someone" : trimmed }
        return String(first)
    }

    /// ["Seth", "Matt", "Mark"] → "Seth, Matt and Mark".
    static func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head: String = names.dropLast().joined(separator: ", ")
            return "\(head) and \(names[names.count - 1])"
        }
    }

    /// "two", "three"… for small group sizes ("both" handled by callers).
    static func numberWord(_ n: Int) -> String {
        let words: [String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight"]
        return n >= 0 && n < words.count ? words[n] : "\(n)"
    }

    /// Hangout name for headers: confirmed title, else "Seth’s hangout" / "Your hangout".
    static func displayName(hangout: Hangout, members: [HangoutMember], myUid: String) -> String {
        let title: String = hangout.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        if hangout.mode == .timeOnly {
            let plan: String = hangout.planDescription.trimmingCharacters(in: .whitespaces)
            if !plan.isEmpty { return plan }
        }
        if hangout.ownerId == myUid { return "Your hangout" }
        if let owner = members.first(where: { $0.id == hangout.ownerId }), !owner.name.isEmpty {
            return "\(firstName(owner.name))’s hangout"
        }
        return "Hangout"
    }

    /// "You" for the signed-in user, else the first name.
    static func shortName(_ member: HangoutMember, myUid: String) -> String {
        member.id == myUid ? "You" : firstName(member.name)
    }
}

// MARK: - Vote tallies

struct HFTally: Equatable {
    var yes: Int = 0
    var maybe: Int = 0
    var no: Int = 0

    /// "2 yes · 1 maybe · 1 no" (zero maybe/no parts omitted).
    var label: String {
        var parts: [String] = ["\(yes) yes"]
        if maybe > 0 { parts.append("\(maybe) maybe") }
        if no > 0 { parts.append("\(no) no") }
        return parts.joined(separator: " · ")
    }
}

enum HFTallies {
    /// Counts of one person's votes (the "Times are in" pills).
    static func counts(_ votes: [String: Vote]) -> HFTally {
        var t = HFTally()
        for v in votes.values {
            switch v {
            case .yes: t.yes += 1
            case .maybe: t.maybe += 1
            case .no: t.no += 1
            }
        }
        return t
    }

    /// Tally for one option. Voters with no recorded vote count as "no" (they didn't agree).
    static func tally(optionId: String, votes: [String: [String: Vote]], voters: [String]) -> HFTally {
        var t = HFTally()
        for voter in voters {
            switch votes[voter]?[optionId] {
            case .some(.yes): t.yes += 1
            case .some(.maybe): t.maybe += 1
            default: t.no += 1
            }
        }
        return t
    }

    /// CLAUDE.md "Deciding a winner": options with yes from everyone; else options where everyone
    /// said yes or maybe; best = most yes, fewest maybe, earliest start. nil if nothing passes.
    static func winner(optionIds: [String], startOf: (String) -> Date,
                       votes: [String: [String: Vote]], voters: [String]) -> String? {
        guard !voters.isEmpty else { return nil }
        let allYes: [String] = optionIds.filter { tally(optionId: $0, votes: votes, voters: voters).yes == voters.count }
        let pool: [String] = allYes.isEmpty
            ? optionIds.filter { tally(optionId: $0, votes: votes, voters: voters).no == 0 }
            : allYes
        let sorted: [String] = pool.sorted { a, b in
            let ta: HFTally = tally(optionId: a, votes: votes, voters: voters)
            let tb: HFTally = tally(optionId: b, votes: votes, voters: voters)
            if ta.yes != tb.yes { return ta.yes > tb.yes }
            if ta.maybe != tb.maybe { return ta.maybe < tb.maybe }
            return startOf(a) < startOf(b)
        }
        return sorted.first
    }

    /// Top options for 11a "Not everyone agrees": most yes, then most maybe, then earliest.
    static func topOptions(optionIds: [String], startOf: (String) -> Date,
                           votes: [String: [String: Vote]], voters: [String], limit: Int = 3) -> [String] {
        let sorted: [String] = optionIds.sorted { a, b in
            let ta: HFTally = tally(optionId: a, votes: votes, voters: voters)
            let tb: HFTally = tally(optionId: b, votes: votes, voters: voters)
            if ta.yes != tb.yes { return ta.yes > tb.yes }
            if ta.maybe != tb.maybe { return ta.maybe > tb.maybe }
            let sa: Date = startOf(a)
            let sb: Date = startOf(b)
            if sa != sb { return sa < sb }
            return a < b
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}

// MARK: - Durations (screen 06)

enum HFDurations {
    static let presetMinutes: [Int] = [30, 60, 120, 180]
    static let customRange: ClosedRange<Int> = 1...12
    static let defaultCustomHours: Int = 4

    static func clampCustom(_ hours: Int) -> Int {
        min(customRange.upperBound, max(customRange.lowerBound, hours))
    }

    /// Selected durations in minutes (sorted, unique). "I don't care" → [] (server picks).
    static func minutes(presets: Set<Int>, customOn: Bool, customHours: Int, any: Bool) -> [Int] {
        if any { return [] }
        var all: Set<Int> = presets.filter { $0 > 0 }
        if customOn { all.insert(clampCustom(customHours) * 60) }
        return all.sorted()
    }

    static func isValid(presets: Set<Int>, customOn: Bool, any: Bool) -> Bool {
        any || customOn || !presets.isEmpty
    }

    /// "Any length", "1 hr, 2 hr, 4 hr" or "Pick one".
    static func summary(presets: Set<Int>, customOn: Bool, customHours: Int, any: Bool) -> String {
        if any { return "Any length" }
        let list: [Int] = minutes(presets: presets, customOn: customOn, customHours: customHours, any: false)
        if list.isEmpty { return "Pick one" }
        return list.map { HFFormat.durationLabel(minutes: $0) }.joined(separator: ", ")
    }
}

// MARK: - Day view math (screen 08a)

/// One person's column in the day view.
struct HFLane: Equatable {
    var uid: String
    var name: String
    var busy: [BusyBlock]
    var bufferMinutes: Int
}

enum HFDayMath {
    /// Snap minutes to the nearest `step`.
    static func snap(_ minutes: Double, step: Int = 15) -> Int {
        let s: Double = Double(max(1, step))
        return Int((minutes / s).rounded()) * Int(s)
    }

    /// Keeps a block of `duration` minutes inside [dayStart, dayEnd] (minutes from midnight).
    static func clampStart(_ start: Int, duration: Int, dayStart: Int, dayEnd: Int) -> Int {
        let latest: Int = max(dayStart, dayEnd - duration)
        return min(latest, max(dayStart, start))
    }

    /// Names (as given in lanes) of people busy during [start, end), counting their buffers.
    static func clashes(start: Date, end: Date, lanes: [HFLane]) -> [String] {
        var out: [String] = []
        for lane in lanes {
            let pad: TimeInterval = TimeInterval(max(0, lane.bufferMinutes) * 60)
            let hit: Bool = lane.busy.contains { b in
                start < b.end.addingTimeInterval(pad) && end > b.start.addingTimeInterval(-pad)
            }
            if hit { out.append(lane.name) }
        }
        return out
    }

    /// "Everyone’s free", "Matt is busy", "Seth and Matt are busy".
    static func statusText(clashNames: [String]) -> String {
        if clashNames.isEmpty { return "Everyone’s free" }
        if clashNames.count == 1 {
            return clashNames[0] == "You" ? "You’re busy" : "\(clashNames[0]) is busy"
        }
        return "\(HFFormat.joinNames(clashNames)) are busy"
    }

    /// Busy blocks clipped to one calendar day, as (startMinute, endMinute) from midnight.
    static func dayBlocks(_ busy: [BusyBlock], day: Date, calendar: Calendar) -> [(start: Int, end: Int)] {
        let dayStart: Date = calendar.startOfDay(for: day)
        guard let dayEnd: Date = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        var out: [(start: Int, end: Int)] = []
        for b in busy where b.end > dayStart && b.start < dayEnd {
            let s: Date = max(b.start, dayStart)
            let e: Date = min(b.end, dayEnd)
            let sm: Int = Int(s.timeIntervalSince(dayStart) / 60)
            let em: Int = Int(e.timeIntervalSince(dayStart) / 60)
            if em > sm { out.append((start: sm, end: em)) }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Date for `minutes` after the start of `day`.
    static func date(day: Date, minutes: Int, calendar: Calendar) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Minutes from midnight of `date` on its own day.
    static func minutesIntoDay(_ date: Date, calendar: Calendar) -> Int {
        Int(date.timeIntervalSince(calendar.startOfDay(for: date)) / 60)
    }
}

// MARK: - Small local persistence (UserDefaults)

/// Remembers per-device facts the backend doesn't expose to the client:
/// which time slots I already swiped (so a suggested time only asks for the new card) and
/// the calendar event I added for a confirmed hangout (added once, removed on cancel/reopen).
enum HFLocalStore {
    private static var defaults: UserDefaults { UserDefaults.standard }

    private static func votedKey(_ hangoutId: String, _ uid: String) -> String {
        "ek.votedSlots.\(hangoutId).\(uid)"
    }

    private static func eventKey(_ hangoutId: String) -> String {
        "ek.calendarEvent.\(hangoutId)"
    }

    static func votedSlotIds(hangoutId: String, uid: String) -> Set<String> {
        Set(defaults.stringArray(forKey: votedKey(hangoutId, uid)) ?? [])
    }

    static func addVotedSlotIds(_ ids: [String], hangoutId: String, uid: String) {
        var all: Set<String> = votedSlotIds(hangoutId: hangoutId, uid: uid)
        for id in ids { all.insert(id) }
        defaults.set(Array(all).sorted(), forKey: votedKey(hangoutId, uid))
    }

    static func clearVotedSlotIds(hangoutId: String, uid: String) {
        defaults.removeObject(forKey: votedKey(hangoutId, uid))
    }

    /// Stored as "<start epoch seconds>|<event identifier>" so a reopened hangout with a new
    /// time gets a fresh event.
    static func calendarEvent(hangoutId: String) -> (start: Double, identifier: String)? {
        guard let raw = defaults.string(forKey: eventKey(hangoutId)) else { return nil }
        let parts: [Substring] = raw.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let start = Double(String(parts[0])) else { return nil }
        return (start: start, identifier: String(parts[1]))
    }

    static func setCalendarEvent(hangoutId: String, start: Date, identifier: String) {
        defaults.set("\(start.timeIntervalSince1970)|\(identifier)", forKey: eventKey(hangoutId))
    }

    static func clearCalendarEvent(hangoutId: String) {
        defaults.removeObject(forKey: eventKey(hangoutId))
    }
}
