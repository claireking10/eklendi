import XCTest
@testable import Eklendi

/// Demo mode: 10-digit login and the preset friends (Services/MockStore.swift, `DemoPersona`).
final class DemoLoginTests: XCTestCase {
    func testUsernameNeedsExactlyTenDigits() {
        XCTAssertTrue(AccountValidation.isValidUsername("1234567890"))
        XCTAssertTrue(AccountValidation.isValidUsername("(210) 555-0142"))
        XCTAssertFalse(AccountValidation.isValidUsername("123456789"))
        XCTAssertFalse(AccountValidation.isValidUsername("12345678901"))
        XCTAssertFalse(AccountValidation.isValidUsername(""))
    }

    func testDemoUsernameDigitsDropsUSCountryCode() {
        XCTAssertEqual(AccountValidation.demoUsernameDigits("+12105550142"), "2105550142")
        XCTAssertEqual(AccountValidation.demoUsernameDigits("2105550142"), "2105550142")
        XCTAssertTrue(AccountValidation.isDemoUsername("+10000000000"))
        XCTAssertFalse(AccountValidation.isDemoUsername("+1555"))
    }
}

final class DemoPersonaTests: XCTestCase {
    private func card(category: String, price: Int?) -> HangoutCard {
        HangoutCard(round: 1, activity: "A", description: "", category: category, venueName: "V", address: "",
                    lat: 0, lng: 0, distanceMiles: nil, priceLevel: price, photoUrl: nil, placeId: "",
                    start: Date(), end: Date(), tags: [])
    }

    func testPriceAboveBudgetDropsOneStep() {
        let matt: DemoPersona = DemoPersona.forUser(MockStore.Ids.matt)   // max price 1
        XCTAssertEqual(matt.cardVote(for: card(category: "active", price: 1)), .yes)
        XCTAssertEqual(matt.cardVote(for: card(category: "active", price: 2)), .maybe)
        XCTAssertEqual(matt.cardVote(for: card(category: "food", price: 2)), .no)
    }

    func testTimeVotesFollowRankAndSuggestedIsYes() {
        let seth: DemoPersona = DemoPersona.forUser(MockStore.Ids.seth)
        var slot = TimeSlot(start: Date(), end: Date(), source: .computed)
        slot.rank = 4
        XCTAssertEqual(seth.timeVote(for: slot), .no)
        slot.source = .suggested
        XCTAssertEqual(seth.timeVote(for: slot), .yes)
    }

    func testUnknownUserIsEasygoing() {
        let p: DemoPersona = DemoPersona.forUser("u_someone_new")
        XCTAssertEqual(p.cardVote(for: card(category: "arts", price: 3)), .maybe)
    }

    /// Every combination of preset friends leaves at least one time slot nobody vetoes.
    func testEveryFriendGroupHasAWorkableTime() {
        let friends: [String] = Array(DemoPersona.presets.keys)
        for mask in 1..<(1 << friends.count) {
            let group: [DemoPersona] = friends.indices.filter { mask & (1 << $0) != 0 }.map { DemoPersona.forUser(friends[$0]) }
            let workable: Bool = (1...8).contains { rank in
                var slot = TimeSlot(start: Date(), end: Date(), source: .computed)
                slot.rank = rank
                return group.allSatisfy { $0.timeVote(for: slot) != .no }
            }
            XCTAssertTrue(workable, "No workable time for group mask \(mask)")
        }
    }

    func testSurveyAnswersCoverEveryQuestion() {
        let answers: [String: SurveyAnswer] = DemoPersona.forUser(MockStore.Ids.claire).surveyAnswers
        for q in SurveyQuestion.all {
            XCTAssertNotNil(answers[q.id], "Missing \(q.id)")
        }
    }

    func testGroupScoreFavorsLikedCategories() {
        let answers: [[String: SurveyAnswer]] = [["food": .yes, "games": .no, "priceLow": .yes]]
        XCTAssertGreaterThan(DemoPersona.groupScore(category: "food", priceLevel: 1, answers: answers),
                             DemoPersona.groupScore(category: "games", priceLevel: 1, answers: answers))
    }
}
