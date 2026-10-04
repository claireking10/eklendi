import Foundation
import FirebaseFirestore

/// hangouts/{id} and its subcollections (docs/ARCHITECTURE.md). Cloud Functions advance the
/// state machine; the app only writes member inputs and owner actions.
@MainActor
final class FirebaseHangoutRepository: HangoutRepository {
    private var db: Firestore { Firestore.firestore() }

    private func hangoutRef(_ id: String) -> DocumentReference {
        db.collection("hangouts").document(id)
    }

    private func memberRef(_ hangoutId: String, _ uid: String) -> DocumentReference {
        hangoutRef(hangoutId).collection("members").document(uid)
    }

    // MARK: Decoding (nonisolated so listener callbacks can use them on any thread)

    nonisolated static func decodeHangout(_ snap: DocumentSnapshot) -> Hangout? {
        guard snap.exists else { return nil }
        guard var h = FirestoreSupport.decode(Hangout.self, data: snap.data(),
                                              defaults: FirestoreSupport.hangoutDefaults) else { return nil }
        h.id = snap.documentID
        return h
    }

    nonisolated static func decodeMember(_ snap: DocumentSnapshot) -> HangoutMember? {
        guard var m = FirestoreSupport.decode(HangoutMember.self, data: snap.data(),
                                              defaults: FirestoreSupport.memberDefaults) else { return nil }
        m.id = snap.documentID
        return m
    }

    nonisolated static func decodeSlot(_ snap: DocumentSnapshot) -> TimeSlot? {
        guard var s = FirestoreSupport.decode(TimeSlot.self, data: snap.data(),
                                              defaults: FirestoreSupport.slotDefaults) else { return nil }
        s.id = snap.documentID
        return s
    }

    nonisolated static func decodeCard(_ snap: DocumentSnapshot) -> HangoutCard? {
        guard var c = FirestoreSupport.decode(HangoutCard.self, data: snap.data(),
                                              defaults: FirestoreSupport.cardDefaults) else { return nil }
        c.id = snap.documentID
        return c
    }

