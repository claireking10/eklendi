import Foundation

/// In-memory "Firestore" shared by all mock services. Seeded with realistic data and a
/// tiny simulation of the Cloud Functions state machine (availability → slots → time winner
/// → survey → cards → confirmed). Every mutation calls `notify()`, which re-fires every
/// active listener with fresh data.
@MainActor
final class MockStore {
    // MARK: Seed ids (documented in docs/UI_COMPONENTS.md)
    enum Ids {
        static let zach = "u_zach"
        static let seth = "u_seth"
        static let matt = "u_matt"
        static let claire = "u_claire"
        static let ava = "u_ava"
        /// Registered on Eklendi but NOT Zach's friend (contacts "Add" button).
        static let noah = "u_noah"

        static let votingTimes = "h_voting_times"
        static let survey = "h_survey"
        static let votingCards = "h_voting_cards"
        static let confirmed = "h_confirmed"
        static let noAgreement = "h_no_agreement"
        static let noMutualTime = "h_no_mutual_time"
        static let collecting = "h_collecting"
    }

    static let zachPhone = "+15555550100"
    static let zachPassword = "password123"

    // MARK: Data
    var users: [String: UserProfile] = [:]
    /// E.164 phone → password (mock accounts).
    var passwords: [String: String] = [:]
    var hangouts: [String: Hangout] = [:]
    /// hangoutId → uid → member
    var members: [String: [String: HangoutMember]] = [:]
    var slots: [String: [TimeSlot]] = [:]
    var cards: [String: [HangoutCard]] = [:]
    /// hangoutId → uid → slotId → vote
    var timeVotes: [String: [String: [String: Vote]]] = [:]
    /// hangoutId → uid → questionId → answer
    var surveyAnswers: [String: [String: [String: SurveyAnswer]]] = [:]
    /// hangoutId → round → uid → cardId → vote
    var cardVotes: [String: [Int: [String: [String: Vote]]]] = [:]

    /// Seconds the simulated backend waits before advancing (shorter in UI tests).
    let delay: Double

    private var observers: [UUID: () -> Void] = [:]
    private var idCounter: Int = 0

    init() {
        let args: [String] = ProcessInfo.processInfo.arguments
        delay = args.contains("-uiTesting") ? 0.3 : 1.0
        seed()
    }

    // MARK: Listeners

    /// Registers a listener; fires immediately and after every change.
    func observe(_ fire: @escaping () -> Void) -> Cancellable {
        let id = UUID()
        observers[id] = fire
        fire()
        return Cancellable { [weak self] in
            self?.observers[id] = nil
        }
    }

    func notify() {
        let all: [() -> Void] = Array(observers.values)
        for fire in all { fire() }
    }

    func newId(_ prefix: String) -> String {
        idCounter += 1
        return "\(prefix)_\(idCounter)_\(Int(Date().timeIntervalSince1970))"
    }

