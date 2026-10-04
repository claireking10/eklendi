import Foundation

/// In-memory hangouts + subcollections, with a simulated state machine so the whole demo
/// flow works offline: after the signed-in user finishes a step, the other members are
/// simulated as finishing it too and the hangout advances after a short delay.
@MainActor
final class MockHangoutRepository: HangoutRepository {
    private let store: MockStore

    init(store: MockStore) {
        self.store = store
    }

    // MARK: Listeners

    func observeMyHangouts(uid: String, onChange: @escaping ([Hangout]) -> Void) -> Cancellable {
        store.observe { [weak store = self.store] in
            guard let store = store else { return }
            let list: [Hangout] = store.hangouts.values
                .filter { $0.memberIds.contains(uid) }
                .sorted { $0.createdAt > $1.createdAt }
            onChange(list)
        }
    }

    func observeHangout(id: String, onChange: @escaping (Hangout?) -> Void) -> Cancellable {
        store.observe { [weak store = self.store] in
            onChange(store?.hangouts[id])
        }
    }

    func observeMembers(hangoutId: String, onChange: @escaping ([HangoutMember]) -> Void) -> Cancellable {
        store.observe { [weak store = self.store] in
            guard let store = store else { return }
            let list: [HangoutMember] = (store.members[hangoutId] ?? [:]).values.sorted { a, b in
                if a.role != b.role { return a.role == .owner }
                return a.name < b.name
            }
            onChange(list)
        }
    }

    func observeSlots(hangoutId: String, onChange: @escaping ([TimeSlot]) -> Void) -> Cancellable {
        store.observe { [weak store = self.store] in
            guard let store = store else { return }
            let list: [TimeSlot] = (store.slots[hangoutId] ?? []).sorted { $0.rank < $1.rank }
            onChange(list)
        }
    }

    func observeCards(hangoutId: String, round: Int, onChange: @escaping ([HangoutCard]) -> Void) -> Cancellable {
        store.observe { [weak store = self.store] in
            guard let store = store else { return }
            let list: [HangoutCard] = (store.cards[hangoutId] ?? []).filter { $0.round == round }
            onChange(list)
        }
    }

    // MARK: Create / join

    func createHangout(owner: UserProfile, invitees: [UserProfile], mode: HangoutMode, planDescription: String,
                       durationsMinutes: [Int], durationAny: Bool) async throws -> String {
        guard !invitees.isEmpty else { throw MockServiceError("Invite at least one friend.") }
        guard invitees.count <= 7 else { throw MockServiceError("A hangout can have at most 8 people.") }
        try await Task.sleep(nanoseconds: 200_000_000)
        let id: String = store.newId("h")
        let memberIds: [String] = [owner.id] + invitees.map { $0.id }
        var h = Hangout(ownerId: owner.id, mode: mode, durationsMinutes: durationsMinutes, memberIds: memberIds)
        h.id = id
        h.planDescription = planDescription
        h.durationAny = durationAny
        h.status = .collectingAvailability
        store.hangouts[id] = h
        var dict: [String: HangoutMember] = [:]
        dict[owner.id] = store.makeMember(owner.id, role: .owner, state: .active)
        for friend in invitees {
            if store.users[friend.id] == nil { store.users[friend.id] = friend }
            dict[friend.id] = store.makeMember(friend.id, role: .member, state: .invited)
        }
        store.members[id] = dict
        store.notify()

        // Simulate the invitees opening the hangout and sharing availability.
        store.later(2.0) { [weak self] in
            guard let self = self else { return }
            self.store.simulateOthers(id, except: owner.id) { m in
                m.availabilitySubmitted = true
            }
            self.store.notify()
            self.advance(id)
        }
        return id
    }

    func join(hangoutId: String, uid: String) async throws {
        guard store.members[hangoutId]?[uid] != nil else { throw MockServiceError("You're not in this hangout.") }
        store.updateMember(hangoutId, uid) { m in
            if m.state == .invited { m.state = .active }
        }
        store.notify()
    }

