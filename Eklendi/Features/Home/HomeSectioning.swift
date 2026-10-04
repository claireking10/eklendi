import Foundation

/// Where a hangout shows up on Home (04).
enum HomeSection: Int, CaseIterable, Comparable, Sendable {
    case needsAction, inProgress, upcoming, past, hidden

    static func < (lhs: HomeSection, rhs: HomeSection) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .needsAction: return "Needs your swipes"
        case .inProgress: return "In progress"
        case .upcoming: return "Coming up"
        case .past: return "Past hangouts"
        case .hidden: return ""
        }
    }
}

/// What a Home tile says about a hangout. Pure, tested in AccountTests.
struct HomeTileInfo: Equatable, Sendable {
    let section: HomeSection
    /// Short, one-line status, e.g. "Times to swipe".
    let status: String
    /// Trailing call to action ("Swipe", "Join"), nil when nothing to do.
    let action: String?
}

enum HomeSectioning {
    /// Classifies a hangout for the signed-in user. `me` is the user's member doc (nil while loading).
    static func info(for hangout: Hangout, me: HangoutMember?, myUid: String, ownerName: String?,
                     now: Date = Date()) -> HomeTileInfo {
        if let me = me, me.state == .declined || me.state == .removed {
            return HomeTileInfo(section: .hidden, status: "", action: nil)
        }
        switch hangout.status {
        case .collectingAvailability:
            if me?.state == .invited {
                return HomeTileInfo(section: .needsAction, status: "New invite", action: "Join")
            }
            if let me = me, !me.availabilitySubmitted {
                return HomeTileInfo(section: .needsAction, status: "Share when you’re free", action: "Start")
            }
            return HomeTileInfo(section: .inProgress, status: "Waiting for everyone’s calendars", action: nil)

        case .votingTimes:
            if let me = me, me.state == .invited || !me.timesDone {
                return HomeTileInfo(section: .needsAction, status: "Times to swipe", action: "Swipe")
            }
            return HomeTileInfo(section: .inProgress, status: "Waiting for others to swipe times", action: nil)

        case .noMutualTime:
            return HomeTileInfo(section: .needsAction, status: "No time works for everyone", action: "Pick")

        case .survey:
            if let me = me, !me.surveyDone {
                return HomeTileInfo(section: .needsAction, status: "Quick activity survey", action: "Swipe")
            }
            return HomeTileInfo(section: .inProgress, status: "Waiting for everyone’s survey", action: nil)

        case .generating:
            return HomeTileInfo(section: .inProgress, status: "Finding hangout ideas…", action: nil)

        case .votingCards:
            if let me = me, me.cardsDoneRound < hangout.round {
                return HomeTileInfo(section: .needsAction, status: "Hangout ideas to swipe", action: "Swipe")
            }
            return HomeTileInfo(section: .inProgress, status: "Waiting for others to swipe ideas", action: nil)

        case .noAgreement:
            return HomeTileInfo(section: .needsAction, status: "Not everyone agrees", action: "Swipe")

        case .confirmed:
            let end: Date = hangout.confirmed?.end ?? hangout.winningSlot?.end ?? now
            if end < now {
                return HomeTileInfo(section: .past, status: "Done", action: nil)
            }
            if me?.notGoing == true {
                return HomeTileInfo(section: .upcoming, status: "You’re not going", action: nil)
            }
            return HomeTileInfo(section: .upcoming, status: "Confirmed", action: nil)

        case .cancelled:
            return HomeTileInfo(section: .hidden, status: "Cancelled", action: nil)
        }
    }

    static func startedBy(hangout: Hangout, myUid: String, ownerName: String?) -> String {
        if hangout.ownerId == myUid { return "started by you" }
        let first: String = AccountFormat.firstName(ownerName ?? "")
        return first.isEmpty ? "started by a friend" : "started by \(first)"
    }

    /// Tile title: the confirmed title, the time-only plan, or "Seth's hangout".
    static func title(for hangout: Hangout, myUid: String, ownerName: String?) -> String {
        let t: String = hangout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let plan: String = hangout.planDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if hangout.mode == .timeOnly && !plan.isEmpty { return plan }
        if hangout.ownerId == myUid { return "Your hangout" }
        let first: String = AccountFormat.firstName(ownerName ?? "")
        return first.isEmpty ? "New hangout" : "\(first)’s hangout"
    }

    /// Members who are going (active and not marked "no longer available").
    static func goingCount(_ members: [HangoutMember]) -> Int {
        members.filter { $0.state == .active && !$0.notGoing }.count
    }

    /// Start used for sorting / the date tile.
    static func startDate(_ hangout: Hangout) -> Date? {
        hangout.confirmed?.start ?? hangout.winningSlot?.start
    }

    /// Sort within a section: upcoming soonest first, past most recent first, others newest first.
    static func sorted(_ list: [Hangout], in section: HomeSection) -> [Hangout] {
        switch section {
        case .upcoming:
            return list.sorted { (startDate($0) ?? .distantFuture) < (startDate($1) ?? .distantFuture) }
        case .past:
            return list.sorted { (startDate($0) ?? .distantPast) > (startDate($1) ?? .distantPast) }
        default:
            return list.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
}