    /// Runs `work` on the main actor after the simulated backend delay.
    func later(_ factor: Double = 1.0, _ work: @escaping @MainActor () -> Void) {
        let nanos: UInt64 = UInt64(delay * factor * 1_000_000_000)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanos)
            work()
        }
    }

    // MARK: Helpers

    func name(of uid: String) -> String {
        users[uid]?.name ?? "Friend"
    }

    func activeMembers(_ hangoutId: String) -> [HangoutMember] {
        (members[hangoutId] ?? [:]).values.filter { $0.state == .active }.sorted { $0.name < $1.name }
    }

    func updateHangout(_ id: String, _ change: (inout Hangout) -> Void) {
        guard var h = hangouts[id] else { return }
        change(&h)
        h.updatedAt = Date()
        hangouts[id] = h
    }

    func updateMember(_ hangoutId: String, _ uid: String, _ change: (inout HangoutMember) -> Void) {
        guard var m = members[hangoutId]?[uid] else { return }
        change(&m)
        members[hangoutId]?[uid] = m
    }

    static func date(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let today: Date = cal.startOfDay(for: Date())
        let day: Date = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func makeMember(_ uid: String, role: MemberRole, state: MemberState) -> HangoutMember {
        var m = HangoutMember(name: name(of: uid), role: role, state: state)
        m.id = uid
        m.bufferMinutes = users[uid]?.bufferMinutes ?? 15
        m.startLocation = users[uid]?.homeLocation
        m.timeZone = TimeZone.current.identifier
        return m
    }

    // MARK: Simulation: slots

    /// Up to 8 specific slots over the next ~10 days at sensible hours.
    func generateSlots(hangoutId: String, durationMinutes: Int) -> [TimeSlot] {
        let minutes: Int = max(30, min(durationMinutes, 240))
        let plan: [(day: Int, hour: Int, minute: Int, label: String, reason: String)] = [
            (2, 15, 0, "Best match", "Starts 15 min after Matt's class ends at 2:45."),
            (1, 18, 30, "Weeknight", "Starts 15 min after Seth's lab ends at 6:15."),
            (3, 19, 0, "Evening", "Everyone's free all evening."),
            (4, 11, 0, "Weekend", "Ends 15 min before Claire's 2:30 plans."),
            (5, 15, 30, "Weekend", "Ends 15 min before Seth's 6:00 dinner."),
            (6, 18, 0, "Weeknight", "Right after work for everyone."),
            (8, 12, 0, "Lunch", "Longest window next week."),
            (9, 19, 30, "Evening", "Everyone's free after 7:15."),
        ]
        var out: [TimeSlot] = []
        for (index, p) in plan.enumerated() {
            let start: Date = MockStore.date(dayOffset: p.day, hour: p.hour, minute: p.minute)
            let end: Date = start.addingTimeInterval(TimeInterval(minutes * 60))
            var slot = TimeSlot(start: start, end: end, source: .computed)
            slot.id = "\(hangoutId)_slot\(index + 1)"
            slot.rank = index + 1
            slot.label = p.label
            slot.reason = p.reason
            out.append(slot)
        }
        return out
    }

    /// "All but one" fallback slots for noMutualTime.
    func generateFallbackSlots(hangoutId: String, missing: String) -> [TimeSlot] {
        var out: [TimeSlot] = []
        let days: [Int] = [16, 19, 23]
        for (index, day) in days.enumerated() {
            let start: Date = MockStore.date(dayOffset: day, hour: 18 + index % 2, minute: 0)
            var slot = TimeSlot(start: start, end: start.addingTimeInterval(3600), source: .fallback)
            slot.id = "\(hangoutId)_fb\(index + 1)"
            slot.rank = index + 1
            slot.missingMemberIds = [missing]
            slot.label = "Later this month"
            slot.reason = "Everyone but \(name(of: missing)) is free."
            out.append(slot)
        }
        return out
    }

    // MARK: Simulation: cards

    private struct CardSeed {
        let activity: String
        let venue: String
        let address: String
        let description: String
        let category: String
        let price: Int?
        let photo: String?
        let miles: Double
        let tags: [String]
    }

    private let cardPool: [CardSeed] = [
        CardSeed(activity: "Coffee + pastries", venue: "Juniper Café", address: "412 Alamo St", description: "A bright neighborhood café with big tables. Easy for a group, and you're done before dinner.", category: "food", price: 1, photo: "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=900", miles: 0.6, tags: ["$", "Indoors", "Chill"]),
        CardSeed(activity: "Bowling", venue: "Ridgeline Lanes", address: "2300 Ridgeline Blvd", description: "One quick game and a basket of fries. Weekday afternoons are rarely busy.", category: "active", price: 2, photo: nil, miles: 3.1, tags: ["$$", "Indoors", "Lively"]),
        CardSeed(activity: "Picnic in the park", venue: "Alder Park", address: "100 Alder Park Dr", description: "Grab sandwiches on the way and claim a shady spot by the pond.", category: "nature", price: 0, photo: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=900", miles: 1.2, tags: ["Free", "Outdoors", "Chill"]),
        CardSeed(activity: "Board game café", venue: "Meeple House", address: "88 Market St", description: "Hundreds of games on the shelves and staff who'll teach you one in five minutes.", category: "games", price: 1, photo: nil, miles: 2.4, tags: ["$", "Indoors"]),
        CardSeed(activity: "Tacos + horchata", venue: "La Brasa Taquería", address: "1510 S Flores St", description: "Counter-service tacos with a patio. Quick, cheap and easy to share.", category: "food", price: 1, photo: nil, miles: 1.8, tags: ["$", "Patio"]),
        CardSeed(activity: "Mini golf", venue: "Cedar Hollow Mini Golf", address: "7400 Cedar Hollow Rd", description: "Eighteen holes with a little friendly trash talk. Shaded course for warm days.", category: "active", price: 2, photo: nil, miles: 4.0, tags: ["$$", "Outdoors"]),
        CardSeed(activity: "Trivia night", venue: "The Copper Kettle", address: "230 E Houston St", description: "Weekly pub trivia with teams of up to six. Four is the sweet spot.", category: "games", price: 1, photo: nil, miles: 2.9, tags: ["$", "Lively"]),
        CardSeed(activity: "Arcade", venue: "Pixel Pier", address: "17 Riverwalk Pl", description: "Retro cabinets, air hockey and a prize counter. Load a card and split it.", category: "games", price: 2, photo: nil, miles: 5.2, tags: ["$$", "Lively"]),
        CardSeed(activity: "Farmers market", venue: "Riverside Market", address: "312 Pearl Pkwy", description: "Wander the stalls, sample a few things and grab lunch from a food truck.", category: "markets", price: 0, photo: "https://images.unsplash.com/photo-1488459716781-31db52582fe9?w=900", miles: 1.5, tags: ["Free", "Outdoors"]),
        CardSeed(activity: "Bubble tea run", venue: "Lotus Tea Bar", address: "905 N St Mary's St", description: "A quick afternoon treat with plenty of seating if you want to linger.", category: "food", price: 1, photo: nil, miles: 0.9, tags: ["$", "Chill"]),
        CardSeed(activity: "Climbing gym", venue: "Granite Works", address: "6100 Broadway", description: "Beginner-friendly bouldering. Shoe rental included with a day pass.", category: "active", price: 2, photo: nil, miles: 3.6, tags: ["$$", "Indoors", "Active"]),
        CardSeed(activity: "Outdoor movie", venue: "Alder Park Lawn", address: "100 Alder Park Dr", description: "Bring a blanket. Food trucks park nearby before the screening starts.", category: "arts", price: 0, photo: nil, miles: 1.2, tags: ["Free", "Outdoors"]),
        CardSeed(activity: "Museum wander", venue: "Blue Star Arts Museum", address: "116 Blue Star", description: "Small rotating exhibits you can see in an hour, plus a good gift shop.", category: "arts", price: 1, photo: nil, miles: 2.2, tags: ["$", "Indoors"]),
        CardSeed(activity: "Live music", venue: "The Lonesome Rose", address: "2114 N St Mary's St", description: "Local bands most nights and a big back patio.", category: "arts", price: 2, photo: nil, miles: 2.7, tags: ["$$", "Lively"]),
        CardSeed(activity: "Brunch", venue: "Sunny Side Kitchen", address: "540 Broadway", description: "Big plates, bottomless coffee and tables that fit a crowd.", category: "food", price: 2, photo: nil, miles: 1.9, tags: ["$$", "Chill"]),
    ]

    /// 3 × active members cards at the winning slot time. The pool is ordered by the group's
    /// survey answers (the user's real answers + the demo friends' presets).
    func generateCards(hangoutId: String, round: Int) -> [HangoutCard] {
        guard let h = hangouts[hangoutId] else { return [] }
        let count: Int = max(2, activeMembers(hangoutId).count) * 3
        let start: Date = h.winningSlot?.start ?? MockStore.date(dayOffset: 2, hour: 15)
        let end: Date = h.winningSlot?.end ?? start.addingTimeInterval(3600)
        let answers: [[String: SurveyAnswer]] = Array((surveyAnswers[hangoutId] ?? [:]).values)
        let ranked: [CardSeed] = cardPool.enumerated().sorted { a, b in
            let sa: Int = DemoPersona.groupScore(category: a.element.category, priceLevel: a.element.price, answers: answers)
            let sb: Int = DemoPersona.groupScore(category: b.element.category, priceLevel: b.element.price, answers: answers)
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }.map { $0.element }
        var out: [HangoutCard] = []
        for i in 0..<count {
            let seed: CardSeed = ranked[(i + (round - 1) * 5) % ranked.count]
            var card = HangoutCard(round: round, activity: seed.activity, description: seed.description,
                                   category: seed.category, venueName: seed.venue, address: seed.address,
                                   lat: 29.42 + Double(i) * 0.003, lng: -98.49 - Double(i) * 0.002,
                                   distanceMiles: seed.miles, priceLevel: seed.price, photoUrl: seed.photo,
                                   placeId: "mock_place_\(i)", start: start, end: end, tags: seed.tags)
            card.id = "\(hangoutId)_r\(round)_c\(i + 1)"
            out.append(card)
        }
        return out
    }

    // MARK: Simulation: state machine

    /// Pretend every other active/invited member has done `step` (so the demo advances on
    /// the current user's input alone).
    func simulateOthers(_ hangoutId: String, except uid: String, _ change: (inout HangoutMember) -> Void) {
        guard let all = members[hangoutId] else { return }
        for (memberUid, m) in all where memberUid != uid && (m.state == .active || m.state == .invited) {
            var copy: HangoutMember = m
            copy.state = .active
            change(&copy)
            members[hangoutId]?[memberUid] = copy
        }
    }

    /// Winner over votes (CLAUDE.md "Deciding a winner"): all-yes, else all yes-or-maybe;
    /// best = most yes, fewest maybe, then earliest.
    func pickWinner(optionIds: [String], startOf: (String) -> Date, votes: [String: [String: Vote]], voters: [String]) -> String? {
        func tally(_ id: String) -> (yes: Int, maybe: Int, no: Int) {
            var y = 0, m = 0, n = 0
            for v in voters {
                switch votes[v]?[id] {
                case .some(.yes): y += 1
                case .some(.maybe): m += 1
                default: n += 1
                }
            }
            return (y, m, n)
        }
        let allYes: [String] = optionIds.filter { tally($0).yes == voters.count }
        let pool: [String] = allYes.isEmpty ? optionIds.filter { tally($0).no == 0 } : allYes
        let sorted: [String] = pool.sorted { a, b in
            let ta = tally(a), tb = tally(b)
            if ta.yes != tb.yes { return ta.yes > tb.yes }
            if ta.maybe != tb.maybe { return ta.maybe < tb.maybe }
            return startOf(a) < startOf(b)
        }
        return sorted.first
    }

    /// Demo mode: a friend's preset time votes (`DemoPersona` in MockStore.swift). Keeps any vote they
    /// already have.
    func fillPresetTimeVotes(hangoutId: String, uid: String) {
        var theirs: [String: Vote] = timeVotes[hangoutId]?[uid] ?? [:]
        let persona: DemoPersona = DemoPersona.forUser(uid)
        for slot in slots[hangoutId] ?? [] where slot.offerOnly != true && theirs[slot.id] == nil {
            theirs[slot.id] = persona.timeVote(for: slot)
        }
        timeVotes[hangoutId, default: [:]][uid] = theirs
    }

    /// Demo mode: a friend's preset card votes for one round.
    func fillPresetCardVotes(hangoutId: String, uid: String, round: Int) {
        var theirs: [String: Vote] = cardVotes[hangoutId]?[round]?[uid] ?? [:]
        let persona: DemoPersona = DemoPersona.forUser(uid)
        for card in (cards[hangoutId] ?? []) where card.round == round && theirs[card.id] == nil {
            theirs[card.id] = persona.cardVote(for: card)
        }
        cardVotes[hangoutId, default: [:]][round, default: [:]][uid] = theirs
    }

    /// Demo mode: a friend's preset survey answers.
    func fillPresetSurvey(hangoutId: String, uid: String) {
        guard surveyAnswers[hangoutId]?[uid] == nil else { return }
        surveyAnswers[hangoutId, default: [:]][uid] = DemoPersona.forUser(uid).surveyAnswers
    }

    // MARK: Seed

    private func seed() {
        let homes: [String: Location] = [
            Ids.zach: Location(text: "Southtown, San Antonio", lat: 29.41, lng: -98.49),
            Ids.seth: Location(text: "Pearl District, San Antonio", lat: 29.44, lng: -98.48),
            Ids.matt: Location(text: "Alamo Heights, San Antonio", lat: 29.48, lng: -98.46),
            Ids.claire: Location(text: "Tobin Hill, San Antonio", lat: 29.45, lng: -98.49),
            Ids.ava: Location(text: "King William, San Antonio", lat: 29.41, lng: -98.50),
            Ids.noah: Location(text: "Monte Vista, San Antonio", lat: 29.46, lng: -98.50),
        ]
        let people: [(String, String, String)] = [
            (Ids.zach, "Zach Weiss", MockStore.zachPhone),
            (Ids.seth, "Seth Fox", "+15555550101"),
            (Ids.matt, "Matt Hill", "+15555550102"),
            (Ids.claire, "Claire Kim", "+15555550103"),
            (Ids.ava, "Ava Lopez", "+15555550104"),
            (Ids.noah, "Noah Park", "+15555550106"),
        ]
        let friendsOfZach: [String] = [Ids.seth, Ids.matt, Ids.claire, Ids.ava]
        for (uid, name, phone) in people {
            var friendIds: [String] = []
            if uid == Ids.zach { friendIds = friendsOfZach }
            else if uid != Ids.noah { friendIds = [Ids.zach] + friendsOfZach.filter { $0 != uid } }
            let profile = UserProfile(id: uid, phone: phone, name: name, photoURL: nil, homeLocation: homes[uid],
                                      bufferMinutes: 15,
                                      interests: uid == Ids.zach ? "Coffee shops, live music, trying new tacos." : "",
                                      calendarConnected: true, friendIds: friendIds,
                                      createdAt: Date().addingTimeInterval(-86_400 * 30))
            users[uid] = profile
            passwords[phone] = MockStore.zachPassword
        }

        let now = Date()

        // 1. votingTimes — Seth's hangout, Zach still needs to swipe 8 times.
        seedHangout(id: Ids.votingTimes, owner: Ids.seth, others: [Ids.zach, Ids.matt, Ids.claire],
                    status: .votingTimes, created: now.addingTimeInterval(-3600 * 5)) { m in
            m.availabilitySubmitted = true
            if m.id != Ids.zach { m.timesDone = true }
        }
        slots[Ids.votingTimes] = generateSlots(hangoutId: Ids.votingTimes, durationMinutes: 60)

        // 2. survey — Zach's hangout with Ava + Matt; time decided, survey pending for Zach.
        seedHangout(id: Ids.survey, owner: Ids.zach, others: [Ids.ava, Ids.matt],
                    status: .survey, durations: [120], created: now.addingTimeInterval(-3600 * 20)) { m in
            m.availabilitySubmitted = true
            m.timesDone = true
            if m.id != Ids.zach { m.surveyDone = true }
        }
        slots[Ids.survey] = generateSlots(hangoutId: Ids.survey, durationMinutes: 120)
        for friend in [Ids.ava, Ids.matt] { fillPresetSurvey(hangoutId: Ids.survey, uid: friend) }
        if let first = slots[Ids.survey]?[3] {
            updateHangout(Ids.survey) { $0.winningSlot = SlotRef(id: first.id, start: first.start, end: first.end) }
        }

        // 3. votingCards — Claire's hangout, 3 people → 9 cards.
        seedHangout(id: Ids.votingCards, owner: Ids.claire, others: [Ids.zach, Ids.seth],
                    status: .votingCards, created: now.addingTimeInterval(-3600 * 30)) { m in
            m.availabilitySubmitted = true
            m.timesDone = true
            m.surveyDone = true
            if m.id != Ids.zach { m.cardsDoneRound = 1 }
        }
        slots[Ids.votingCards] = generateSlots(hangoutId: Ids.votingCards, durationMinutes: 60)
        if let first = slots[Ids.votingCards]?[0] {
            updateHangout(Ids.votingCards) { $0.winningSlot = SlotRef(id: first.id, start: first.start, end: first.end) }
        }
        for friend in [Ids.claire, Ids.seth] { fillPresetSurvey(hangoutId: Ids.votingCards, uid: friend) }
        cards[Ids.votingCards] = generateCards(hangoutId: Ids.votingCards, round: 1)

        // 4. confirmed — Coffee at Juniper Café, 4 going.
        seedHangout(id: Ids.confirmed, owner: Ids.zach, others: [Ids.seth, Ids.matt, Ids.claire],
                    status: .confirmed, created: now.addingTimeInterval(-86_400 * 2)) { m in
            m.availabilitySubmitted = true
            m.timesDone = true
            m.surveyDone = true
            m.cardsDoneRound = 1
        }
        let cStart: Date = MockStore.date(dayOffset: 4, hour: 15)
        let cEnd: Date = cStart.addingTimeInterval(3600)
        updateHangout(Ids.confirmed) { h in
            h.title = "Coffee at Juniper Café"
            h.winningSlot = SlotRef(id: "\(Ids.confirmed)_slot1", start: cStart, end: cEnd)
            h.confirmed = ConfirmedPlan(start: cStart, end: cEnd, activity: "Coffee + pastries",
                                        venueName: "Juniper Café", address: "412 Alamo St", cardId: "\(Ids.confirmed)_r1_c1")
        }

        // 5. noAgreement — round 1 finished with no winner (top 3 shown with everyone's votes).
        seedHangout(id: Ids.noAgreement, owner: Ids.matt, others: [Ids.zach, Ids.ava],
                    status: .noAgreement, created: now.addingTimeInterval(-3600 * 40)) { m in
            m.availabilitySubmitted = true
            m.timesDone = true
            m.surveyDone = true
            m.cardsDoneRound = 1
        }
        slots[Ids.noAgreement] = generateSlots(hangoutId: Ids.noAgreement, durationMinutes: 120)
        if let s = slots[Ids.noAgreement]?[4] {
            updateHangout(Ids.noAgreement) { $0.winningSlot = SlotRef(id: s.id, start: s.start, end: s.end) }
        }
        let naCards: [HangoutCard] = generateCards(hangoutId: Ids.noAgreement, round: 1)
        cards[Ids.noAgreement] = naCards
        var naVotes: [String: [String: Vote]] = [:]
        let voters: [String] = [Ids.zach, Ids.matt, Ids.ava]
        for (vi, voter) in voters.enumerated() {
            var v: [String: Vote] = [:]
            for (ci, card) in naCards.enumerated() {
                // Each card gets at least one "no", so nothing wins.
                if ci % 3 == vi { v[card.id] = .no }
                else if (ci + vi) % 2 == 0 { v[card.id] = .yes }
                else { v[card.id] = .maybe }
            }
            naVotes[voter] = v
        }
        cardVotes[Ids.noAgreement] = [1: naVotes]

        // 6. noMutualTime — Ava's hangout; fallback "all but one" slots, Matt missing.
        seedHangout(id: Ids.noMutualTime, owner: Ids.ava, others: [Ids.zach, Ids.matt],
                    status: .noMutualTime, created: now.addingTimeInterval(-3600 * 10)) { m in
            m.availabilitySubmitted = true
            m.timesDone = true
        }
        updateHangout(Ids.noMutualTime) { h in
            h.horizonDays = 30
            h.statusMessage = "No time works for everyone in the next month."
        }
        slots[Ids.noMutualTime] = generateFallbackSlots(hangoutId: Ids.noMutualTime, missing: Ids.matt)

        // 7. collectingAvailability — Matt just invited Zach (Zach is `invited`).
        seedHangout(id: Ids.collecting, owner: Ids.matt, others: [Ids.zach, Ids.claire, Ids.ava],
                    status: .collectingAvailability, created: now.addingTimeInterval(-600)) { m in
            if m.id == Ids.zach { m.state = .invited }
            else if m.id == Ids.matt { m.availabilitySubmitted = true }
        }
    }

    private func seedHangout(id: String, owner: String, others: [String], status: HangoutStatus,
                             durations: [Int] = [60], created: Date,
                             configure: (inout HangoutMember) -> Void) {
        let all: [String] = [owner] + others
        var h = Hangout(ownerId: owner, mode: .timeAndActivity, durationsMinutes: durations, memberIds: all)
        h.id = id
        h.status = status
        h.createdAt = created
        h.updatedAt = created
        hangouts[id] = h
        var dict: [String: HangoutMember] = [:]
        for uid in all {
            var m: HangoutMember = makeMember(uid, role: uid == owner ? .owner : .member, state: .active)
            configure(&m)
            dict[uid] = m
        }
        members[id] = dict
    }

    /// Gives a freshly signed-up mock user something to look at: friends, plus a seat in the
    /// votingTimes hangout and an invite to the collecting one.
    func enrollNewUser(uid: String) {
        for friend in [Ids.seth, Ids.matt, Ids.claire, Ids.ava] {
            users[friend]?.friendIds.append(uid)
        }
        users[uid]?.friendIds = [Ids.seth, Ids.matt, Ids.claire, Ids.ava]
        for (hid, state) in [(Ids.votingTimes, MemberState.active), (Ids.collecting, MemberState.invited)] {
            var m: HangoutMember = makeMember(uid, role: .member, state: state)
            if hid == Ids.votingTimes { m.availabilitySubmitted = true }
            members[hid]?[uid] = m
            updateHangout(hid) { $0.memberIds.append(uid) }
        }
    }

    /// Keeps denormalized member names in sync after a profile edit.
    func syncMemberNames(uid: String) {
        guard let name = users[uid]?.name else { return }
        for hid in Array(members.keys) where members[hid]?[uid] != nil {
            members[hid]?[uid]?.name = name
        }
    }
}

// MARK: - Demo mode preset friends

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
