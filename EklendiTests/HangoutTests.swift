import XCTest
@testable import Eklendi

/// Pure helpers behind the hangout screens (Eklendi/Features/Hangout/HangoutFlowLogic.swift).
final class HangoutTests: XCTestCase {
    private let tz: TimeZone = TimeZone(identifier: "America/Chicago")!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return HFFormat.calendar(tz).date(from: c)!
    }

    private func hangout(_ status: HangoutStatus, round: Int = 1, mode: HangoutMode = .timeAndActivity) -> Hangout {
        var h = Hangout(ownerId: "u_owner", mode: mode, durationsMinutes: [60], memberIds: ["u_owner", "u_me"])
        h.id = "h1"
        h.status = status
        h.round = round
        return h
    }

    private func member(_ id: String, name: String = "Matt Hill", state: MemberState = .active) -> HangoutMember {
        var m = HangoutMember(name: name, role: id == "u_owner" ? .owner : .member, state: state)
        m.id = id
        return m
    }

    // MARK: Routing

    func testRoutingLoadingAndMembership() {
        XCTAssertEqual(HFRouting.screen(hangout: nil, me: nil, membersLoaded: false), .loading)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingTimes), me: nil, membersLoaded: false), .loading)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingTimes), me: nil, membersLoaded: true), .notMember)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingTimes), me: member("u_me", state: .declined), membersLoaded: true), .notMember)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingTimes), me: member("u_me", state: .removed), membersLoaded: true), .notMember)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.collectingAvailability), me: member("u_me", state: .invited), membersLoaded: true), .join)
        // Cancelled wins over everything.
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.cancelled), me: member("u_me", state: .invited), membersLoaded: true), .cancelled)
    }

    func testRoutingByStatusAndProgress() {
        var me = member("u_me")
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.collectingAvailability), me: me, membersLoaded: true), .availability)
        me.availabilitySubmitted = true
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.collectingAvailability), me: me, membersLoaded: true), .waiting)

        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingTimes), me: me, membersLoaded: true), .swipeTimes)
        me.timesDone = true
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingTimes), me: me, membersLoaded: true), .waiting)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.noMutualTime), me: me, membersLoaded: true), .noMutualTime)

        XCTAssertEqual(HFRouting.screen(hangout: hangout(.survey), me: me, membersLoaded: true), .survey)
        me.surveyDone = true
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.survey), me: me, membersLoaded: true), .waiting)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.generating), me: me, membersLoaded: true), .generating)

        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingCards, round: 2), me: me, membersLoaded: true), .cards)
        me.cardsDoneRound = 1
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingCards, round: 2), me: me, membersLoaded: true), .cards)
        me.cardsDoneRound = 2
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.votingCards, round: 2), me: me, membersLoaded: true), .waiting)

        XCTAssertEqual(HFRouting.screen(hangout: hangout(.noAgreement), me: me, membersLoaded: true), .noAgreement)
        XCTAssertEqual(HFRouting.screen(hangout: hangout(.confirmed), me: me, membersLoaded: true), .confirmed)
    }

    func testStepDoneAndWaitingHeadline() {
        var m = member("u_a")
        let h = hangout(.votingTimes)
        XCTAssertFalse(HFRouting.stepDone(m, hangout: h))
        m.timesDone = true
        XCTAssertTrue(HFRouting.stepDone(m, hangout: h))
        let invited = member("u_b", state: .invited)
        XCTAssertFalse(HFRouting.stepDone(invited, hangout: hangout(.collectingAvailability)))
        XCTAssertEqual(HFRouting.countable([member("a"), member("b", state: .invited), member("c", state: .declined),
                                            member("d", state: .removed)]).map { $0.id }, ["a", "b"])

        XCTAssertEqual(HFRouting.waitingHeadline(pendingNames: []), "Everyone’s in.")
        XCTAssertEqual(HFRouting.waitingHeadline(pendingNames: ["Mark"]), "Waiting on Mark.")
        XCTAssertEqual(HFRouting.waitingHeadline(pendingNames: ["Mark", "Seth"]), "Waiting on Mark and Seth.")
        XCTAssertEqual(HFRouting.waitingHeadline(pendingNames: ["A", "B", "C"]), "Waiting on 3 people.")
        XCTAssertEqual(HFRouting.stepLabel(.survey, mode: .timeAndActivity), "Step 2 of 3")
        XCTAssertEqual(HFRouting.stepLabel(.votingTimes, mode: .timeOnly), "Pick a time")
    }

    // MARK: Formatting

    func testTimeFormatting() {
        let three = date(2026, 10, 8, 15)
        let four = date(2026, 10, 8, 16)
        XCTAssertEqual(HFFormat.timeRange(three, four, timeZone: tz), "3:00 – 4:00 PM")
        XCTAssertEqual(HFFormat.timeRange(date(2026, 10, 10, 11), date(2026, 10, 10, 13), timeZone: tz), "11:00 AM – 1:00 PM")
        XCTAssertEqual(HFFormat.time(date(2026, 10, 8, 18, 30), timeZone: tz), "6:30 PM")
        XCTAssertEqual(HFFormat.weekdayUpper(three, timeZone: tz), "THURSDAY")
        XCTAssertEqual(HFFormat.monthDayOrdinal(three, timeZone: tz), "October 8th")
        XCTAssertEqual(HFFormat.longDate(three, timeZone: tz), "Thursday, October 8")
        XCTAssertEqual(HFFormat.dayHeader(three, timeZone: tz), "Thursday, Oct 8")
        XCTAssertEqual(HFFormat.shortWhen(three, four, timeZone: tz), "Thu, Oct 8 · 3:00 – 4:00 PM")
        XCTAssertEqual(HFFormat.shortDayTime(three, timeZone: tz), "Thu 3:00 PM")
        XCTAssertEqual(HFFormat.shortTime(three, timeZone: tz), "3p")
        XCTAssertEqual(HFFormat.shortTime(date(2026, 10, 8, 9, 30), timeZone: tz), "9:30a")
        XCTAssertEqual(HFFormat.hourLabel(9), "9a")
        XCTAssertEqual(HFFormat.hourLabel(12), "12p")
        XCTAssertEqual(HFFormat.hourLabel(21), "9p")
    }

    func testOrdinalsAndLabels() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map { HFFormat.ordinal($0) },
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "111th"])
        XCTAssertEqual(HFFormat.durationLabel(minutes: 30), "30 min")
        XCTAssertEqual(HFFormat.durationLabel(minutes: 60), "1 hr")
        XCTAssertEqual(HFFormat.durationLabel(minutes: 90), "1 hr 30 min")
        XCTAssertEqual(HFFormat.durationLabel(minutes: 240), "4 hr")
        XCTAssertEqual(HFFormat.durationLabel(date(2026, 10, 8, 15), date(2026, 10, 8, 17)), "2 hr")
        XCTAssertNil(HFFormat.priceLabel(nil))
        XCTAssertEqual(HFFormat.priceLabel(0), "Free")
        XCTAssertEqual(HFFormat.priceLabel(2), "$$")
        XCTAssertEqual(HFFormat.priceLabel(9), "$$$$")
        XCTAssertEqual(HFFormat.distanceLabel(0.62), "0.6 mi")
        XCTAssertEqual(HFFormat.distanceLabel(12.4), "12 mi")
        XCTAssertNil(HFFormat.distanceLabel(nil))
        XCTAssertEqual(HFFormat.joinNames([]), "")
        XCTAssertEqual(HFFormat.joinNames(["Seth"]), "Seth")
        XCTAssertEqual(HFFormat.joinNames(["Seth", "Matt"]), "Seth and Matt")
        XCTAssertEqual(HFFormat.joinNames(["Seth", "Matt", "Mark"]), "Seth, Matt and Mark")
        XCTAssertEqual(HFFormat.firstName("Seth Fox"), "Seth")
        XCTAssertEqual(HFFormat.numberWord(4), "four")
    }

    func testDisplayName() {
        let owner = member("u_owner", name: "Seth Fox")
        var h = hangout(.votingTimes)
        XCTAssertEqual(HFFormat.displayName(hangout: h, members: [owner], myUid: "u_me"), "Seth’s hangout")
        XCTAssertEqual(HFFormat.displayName(hangout: h, members: [owner], myUid: "u_owner"), "Your hangout")
        h.title = "Coffee at Juniper Café"
        XCTAssertEqual(HFFormat.displayName(hangout: h, members: [owner], myUid: "u_me"), "Coffee at Juniper Café")
        var t = hangout(.votingTimes, mode: .timeOnly)
        t.planDescription = "Dinner at Mom’s"
        XCTAssertEqual(HFFormat.displayName(hangout: t, members: [owner], myUid: "u_me"), "Dinner at Mom’s")
        XCTAssertEqual(HFFormat.shortName(owner, myUid: "u_owner"), "You")
        XCTAssertEqual(HFFormat.shortName(owner, myUid: "u_me"), "Seth")
    }

    // MARK: Tallies and winner rule

    func testWinnerPrefersAllYes() {
        let starts: [String: Date] = ["a": date(2026, 10, 8, 15), "b": date(2026, 10, 9, 15), "c": date(2026, 10, 7, 15)]
        let votes: [String: [String: Vote]] = [
            "u1": ["a": .yes, "b": .yes, "c": .yes],
            "u2": ["a": .yes, "b": .yes, "c": .maybe],
            "u3": ["a": .yes, "b": .yes, "c": .yes],
        ]
        // a and b are all-yes; a is earlier.
        let w = HFTallies.winner(optionIds: ["b", "c", "a"], startOf: { starts[$0]! }, votes: votes, voters: ["u1", "u2", "u3"])
        XCTAssertEqual(w, "a")
    }

    func testWinnerFallsBackToYesOrMaybeWithTieBreaks() {
        let starts: [String: Date] = ["a": date(2026, 10, 8, 15), "b": date(2026, 10, 9, 15), "c": date(2026, 10, 7, 15)]
        let votes: [String: [String: Vote]] = [
            "u1": ["a": .yes, "b": .yes, "c": .no],
            "u2": ["a": .maybe, "b": .maybe, "c": .yes],
            "u3": ["a": .yes, "b": .maybe, "c": .yes],
        ]
        // c has a "no" → out. a: 2 yes 1 maybe beats b: 1 yes 2 maybe.
        XCTAssertEqual(HFTallies.winner(optionIds: ["a", "b", "c"], startOf: { starts[$0]! }, votes: votes,
                                        voters: ["u1", "u2", "u3"]), "a")
        // Equal yes and maybe → earliest.
        let tie: [String: [String: Vote]] = ["u1": ["a": .yes, "b": .yes], "u2": ["a": .maybe, "b": .maybe]]
        XCTAssertEqual(HFTallies.winner(optionIds: ["a", "b"], startOf: { starts[$0]! }, votes: tie, voters: ["u1", "u2"]), "a")
        // Missing vote counts as not agreeing.
        let missing: [String: [String: Vote]] = ["u1": ["a": .yes]]
        XCTAssertNil(HFTallies.winner(optionIds: ["a"], startOf: { starts[$0]! }, votes: missing, voters: ["u1", "u2"]))
    }

    func testTopOptionsAndTallyLabel() {
        let starts: [String: Date] = ["a": date(2026, 10, 8, 15), "b": date(2026, 10, 9, 15),
                                      "c": date(2026, 10, 7, 15), "d": date(2026, 10, 6, 15)]
        let votes: [String: [String: Vote]] = [
            "u1": ["a": .yes, "b": .yes, "c": .no, "d": .no],
            "u2": ["a": .no, "b": .yes, "c": .maybe, "d": .no],
            "u3": ["a": .yes, "b": .no, "c": .yes, "d": .maybe],
        ]
        let top = HFTallies.topOptions(optionIds: ["a", "b", "c", "d"], startOf: { starts[$0]! },
                                       votes: votes, voters: ["u1", "u2", "u3"])
        // a: 2y, b: 2y (b later) → a, b; c: 1y 1m beats d: 0y 1m.
        XCTAssertEqual(top, ["a", "b", "c"])
        let t = HFTallies.tally(optionId: "c", votes: votes, voters: ["u1", "u2", "u3"])
        XCTAssertEqual(t, HFTally(yes: 1, maybe: 1, no: 1))
        XCTAssertEqual(t.label, "1 yes · 1 maybe · 1 no")
        XCTAssertEqual(HFTally(yes: 3, maybe: 0, no: 0).label, "3 yes")
        XCTAssertEqual(HFTallies.counts(["a": .yes, "b": .yes, "c": .no]), HFTally(yes: 2, maybe: 0, no: 1))
    }

    // MARK: Durations

    func testDurations() {
        XCTAssertEqual(HFDurations.minutes(presets: [60, 120], customOn: true, customHours: 4, any: false), [60, 120, 240])
        XCTAssertEqual(HFDurations.minutes(presets: [60], customOn: true, customHours: 1, any: false), [60])
        XCTAssertEqual(HFDurations.minutes(presets: [60], customOn: true, customHours: 40, any: false), [60, 720])
        XCTAssertEqual(HFDurations.minutes(presets: [60], customOn: false, customHours: 4, any: true), [])
        XCTAssertEqual(HFDurations.clampCustom(0), 1)
        XCTAssertEqual(HFDurations.clampCustom(13), 12)
        XCTAssertTrue(HFDurations.isValid(presets: [], customOn: false, any: true))
        XCTAssertFalse(HFDurations.isValid(presets: [], customOn: false, any: false))
        XCTAssertEqual(HFDurations.summary(presets: [30, 120], customOn: true, customHours: 4, any: false), "30 min, 2 hr, 4 hr")
        XCTAssertEqual(HFDurations.summary(presets: [], customOn: false, customHours: 4, any: false), "Pick one")
        XCTAssertEqual(HFDurations.summary(presets: [60], customOn: false, customHours: 4, any: true), "Any length")
        XCTAssertEqual(HFDurations.defaultCustomHours, 4)
    }

    // MARK: Day view

    func testSnapAndClamp() {
        XCTAssertEqual(HFDayMath.snap(607), 600)
        XCTAssertEqual(HFDayMath.snap(608), 615)
        XCTAssertEqual(HFDayMath.snap(620, step: 30), 630)
        XCTAssertEqual(HFDayMath.clampStart(400, duration: 60, dayStart: 480, dayEnd: 1380), 480)
        XCTAssertEqual(HFDayMath.clampStart(1350, duration: 60, dayStart: 480, dayEnd: 1380), 1320)
        XCTAssertEqual(HFDayMath.clampStart(900, duration: 60, dayStart: 480, dayEnd: 1380), 900)
    }

    func testClashesRespectBuffers() {
        let lanes: [HFLane] = [
            HFLane(uid: "a", name: "You", busy: [BusyBlock(start: date(2026, 10, 8, 9), end: date(2026, 10, 8, 12))], bufferMinutes: 15),
            HFLane(uid: "b", name: "Matt", busy: [BusyBlock(start: date(2026, 10, 8, 13), end: date(2026, 10, 8, 15))], bufferMinutes: 15),
        ]
        // Class ends 3:00 PM → 3:15 start is fine, 3:10 is not.
        XCTAssertEqual(HFDayMath.clashes(start: date(2026, 10, 8, 15, 15), end: date(2026, 10, 8, 16, 15), lanes: lanes), [])
        XCTAssertEqual(HFDayMath.clashes(start: date(2026, 10, 8, 15, 10), end: date(2026, 10, 8, 16, 10), lanes: lanes), ["Matt"])
        XCTAssertEqual(HFDayMath.clashes(start: date(2026, 10, 8, 11), end: date(2026, 10, 8, 14), lanes: lanes), ["You", "Matt"])
        XCTAssertEqual(HFDayMath.statusText(clashNames: []), "Everyone’s free")
        XCTAssertEqual(HFDayMath.statusText(clashNames: ["Matt"]), "Matt is busy")
        XCTAssertEqual(HFDayMath.statusText(clashNames: ["You"]), "You’re busy")
        XCTAssertEqual(HFDayMath.statusText(clashNames: ["Seth", "Matt"]), "Seth and Matt are busy")
    }

    func testDayBlocksClipToDay() {
        let cal = HFFormat.calendar(tz)
        let busy: [BusyBlock] = [
            BusyBlock(start: date(2026, 10, 7, 22), end: date(2026, 10, 8, 1)),     // crosses midnight
            BusyBlock(start: date(2026, 10, 8, 13), end: date(2026, 10, 8, 14, 45)),
            BusyBlock(start: date(2026, 10, 9, 9), end: date(2026, 10, 9, 10)),     // other day
        ]
        let blocks = HFDayMath.dayBlocks(busy, day: date(2026, 10, 8, 12), calendar: cal)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].start, 0)
        XCTAssertEqual(blocks[0].end, 60)
        XCTAssertEqual(blocks[1].start, 13 * 60)
        XCTAssertEqual(blocks[1].end, 14 * 60 + 45)
        XCTAssertEqual(HFDayMath.minutesIntoDay(date(2026, 10, 8, 15, 30), calendar: cal), 930)
        XCTAssertEqual(HFDayMath.date(day: date(2026, 10, 8, 3), minutes: 930, calendar: cal), date(2026, 10, 8, 15, 30))
    }

    // MARK: Local store

    func testLocalStoreRoundTrip() {
        let hid: String = "test_\(UUID().uuidString)"
        XCTAssertEqual(HFLocalStore.votedSlotIds(hangoutId: hid, uid: "u"), [])
        HFLocalStore.addVotedSlotIds(["s1", "s2"], hangoutId: hid, uid: "u")
        HFLocalStore.addVotedSlotIds(["s2", "s3"], hangoutId: hid, uid: "u")
        XCTAssertEqual(HFLocalStore.votedSlotIds(hangoutId: hid, uid: "u"), ["s1", "s2", "s3"])
        HFLocalStore.clearVotedSlotIds(hangoutId: hid, uid: "u")
        XCTAssertEqual(HFLocalStore.votedSlotIds(hangoutId: hid, uid: "u"), [])

        XCTAssertNil(HFLocalStore.calendarEvent(hangoutId: hid))
        let start: Date = date(2026, 10, 8, 15)
        HFLocalStore.setCalendarEvent(hangoutId: hid, start: start, identifier: "evt|with|pipes")
        let record = HFLocalStore.calendarEvent(hangoutId: hid)
        XCTAssertEqual(record?.start, start.timeIntervalSince1970)
        XCTAssertEqual(record?.identifier, "evt|with|pipes")
        HFLocalStore.clearCalendarEvent(hangoutId: hid)
        XCTAssertNil(HFLocalStore.calendarEvent(hangoutId: hid))
    }

    // MARK: Offer filtering (TimeSlot.offerOnly)

    func testOfferOnlyDecodesOptional() throws {
        let json: String = """
        {"start": 0, "end": 3600, "source": "fallback", "missingMemberIds": [], "rank": 1, "label": "All but one", "reason": "", "offerOnly": true}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let slot: TimeSlot = try decoder.decode(TimeSlot.self, from: Data(json.utf8))
        XCTAssertEqual(slot.offerOnly, true)
        let plain: String = """
        {"start": 0, "end": 3600, "source": "computed", "missingMemberIds": [], "rank": 1, "label": "", "reason": ""}
        """
        let slot2: TimeSlot = try decoder.decode(TimeSlot.self, from: Data(plain.utf8))
        XCTAssertNil(slot2.offerOnly)
    }
}
