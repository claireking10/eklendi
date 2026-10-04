import Foundation
import Observation

/// Live view of one hangout: the hangout document, its members, slots and the current
/// round's cards, plus the signed-in user's profile. Owned by HangoutFlowView.
@MainActor
@Observable
final class HFHangoutStore {
    var hangout: Hangout? = nil
    var hangoutLoaded: Bool = false
    var members: [HangoutMember] = []
    var membersLoaded: Bool = false
    var slots: [TimeSlot] = []
    var cards: [HangoutCard] = []
    var cardsRound: Int = 0
    var myProfile: UserProfile? = nil

    @ObservationIgnored private var subscriptions: [Cancellable] = []
    @ObservationIgnored private var cardSubscription: Cancellable? = nil
    @ObservationIgnored private var startedId: String? = nil
    @ObservationIgnored private weak var env: AppEnvironment? = nil

    init() {}

    /// Starts the listeners once per hangout id (safe to call from every `.task`).
    func start(env: AppEnvironment, hangoutId: String) {
        guard startedId != hangoutId else { return }
        startedId = hangoutId
        self.env = env
        stop()
        let repo: HangoutRepository = env.hangouts
        subscriptions.append(repo.observeHangout(id: hangoutId) { [weak self] value in
            guard let self = self else { return }
            self.hangout = value
            self.hangoutLoaded = true
            if let value = value {
                self.observeCards(hangoutId: hangoutId, round: value.round)
            }
        })
        subscriptions.append(repo.observeMembers(hangoutId: hangoutId) { [weak self] list in
            guard let self = self else { return }
            self.members = list
            self.membersLoaded = true
        })
        subscriptions.append(repo.observeSlots(hangoutId: hangoutId) { [weak self] list in
            guard let self = self else { return }
            self.slots = list.sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.start < b.start
            }
        })
    }

    private func observeCards(hangoutId: String, round: Int) {
        guard round != cardsRound || cardSubscription == nil, let env = env else { return }
        cardsRound = round
        cards = []
        cardSubscription?.cancel()
        cardSubscription = env.hangouts.observeCards(hangoutId: hangoutId, round: round) { [weak self] list in
            guard let self = self else { return }
            self.cards = list
        }
    }

    func stop() {
        for s in subscriptions { s.cancel() }
        subscriptions = []
        cardSubscription?.cancel()
        cardSubscription = nil
        cardsRound = 0
    }

    func loadProfile(env: AppEnvironment, uid: String) async {
        if myProfile != nil { return }
        myProfile = try? await env.users.profile(uid: uid)
    }

    // MARK: Derived

    func me(_ uid: String) -> HangoutMember? {
        members.first { $0.id == uid }
    }

    func isOwner(_ uid: String) -> Bool {
        hangout?.ownerId == uid
    }

    /// Active members (the ones who vote).
    var participants: [HangoutMember] {
        members.filter { $0.state == .active }
    }

    /// Active + invited (everyone still in the group).
    var inGroup: [HangoutMember] {
        HFRouting.countable(members)
    }

    /// Slots to swipe on (never the 08b offers).
    var votableSlots: [TimeSlot] {
        slots.filter { $0.offerOnly != true }
    }

    /// 08b alternatives: server-flagged offers, or fallback slots (mock backend).
    var offerSlots: [TimeSlot] {
        let flagged: [TimeSlot] = slots.filter { $0.offerOnly == true }
        if !flagged.isEmpty { return flagged.sorted { $0.start < $1.start } }
        return slots.filter { $0.source == .fallback }.sorted { $0.start < $1.start }
    }

    func displayName(uid: String) -> String {
        guard let h = hangout else { return "Hangout" }
        return HFFormat.displayName(hangout: h, members: members, myUid: uid)
    }

    func memberName(_ memberUid: String) -> String {
        if let m = members.first(where: { $0.id == memberUid }) { return HFFormat.firstName(m.name) }
        return "Someone"
    }

    /// Lanes for the day view: everyone still in the group, me first as "You".
    func lanes(myUid: String) -> [HFLane] {
        let group: [HangoutMember] = inGroup
        var mine: [HFLane] = []
        var others: [HFLane] = []
        for m in group {
            let lane = HFLane(uid: m.id, name: HFFormat.shortName(m, myUid: myUid), busy: m.busy,
                              bufferMinutes: m.bufferMinutes)
            if m.id == myUid { mine.append(lane) } else { others.append(lane) }
        }
        return mine + others
    }
}
