import XCTest
@testable import Eklendi

final class AccountValidationTests: XCTestCase {
    func testNormalizePhoneAssumesUSForTenDigits() {
        XCTAssertEqual(AccountValidation.normalizePhone("(210) 555-0142"), "+12105550142")
        XCTAssertEqual(AccountValidation.normalizePhone("210.555.0142"), "+12105550142")
        XCTAssertEqual(AccountValidation.normalizePhone("2105550142"), "+12105550142")
        XCTAssertEqual(AccountValidation.normalizePhone("  210 555 0142 "), "+12105550142")
    }

    func testNormalizePhoneHandlesCountryCode() {
        XCTAssertEqual(AccountValidation.normalizePhone("1-210-555-0142"), "+12105550142")
        XCTAssertEqual(AccountValidation.normalizePhone("+1 (210) 555-0142"), "+12105550142")
        XCTAssertEqual(AccountValidation.normalizePhone("+44 20 7946 0958"), "+442079460958")
        XCTAssertEqual(AccountValidation.normalizePhone("0044 20 7946 0958"), "+442079460958")
    }

    func testNormalizePhoneRejectsGarbage() {
        XCTAssertNil(AccountValidation.normalizePhone(""))
        XCTAssertNil(AccountValidation.normalizePhone("555-0142"))
        XCTAssertNil(AccountValidation.normalizePhone("hello"))
        XCTAssertNil(AccountValidation.normalizePhone("+12"))
    }

    func testPassword() {
        XCTAssertNotNil(AccountValidation.passwordError("12345"))
        XCTAssertNil(AccountValidation.passwordError("123456"))
    }

    func testCode() {
        XCTAssertEqual(AccountValidation.cleanCode("12 34 56 78"), "123456")
        XCTAssertTrue(AccountValidation.isValidCode("123456"))
        XCTAssertFalse(AccountValidation.isValidCode("12345"))
        XCTAssertFalse(AccountValidation.isValidCode(""))
    }

    func testTrimmedName() {
        XCTAssertEqual(AccountValidation.trimmedName("  Zach  "), "Zach")
    }
}

final class HomeLocationValidationTests: XCTestCase {
    func testZipOnlyIsRejected() {
        XCTAssertTrue(HomeLocationValidation.isZipOnly("78205"))
        XCTAssertTrue(HomeLocationValidation.isZipOnly("78205-1234"))
        XCTAssertNotNil(HomeLocationValidation.error("60637"))
    }

    func testNeighborhoodIsAccepted() {
        XCTAssertFalse(HomeLocationValidation.isZipOnly("Hyde Park, Chicago"))
        XCTAssertFalse(HomeLocationValidation.isZipOnly("5th & Main"))
        XCTAssertNil(HomeLocationValidation.error("Hyde Park, Chicago"))
        XCTAssertNil(HomeLocationValidation.error("Near Main St & 5th Ave"))
    }

    func testEmptyOrTooShort() {
        XCTAssertNotNil(HomeLocationValidation.error(""))
        XCTAssertNotNil(HomeLocationValidation.error("   "))
        XCTAssertNotNil(HomeLocationValidation.error("ab"))
    }
}

final class BufferSettingTests: XCTestCase {
    func testSteppingIsClampedInFives() {
        XCTAssertEqual(BufferSetting.increment(15), 20)
        XCTAssertEqual(BufferSetting.decrement(15), 10)
        XCTAssertEqual(BufferSetting.increment(60), 60)
        XCTAssertEqual(BufferSetting.decrement(0), 0)
        XCTAssertEqual(BufferSetting.defaultMinutes, 15)
    }

    func testExample() {
        XCTAssertTrue(BufferSetting.example(15).contains("3:15 PM"))
        XCTAssertTrue(BufferSetting.example(0).hasPrefix("No buffer"))
    }

    func testClock() {
        XCTAssertEqual(BufferSetting.clock(0), "12:00 AM")
        XCTAssertEqual(BufferSetting.clock(12 * 60), "12:00 PM")
        XCTAssertEqual(BufferSetting.clock(15 * 60 + 5), "3:05 PM")
        XCTAssertEqual(BufferSetting.clock(9 * 60 + 30), "9:30 AM")
    }
}

final class InterestsAndInviteTests: XCTestCase {
    func testAppendSuggestion() {
        XCTAssertEqual(InterestSuggestions.append("Hiking", to: ""), "Hiking")
        XCTAssertEqual(InterestSuggestions.append("Live music", to: "Coffee shops."), "Coffee shops, live music")
        XCTAssertEqual(InterestSuggestions.append("Movies", to: "tacos, "), "tacos, movies")
    }

    func testRemainingSuggestionsSkipMentionedOnes() {
        let remaining: [String] = InterestSuggestions.remaining(for: "I love HIKING and movies")
        XCTAssertFalse(remaining.contains("Hiking"))
        XCTAssertFalse(remaining.contains("Movies"))
        XCTAssertEqual(remaining.count, InterestSuggestions.all.count - 2)
    }

    func testSmsInviteURL() {
        let url: URL? = InviteMessage.smsURL(to: "+12105550142")
        XCTAssertNotNil(url)
        let s: String = url?.absoluteString ?? ""
        XCTAssertTrue(s.hasPrefix("sms:+12105550142&body="))
        XCTAssertFalse(s.contains(" "))
    }

    func testContactNumbersAreNormalizedAndDeduped() {
        let out: [String] = ContactMatching.normalizedNumbers(["(210) 555-0142", "+1 210 555 0142", "123", "512-555-0164"])
        XCTAssertEqual(out, ["+12105550142", "+15125550164"])
    }
}

final class AccountFormatTests: XCTestCase {
    private func utc(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 8; comps.hour = hour; comps.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }

