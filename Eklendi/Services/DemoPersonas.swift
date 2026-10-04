import Foundation

/// Demo mode: fixed choices for the seeded friends, so the signed-in user's swipes are
/// compared against realistic, different preferences instead of being copied.
///
/// Every combination of friends has at least two time slots and several card options that
/// nobody vetoes, so a winner is always reachable when the user says yes or maybe to them.
/// Saying no to everything still leads to "No mutual time" / "Not everyone agrees".
struct DemoPersona: Sendable {
    /// Votes on the 8 generated slots, by rank (index 0 = rank 1).
    let timeVotes: [Vote]
    /// Card vote per activity category (food, active, nature, games, markets, arts).
    let categories: [String: Vote]
    /// Highest price level (0 free … 3 $$$) this friend is happy with; pricier cards drop
    /// one step (yes → maybe, maybe → no).
    let maxPrice: Int
    /// Setting, price and vibe answers for the survey (type answers come from `categories`).
    let otherAnswers: [String: SurveyAnswer]

    func timeVote(for slot: TimeSlot) -> Vote {
        // Suggested times are answered yes (they were picked to fit), like the real flow.
        guard slot.source == .computed, slot.rank >= 1, slot.rank <= timeVotes.count else { return .yes }
        return timeVotes[slot.rank - 1]
    }

    func cardVote(for card: HangoutCard) -> Vote {
        let base: Vote = categories[card.category] ?? .maybe
        guard let price = card.priceLevel, price > maxPrice else { return base }
        switch base {
        case .yes: return .maybe
        case .maybe, .no: return .no
        }
    }

    var surveyAnswers: [String: SurveyAnswer] {
        var out: [String: SurveyAnswer] = otherAnswers
        for q in SurveyQuestion.all where q.category == "Type" {
            if let v = categories[q.id] {
                out[q.id] = SurveyAnswer(rawValue: v.rawValue) ?? .dontCare
            } else if out[q.id] == nil {
                out[q.id] = .dontCare
            }
        }
        return out
    }

    /// Anyone without a preset (e.g. a newly signed-up user) goes along with everything.
    static let easygoing = DemoPersona(
        timeVotes: Array(repeating: .yes, count: 8),
        categories: [:], maxPrice: 3, otherAnswers: [:])

    static func forUser(_ uid: String) -> DemoPersona {
        presets[uid] ?? easygoing
    }

    static let presets: [String: DemoPersona] = [
        // Seth: evenings after lab, foodie and gamer, not into nature.
        MockStore.Ids.seth: DemoPersona(
            timeVotes: [.maybe, .yes, .yes, .no, .yes, .yes, .no, .yes],
            categories: ["food": .yes, "games": .yes, "arts": .yes, "active": .maybe, "markets": .maybe, "nature": .no],
            maxPrice: 2,
            otherAnswers: ["indoors": .yes, "outdoors": .maybe, "priceLow": .yes, "priceMid": .yes, "priceHigh": .no,
                           "chill": .maybe, "lively": .yes]),
        // Matt: daytime and weekends, outdoorsy, on a budget, skips arts.
        MockStore.Ids.matt: DemoPersona(
            timeVotes: [.yes, .no, .yes, .yes, .maybe, .no, .yes, .yes],
            categories: ["food": .maybe, "active": .yes, "nature": .yes, "markets": .yes, "games": .maybe, "arts": .no],
            maxPrice: 1,
            otherAnswers: ["indoors": .maybe, "outdoors": .yes, "priceLow": .yes, "priceMid": .maybe, "priceHigh": .no,
                           "chill": .dontCare, "lively": .dontCare]),
        // Claire: free most afternoons, likes arts, food and markets, not games.
        MockStore.Ids.claire: DemoPersona(
            timeVotes: [.yes, .yes, .maybe, .yes, .yes, .yes, .no, .no],
            categories: ["arts": .yes, "food": .yes, "markets": .yes, "nature": .maybe, "active": .maybe, "games": .no],
            maxPrice: 2,
            otherAnswers: ["indoors": .dontCare, "outdoors": .dontCare, "priceLow": .yes, "priceMid": .yes, "priceHigh": .maybe,
                           "chill": .yes, "lively": .maybe]),
        // Ava: easygoing about most things, but busy weekend afternoons.
        MockStore.Ids.ava: DemoPersona(
            timeVotes: [.maybe, .yes, .yes, .yes, .no, .yes, .yes, .maybe],
            categories: ["food": .yes, "nature": .yes, "games": .yes, "active": .maybe, "arts": .maybe, "markets": .maybe],
            maxPrice: 2,
            otherAnswers: ["indoors": .dontCare, "outdoors": .yes, "priceLow": .yes, "priceMid": .yes, "priceHigh": .dontCare,
                           "chill": .yes, "lively": .dontCare]),
        // Noah (on Eklendi, not a friend until added): active, skips markets.
        MockStore.Ids.noah: DemoPersona(
            timeVotes: [.yes, .maybe, .yes, .no, .yes, .yes, .maybe, .yes],
            categories: ["food": .yes, "active": .yes, "games": .maybe, "arts": .yes, "nature": .maybe, "markets": .no],
            maxPrice: 2,
            otherAnswers: ["indoors": .yes, "outdoors": .maybe, "priceLow": .yes, "priceMid": .yes, "priceHigh": .maybe,
                           "chill": .dontCare, "lively": .yes]),
    ]

    /// Group score for a card from everyone's survey answers (yes +2, maybe +1, no −2,
    /// "I don't care" 0), so cards the group leans toward come first.
    static func groupScore(category: String, priceLevel: Int?, answers: [[String: SurveyAnswer]]) -> Int {
        func points(_ a: SurveyAnswer?) -> Int {
            switch a {
            case .some(.yes): return 2
            case .some(.maybe): return 1
            case .some(.no): return -2
            default: return 0
            }
        }
        let priceKey: String
        switch priceLevel ?? 1 {
        case 0, 1: priceKey = "priceLow"
        case 2: priceKey = "priceMid"
        default: priceKey = "priceHigh"
        }
        var total: Int = 0
        for a in answers {
            total += 2 * points(a[category]) + points(a[priceKey])
        }
        return total
    }
}