    func setStartLocation(hangoutId: String, uid: String, location: Location) async throws {
        store.updateMember(hangoutId, uid) { $0.startLocation = location }
        store.notify()
    }

    // MARK: Member inputs

    func submitAvailability(hangoutId: String, uid: String, busy: [BusyBlock], bufferMinutes: Int) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        store.updateMember(hangoutId, uid) { m in
            m.state = .active
            m.busy = busy
            m.bufferMinutes = bufferMinutes
            m.availabilitySubmitted = true
            m.timeZone = TimeZone.current.identifier
        }
        store.notify()
        store.later { [weak self] in
            guard let self = self else { return }
            self.store.simulateOthers(hangoutId, except: uid) { m in
                m.availabilitySubmitted = true
            }
            self.advance(hangoutId)
        }
    }

    func submitTimeVotes(hangoutId: String, uid: String, votes: [String: Vote]) async throws {
        var mine: [String: Vote] = store.timeVotes[hangoutId]?[uid] ?? [:]
        for (k, v) in votes { mine[k] = v }
        store.timeVotes[hangoutId, default: [:]][uid] = mine
        store.updateMember(hangoutId, uid) { $0.timesDone = true }
        store.notify()
        let snapshot: [String: Vote] = mine
        store.later { [weak self] in
            guard let self = self else { return }
            let mirrored: [String: Vote] = self.store.simulatedVotes(from: snapshot)
            let slotIds: [String] = (self.store.slots[hangoutId] ?? []).map { $0.id }
            let others: [String] = Array((self.store.members[hangoutId] ?? [:]).keys).filter { $0 != uid }
            for other in others {
                var theirs: [String: Vote] = self.store.timeVotes[hangoutId]?[other] ?? [:]
                for sid in slotIds where theirs[sid] == nil {
                    theirs[sid] = mirrored[sid] ?? .yes
                }
                self.store.timeVotes[hangoutId, default: [:]][other] = theirs
            }
            self.store.simulateOthers(hangoutId, except: uid) { m in
                m.availabilitySubmitted = true
                m.timesDone = true
            }
            self.advance(hangoutId)
        }
    }

    func submitSurvey(hangoutId: String, uid: String, answers: [String: SurveyAnswer]) async throws {
        store.surveyAnswers[hangoutId, default: [:]][uid] = answers
        store.updateMember(hangoutId, uid) { $0.surveyDone = true }
        store.notify()
        store.later { [weak self] in
            guard let self = self else { return }
            self.store.simulateOthers(hangoutId, except: uid) { m in
                m.surveyDone = true
            }
            self.advance(hangoutId)
        }
    }

    func submitCardVotes(hangoutId: String, uid: String, round: Int, votes: [String: Vote]) async throws {
        var roundVotes: [String: [String: Vote]] = store.cardVotes[hangoutId]?[round] ?? [:]
        var mine: [String: Vote] = roundVotes[uid] ?? [:]
        for (k, v) in votes { mine[k] = v }
        roundVotes[uid] = mine
        store.cardVotes[hangoutId, default: [:]][round] = roundVotes
        store.updateMember(hangoutId, uid) { $0.cardsDoneRound = round }
        store.notify()
        let snapshot: [String: Vote] = mine
        store.later { [weak self] in
            guard let self = self else { return }
            let mirrored: [String: Vote] = self.store.simulatedVotes(from: snapshot)
            let cardIds: [String] = (self.store.cards[hangoutId] ?? []).filter { $0.round == round }.map { $0.id }
            var all: [String: [String: Vote]] = self.store.cardVotes[hangoutId]?[round] ?? [:]
            let others: [String] = self.store.activeMembers(hangoutId).map { $0.id }.filter { $0 != uid }
            for other in others {
                var theirs: [String: Vote] = all[other] ?? [:]
                for cid in cardIds where theirs[cid] == nil {
                    theirs[cid] = mirrored[cid] ?? .maybe
                }
                all[other] = theirs
            }
            self.store.cardVotes[hangoutId, default: [:]][round] = all
            self.store.simulateOthers(hangoutId, except: uid) { m in
                m.cardsDoneRound = round
            }
            self.advance(hangoutId)
        }
    }

    func cardVotes(hangoutId: String, round: Int) async throws -> [String: [String: Vote]] {
        store.cardVotes[hangoutId]?[round] ?? [:]
    }

    // MARK: Member / owner actions

    func decline(hangoutId: String, uid: String) async throws {
        store.updateMember(hangoutId, uid) { m in
            m.state = .declined
            m.role = .member
        }
        passOwnershipIfNeeded(hangoutId: hangoutId, leaving: uid)
        store.updateHangout(hangoutId) { $0.memberIds.removeAll { $0 == uid } }
        store.notify()
        advance(hangoutId)
    }

    func setNotGoing(hangoutId: String, uid: String, notGoing: Bool) async throws {
        store.updateMember(hangoutId, uid) { $0.notGoing = notGoing }
        store.notify()
    }

    func nudge(hangoutId: String, memberUid: String) async throws {
        store.updateMember(hangoutId, memberUid) { $0.nudgedAt = Date() }
        store.notify()
    }

    func remove(hangoutId: String, memberUid: String) async throws {
        store.updateMember(hangoutId, memberUid) { m in
            m.state = .removed
            m.role = .member
        }
        passOwnershipIfNeeded(hangoutId: hangoutId, leaving: memberUid)
        store.updateHangout(hangoutId) { $0.memberIds.removeAll { $0 == memberUid } }
        store.notify()
        advance(hangoutId)
    }

    func cancel(hangoutId: String) async throws {
        store.updateHangout(hangoutId) { h in
            h.status = .cancelled
            h.statusMessage = "The owner cancelled this hangout."
        }
        store.notify()
    }

    func reopen(hangoutId: String) async throws {
        store.updateHangout(hangoutId) { h in
            h.status = .collectingAvailability
            h.round += 1
            h.winningSlot = nil
            h.confirmed = nil
            h.title = ""
            h.statusMessage = ""
        }
        let uids: [String] = Array((store.members[hangoutId] ?? [:]).keys)
        for uid in uids {
            store.updateMember(hangoutId, uid) { m in
                m.availabilitySubmitted = false
                m.timesDone = false
                m.surveyDone = false
                m.notGoing = false
            }
        }
        store.slots[hangoutId] = nil
        store.timeVotes[hangoutId] = nil
        store.surveyAnswers[hangoutId] = nil
        store.notify()
    }

    func handOff(hangoutId: String, toUid: String) async throws {
        guard let h = store.hangouts[hangoutId], store.members[hangoutId]?[toUid] != nil else {
            throw MockServiceError("That person isn't in this hangout.")
        }
        store.updateMember(hangoutId, h.ownerId) { $0.role = .member }
        store.updateMember(hangoutId, toUid) { $0.role = .owner }
        store.updateHangout(hangoutId) { $0.ownerId = toUid }
        store.notify()
    }

    private func passOwnershipIfNeeded(hangoutId: String, leaving uid: String) {
        guard let h = store.hangouts[hangoutId], h.ownerId == uid else { return }
        let candidates: [String] = store.activeMembers(hangoutId).map { $0.id }.filter { $0 != uid }
        guard let next = candidates.randomElement() else { return }
        store.updateHangout(hangoutId) { $0.ownerId = next }
        store.updateMember(hangoutId, next) { $0.role = .owner }
    }

    // MARK: Simulated state machine (mirrors docs/ARCHITECTURE.md)

    /// Members who still count: active or invited (invited = pending).
    private func pending(_ hangoutId: String) -> [HangoutMember] {
        (store.members[hangoutId] ?? [:]).values.filter { $0.state == .active || $0.state == .invited }
    }

    func advance(_ hangoutId: String) {
        guard let h = store.hangouts[hangoutId] else { return }
        let people: [HangoutMember] = pending(hangoutId)
        let everyoneActive: Bool = people.allSatisfy { $0.state == .active }
        guard people.count >= 2 else {
            store.updateHangout(hangoutId) { $0.statusMessage = "Fewer than 2 people left in this hangout." }
            store.notify()
            return
        }

        switch h.status {
        case .collectingAvailability:
            guard everyoneActive, people.allSatisfy({ $0.availabilitySubmitted }) else { return }
            let duration: Int = h.durationAny ? 60 : (h.durationsMinutes.min() ?? 60)
            store.slots[hangoutId] = store.generateSlots(hangoutId: hangoutId, durationMinutes: duration)
            store.timeVotes[hangoutId] = nil
            for m in people { store.updateMember(hangoutId, m.id) { $0.timesDone = false } }
            store.updateHangout(hangoutId) { $0.status = .votingTimes }
            store.notify()

        case .votingTimes:
            guard everyoneActive, people.allSatisfy({ $0.timesDone }) else { return }
            let options: [TimeSlot] = store.slots[hangoutId] ?? []
            let voters: [String] = people.map { $0.id }
            let winner: String? = store.pickWinner(
                optionIds: options.map { $0.id },
                startOf: { id in options.first(where: { $0.id == id })?.start ?? Date.distantFuture },
                votes: store.timeVotes[hangoutId] ?? [:],
                voters: voters)
            if let winnerId = winner, let slot = options.first(where: { $0.id == winnerId }) {
                let ref = SlotRef(id: slot.id, start: slot.start, end: slot.end)
                if h.mode == .timeOnly {
                    store.updateHangout(hangoutId) { hh in
                        hh.winningSlot = ref
                        hh.title = hh.planDescription
                        hh.confirmed = ConfirmedPlan(start: slot.start, end: slot.end, activity: hh.planDescription,
                                                     venueName: "", address: "", cardId: nil)
                        hh.status = .confirmed
                    }
                } else {
                    store.updateHangout(hangoutId) { hh in
                        hh.winningSlot = ref
                        hh.status = .survey
                    }
                }
            } else {
                let missing: String = voters.first(where: { $0 != h.ownerId }) ?? h.ownerId
                let fallback: [TimeSlot] = store.generateFallbackSlots(hangoutId: hangoutId, missing: missing)
                store.slots[hangoutId] = options.filter { $0.source != .fallback } + fallback
                store.updateHangout(hangoutId) { hh in
                    hh.status = .noMutualTime
                    hh.horizonDays = 30
                    hh.statusMessage = "No time works for everyone. Here are times where all but one person is free."
                }
            }
            store.notify()

        case .survey:
            guard everyoneActive, people.allSatisfy({ $0.surveyDone }) else { return }
            let round: Int = h.round
            store.updateHangout(hangoutId) { $0.status = .generating }
            store.notify()
            store.later(1.5) { [weak store = self.store] in
                guard let store = store, store.hangouts[hangoutId]?.status == .generating else { return }
                let newCards: [HangoutCard] = store.generateCards(hangoutId: hangoutId, round: round)
                store.cards[hangoutId] = (store.cards[hangoutId] ?? []).filter { $0.round != round } + newCards
                store.updateHangout(hangoutId) { $0.status = .votingCards }
                store.notify()
            }

        case .votingCards:
            guard everyoneActive, people.allSatisfy({ $0.cardsDoneRound >= h.round }) else { return }
            let roundCards: [HangoutCard] = (store.cards[hangoutId] ?? []).filter { $0.round == h.round }
            let winner: String? = store.pickWinner(
                optionIds: roundCards.map { $0.id },
                startOf: { id in roundCards.first(where: { $0.id == id })?.start ?? Date.distantFuture },
                votes: store.cardVotes[hangoutId]?[h.round] ?? [:],
                voters: people.map { $0.id })
            if let winnerId = winner, let card = roundCards.first(where: { $0.id == winnerId }) {
                store.updateHangout(hangoutId) { hh in
                    hh.title = "\(card.activity) at \(card.venueName)"
                    hh.confirmed = ConfirmedPlan(start: card.start, end: card.end, activity: card.activity,
                                                 venueName: card.venueName, address: card.address, cardId: card.id)
                    hh.status = .confirmed
                }
            } else {
                store.updateHangout(hangoutId) { $0.status = .noAgreement }
            }
            store.notify()

        default:
            store.notify()
        }
    }
}