    func testFirstName() {
        XCTAssertEqual(AccountFormat.firstName("Seth Fox"), "Seth")
        XCTAssertEqual(AccountFormat.firstName("Ava"), "Ava")
        XCTAssertEqual(AccountFormat.firstName(""), "")
    }

    func testTimeRange() {
        let utcZone: TimeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(AccountFormat.timeRange(utc(15), utc(16), timeZone: utcZone), "3:00 – 4:00 PM")
        XCTAssertEqual(AccountFormat.timeRange(utc(11), utc(13), timeZone: utcZone), "11:00 AM – 1:00 PM")
        XCTAssertEqual(AccountFormat.timeRange(utc(18, 30), utc(19, 30), timeZone: utcZone), "6:30 – 7:30 PM")
    }
}

final class HomeSectioningTests: XCTestCase {
    private let me: String = "u_zach"

    private func hangout(_ status: HangoutStatus, owner: String = "u_seth") -> Hangout {
        var h = Hangout(ownerId: owner, mode: .timeAndActivity, durationsMinutes: [60], memberIds: [owner, "u_zach"])
        h.id = "h1"
        h.status = status
        return h
    }

    private func member(state: MemberState = .active) -> HangoutMember {
        var m = HangoutMember(name: "Zach Weiss", role: .member, state: state)
        m.id = "u_zach"
        return m
    }

    func testVotingTimesNeedsMySwipes() {
        let info: HomeTileInfo = HomeSectioning.info(for: hangout(.votingTimes), me: member(), myUid: me, ownerName: "Seth Fox")
        XCTAssertEqual(info.section, .needsAction)
        XCTAssertEqual(info.action, "Swipe")
        XCTAssertTrue(info.status.contains("started by Seth"))
    }

    func testVotingTimesDoneIsInProgress() {
        var m = member()
        m.timesDone = true
        let info: HomeTileInfo = HomeSectioning.info(for: hangout(.votingTimes), me: m, myUid: me, ownerName: "Seth Fox")
        XCTAssertEqual(info.section, .inProgress)
        XCTAssertNil(info.action)
    }

    func testInviteNeedsJoin() {
        let info: HomeTileInfo = HomeSectioning.info(for: hangout(.collectingAvailability), me: member(state: .invited),
                                                     myUid: me, ownerName: "Matt Hill")
        XCTAssertEqual(info.section, .needsAction)
        XCTAssertEqual(info.action, "Join")
    }

    func testSurveyAndCards() {
        XCTAssertEqual(HomeSectioning.info(for: hangout(.survey), me: member(), myUid: me, ownerName: nil).section, .needsAction)
        XCTAssertEqual(HomeSectioning.info(for: hangout(.votingCards), me: member(), myUid: me, ownerName: nil).section, .needsAction)
        var m = member()
        m.cardsDoneRound = 1
        XCTAssertEqual(HomeSectioning.info(for: hangout(.votingCards), me: m, myUid: me, ownerName: nil).section, .inProgress)
        XCTAssertEqual(HomeSectioning.info(for: hangout(.generating), me: m, myUid: me, ownerName: nil).section, .inProgress)
        XCTAssertEqual(HomeSectioning.info(for: hangout(.noAgreement), me: m, myUid: me, ownerName: nil).section, .needsAction)
        XCTAssertEqual(HomeSectioning.info(for: hangout(.noMutualTime), me: m, myUid: me, ownerName: nil).section, .needsAction)
    }

    func testConfirmedUpcomingAndPast() {
        let now = Date()
        var h = hangout(.confirmed)
        h.confirmed = ConfirmedPlan(start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
                                    activity: "Coffee", venueName: "Juniper Café", address: "412 Alamo St", cardId: nil)
        XCTAssertEqual(HomeSectioning.info(for: h, me: member(), myUid: me, ownerName: nil, now: now).section, .upcoming)
        h.confirmed = ConfirmedPlan(start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
                                    activity: "Coffee", venueName: "Juniper Café", address: "412 Alamo St", cardId: nil)
        XCTAssertEqual(HomeSectioning.info(for: h, me: member(), myUid: me, ownerName: nil, now: now).section, .past)
    }

    func testCancelledAndDeclinedAreHidden() {
        XCTAssertEqual(HomeSectioning.info(for: hangout(.cancelled), me: member(), myUid: me, ownerName: nil).section, .hidden)
        XCTAssertEqual(HomeSectioning.info(for: hangout(.votingTimes), me: member(state: .declined), myUid: me, ownerName: nil).section, .hidden)
    }

    func testTitles() {
        XCTAssertEqual(HomeSectioning.title(for: hangout(.votingTimes), myUid: me, ownerName: "Seth Fox"), "Seth’s hangout")
        XCTAssertEqual(HomeSectioning.title(for: hangout(.votingTimes, owner: me), myUid: me, ownerName: "Zach Weiss"), "Your hangout")
        var titled = hangout(.confirmed)
        titled.title = "Coffee at Juniper Café"
        XCTAssertEqual(HomeSectioning.title(for: titled, myUid: me, ownerName: "Seth Fox"), "Coffee at Juniper Café")
        var timeOnly = hangout(.votingTimes)
        timeOnly.mode = .timeOnly
        timeOnly.planDescription = "Dinner at Matt's"
        XCTAssertEqual(HomeSectioning.title(for: timeOnly, myUid: me, ownerName: "Seth Fox"), "Dinner at Matt's")
    }

    func testGoingCount() {
        var a = member()
        a.id = "a"
        var b = member()
        b.id = "b"
        b.notGoing = true
        var c = member(state: .declined)
        c.id = "c"
        XCTAssertEqual(HomeSectioning.goingCount([a, b, c]), 1)
    }
}