    nonisolated static func voteMap(_ raw: Any?) -> [String: Vote] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: [String: Vote] = [:]
        for (key, value) in dict {
            if let s = value as? String, let v = Vote(rawValue: s) { out[key] = v }
        }
        return out
    }

    // MARK: Listeners

    func observeMyHangouts(uid: String, onChange: @escaping ([Hangout]) -> Void) -> Cancellable {
        let registration: ListenerRegistration = db.collection("hangouts")
            .whereField("memberIds", arrayContains: uid)
            .addSnapshotListener { snap, error in
                if let error = error { print("[Hangouts] my hangouts listener: \(error)") }
                guard let snap = snap else { return }
                let list: [Hangout] = snap.documents
                    .compactMap { FirebaseHangoutRepository.decodeHangout($0) }
                    .sorted { $0.createdAt > $1.createdAt }
                FirestoreSupport.onMain { onChange(list) }
            }
        return Cancellable { registration.remove() }
    }

    func observeHangout(id: String, onChange: @escaping (Hangout?) -> Void) -> Cancellable {
        let registration: ListenerRegistration = hangoutRef(id).addSnapshotListener { snap, error in
            if let error = error { print("[Hangouts] hangout listener: \(error)") }
            guard let snap = snap else { return }
            let hangout: Hangout? = FirebaseHangoutRepository.decodeHangout(snap)
            FirestoreSupport.onMain { onChange(hangout) }
        }
        return Cancellable { registration.remove() }
    }

    func observeMembers(hangoutId: String, onChange: @escaping ([HangoutMember]) -> Void) -> Cancellable {
        let registration: ListenerRegistration = hangoutRef(hangoutId).collection("members")
            .addSnapshotListener { snap, error in
                if let error = error { print("[Hangouts] members listener: \(error)") }
                guard let snap = snap else { return }
                let members: [HangoutMember] = snap.documents
                    .compactMap { FirebaseHangoutRepository.decodeMember($0) }
                    .sorted { a, b in
                        if a.role != b.role { return a.role == .owner }
                        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }
                FirestoreSupport.onMain { onChange(members) }
            }
        return Cancellable { registration.remove() }
    }

    func observeSlots(hangoutId: String, onChange: @escaping ([TimeSlot]) -> Void) -> Cancellable {
        let registration: ListenerRegistration = hangoutRef(hangoutId).collection("slots")
            .addSnapshotListener { snap, error in
                if let error = error { print("[Hangouts] slots listener: \(error)") }
                guard let snap = snap else { return }
                let slots: [TimeSlot] = snap.documents
                    .compactMap { FirebaseHangoutRepository.decodeSlot($0) }
                    .sorted { a, b in
                        if a.rank != b.rank { return a.rank < b.rank }
                        return a.start < b.start
                    }
                FirestoreSupport.onMain { onChange(slots) }
            }
        return Cancellable { registration.remove() }
    }

    func observeCards(hangoutId: String, round: Int, onChange: @escaping ([HangoutCard]) -> Void) -> Cancellable {
        let registration: ListenerRegistration = hangoutRef(hangoutId).collection("cards")
            .whereField("round", isEqualTo: round)
            .addSnapshotListener { snap, error in
                if let error = error { print("[Hangouts] cards listener: \(error)") }
                guard let snap = snap else { return }
                let cards: [HangoutCard] = snap.documents.compactMap { FirebaseHangoutRepository.decodeCard($0) }
                FirestoreSupport.onMain { onChange(cards) }
            }
        return Cancellable { registration.remove() }
    }

    // MARK: Create / join / inputs

    func createHangout(owner: UserProfile, invitees: [UserProfile], mode: HangoutMode, planDescription: String,
                       durationsMinutes: [Int], durationAny: Bool) async throws -> String {
        guard !owner.id.isEmpty else { throw EklendiServiceError.notSignedIn }
        let ref: DocumentReference = db.collection("hangouts").document()
        let others: [UserProfile] = invitees.filter { $0.id != owner.id && !$0.id.isEmpty }
        let now = Date()
        let hangout = Hangout(
            ownerId: owner.id,
            mode: mode,
            planDescription: planDescription,
            durationsMinutes: durationsMinutes,
            durationAny: durationAny,
            memberIds: [owner.id] + others.map { $0.id },
            status: .collectingAvailability,
            horizonDays: 14,
            round: 1,
            createdAt: now,
            updatedAt: now
        )
        let batch: WriteBatch = db.batch()
        let hangoutData: [String: Any] = try FirestoreSupport.encode(hangout)
        batch.setData(hangoutData, forDocument: ref)

        let ownerMember = HangoutMember(name: owner.name, role: .owner, state: .active,
                                        bufferMinutes: owner.bufferMinutes, startLocation: owner.homeLocation)
        let ownerData: [String: Any] = try FirestoreSupport.encode(ownerMember)
        batch.setData(ownerData, forDocument: ref.collection("members").document(owner.id))
        for invitee in others {
            let member = HangoutMember(name: invitee.name, role: .member, state: .invited,
                                       bufferMinutes: invitee.bufferMinutes, startLocation: invitee.homeLocation)
            let memberData: [String: Any] = try FirestoreSupport.encode(member)
            batch.setData(memberData, forDocument: ref.collection("members").document(invitee.id))
        }
        try await batch.commit()
        return ref.documentID
    }

    func join(hangoutId: String, uid: String) async throws {
        let ref = memberRef(hangoutId, uid)
        let snap: DocumentSnapshot = try await ref.getDocument()
        guard let state = snap.data()?["state"] as? String, state == MemberState.invited.rawValue else { return }
        try await ref.updateData(["state": MemberState.active.rawValue])
    }

    func setStartLocation(hangoutId: String, uid: String, location: Location) async throws {
        try await memberRef(hangoutId, uid).updateData(["startLocation": FirestoreSupport.locationData(location)])
    }

    func submitAvailability(hangoutId: String, uid: String, busy: [BusyBlock], bufferMinutes: Int) async throws {
        let busyData: [[String: Any]] = busy.map { block in
            ["start": Timestamp(date: block.start), "end": Timestamp(date: block.end)]
        }
        try await memberRef(hangoutId, uid).updateData([
            "busy": busyData,
            "bufferMinutes": bufferMinutes,
            "availabilitySubmitted": true,
            "timeZone": TimeZone.current.identifier,
        ])
    }

    func submitTimeVotes(hangoutId: String, uid: String, votes: [String: Vote]) async throws {
        let batch: WriteBatch = db.batch()
        let voteData: [String: String] = votes.mapValues { $0.rawValue }
        // merge: a suggested-time re-swipe sends only the new slot's vote; keep earlier votes.
        batch.setData(["votes": voteData],
                      forDocument: hangoutRef(hangoutId).collection("timeVotes").document(uid), merge: true)
        batch.updateData(["timesDone": true], forDocument: memberRef(hangoutId, uid))
        try await batch.commit()
    }

    func submitSurvey(hangoutId: String, uid: String, answers: [String: SurveyAnswer]) async throws {
        let batch: WriteBatch = db.batch()
        let answerData: [String: String] = answers.mapValues { $0.rawValue }
        batch.setData(["answers": answerData],
                      forDocument: hangoutRef(hangoutId).collection("surveyAnswers").document(uid))
        batch.updateData(["surveyDone": true], forDocument: memberRef(hangoutId, uid))
        try await batch.commit()
    }

    func submitCardVotes(hangoutId: String, uid: String, round: Int, votes: [String: Vote]) async throws {
        let batch: WriteBatch = db.batch()
        let voteData: [String: String] = votes.mapValues { $0.rawValue }
        batch.setData(["round": round, "votes": voteData],
                      forDocument: hangoutRef(hangoutId).collection("cardVotes").document("\(uid)_\(round)"))
        batch.updateData(["cardsDoneRound": round], forDocument: memberRef(hangoutId, uid))
        try await batch.commit()
    }

    func cardVotes(hangoutId: String, round: Int) async throws -> [String: [String: Vote]] {
        let snap: QuerySnapshot = try await hangoutRef(hangoutId).collection("cardVotes")
            .whereField("round", isEqualTo: round)
            .getDocuments()
        var out: [String: [String: Vote]] = [:]
        for doc in snap.documents {
            let docId = doc.documentID
            let uid: String
            if let idx = docId.lastIndex(of: "_") {
                uid = String(docId[docId.startIndex..<idx])
            } else {
                uid = docId
            }
            out[uid] = FirebaseHangoutRepository.voteMap(doc.data()["votes"])
        }
        return out
    }

    // MARK: Member / owner actions

    func decline(hangoutId: String, uid: String) async throws {
        let ref = hangoutRef(hangoutId)
        let snap: DocumentSnapshot = try await ref.getDocument()
        let data: [String: Any] = snap.data() ?? [:]
        let ownerId = (data["ownerId"] as? String) ?? ""
        let memberIds = (data["memberIds"] as? [String]) ?? []

        let batch: WriteBatch = db.batch()
        batch.updateData(["state": MemberState.declined.rawValue, "role": MemberRole.member.rawValue],
                         forDocument: memberRef(hangoutId, uid))
        var hangoutUpdate: [String: Any] = [
            "memberIds": FieldValue.arrayRemove([uid]),
            "updatedAt": Timestamp(date: Date()),
        ]
        // If the owner leaves, ownership passes to a random remaining member (CLAUDE.md).
        if ownerId == uid, let newOwner = memberIds.filter({ $0 != uid }).randomElement() {
            hangoutUpdate["ownerId"] = newOwner
            batch.updateData(["role": MemberRole.owner.rawValue], forDocument: memberRef(hangoutId, newOwner))
        }
        batch.updateData(hangoutUpdate, forDocument: ref)
        try await batch.commit()
    }

    func setNotGoing(hangoutId: String, uid: String, notGoing: Bool) async throws {
        try await memberRef(hangoutId, uid).updateData(["notGoing": notGoing])
    }

    func nudge(hangoutId: String, memberUid: String) async throws {
        try await memberRef(hangoutId, memberUid).updateData(["nudgedAt": Timestamp(date: Date())])
    }

    func remove(hangoutId: String, memberUid: String) async throws {
        let batch: WriteBatch = db.batch()
        batch.updateData(["state": MemberState.removed.rawValue], forDocument: memberRef(hangoutId, memberUid))
        batch.updateData([
            "memberIds": FieldValue.arrayRemove([memberUid]),
            "updatedAt": Timestamp(date: Date()),
        ], forDocument: hangoutRef(hangoutId))
        try await batch.commit()
    }

    func cancel(hangoutId: String) async throws {
        try await hangoutRef(hangoutId).updateData([
            "status": HangoutStatus.cancelled.rawValue,
            "statusMessage": "Cancelled",
            "updatedAt": Timestamp(date: Date()),
        ])
    }

    func reopen(hangoutId: String) async throws {
        let ref = hangoutRef(hangoutId)
        let members: QuerySnapshot = try await ref.collection("members").getDocuments()
        let slots: QuerySnapshot = try await ref.collection("slots").getDocuments()
        let timeVotes: QuerySnapshot = try await ref.collection("timeVotes").getDocuments()
        let surveys: QuerySnapshot = try await ref.collection("surveyAnswers").getDocuments()

        let batch: WriteBatch = db.batch()
        batch.updateData([
            "status": HangoutStatus.collectingAvailability.rawValue,
            "round": FieldValue.increment(Int64(1)),
            "winningSlot": FieldValue.delete(),
            "confirmed": FieldValue.delete(),
            "title": "",
            "statusMessage": "",
            "updatedAt": Timestamp(date: Date()),
        ], forDocument: ref)
        for doc in members.documents {
            batch.updateData([
                "availabilitySubmitted": false,
                "timesDone": false,
                "surveyDone": false,
                "notGoing": false,
            ], forDocument: doc.reference)
        }
        // Fresh planning: old candidate times, time votes and survey answers no longer apply.
        for doc in slots.documents { batch.deleteDocument(doc.reference) }
        for doc in timeVotes.documents { batch.deleteDocument(doc.reference) }
        for doc in surveys.documents { batch.deleteDocument(doc.reference) }
        try await batch.commit()
    }

    func handOff(hangoutId: String, toUid: String) async throws {
        let ref = hangoutRef(hangoutId)
        let snap: DocumentSnapshot = try await ref.getDocument()
        let oldOwner = (snap.data()?["ownerId"] as? String) ?? ""
        guard oldOwner != toUid else { return }
        let batch: WriteBatch = db.batch()
        batch.updateData(["ownerId": toUid, "updatedAt": Timestamp(date: Date())], forDocument: ref)
        if !oldOwner.isEmpty {
            batch.updateData(["role": MemberRole.member.rawValue], forDocument: memberRef(hangoutId, oldOwner))
        }
        batch.updateData(["role": MemberRole.owner.rawValue], forDocument: memberRef(hangoutId, toUid))
        try await batch.commit()
    }
}
