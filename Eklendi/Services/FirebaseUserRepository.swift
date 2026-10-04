import Foundation
import FirebaseFirestore

/// users/{uid} and phoneIndex/{e164} (docs/ARCHITECTURE.md).
@MainActor
final class FirebaseUserRepository: UserRepository {
    private var db: Firestore { Firestore.firestore() }

    nonisolated static func decodeProfile(_ snap: DocumentSnapshot) -> UserProfile? {
        guard snap.exists else { return nil }
        guard var profile = FirestoreSupport.decode(UserProfile.self, data: snap.data(),
                                                    defaults: FirestoreSupport.profileDefaults) else { return nil }
        profile.id = snap.documentID
        return profile
    }

    func profile(uid: String) async throws -> UserProfile? {
        guard !uid.isEmpty else { return nil }
        let snap: DocumentSnapshot = try await db.collection("users").document(uid).getDocument()
        return FirebaseUserRepository.decodeProfile(snap)
    }

    func observeProfile(uid: String, onChange: @escaping (UserProfile?) -> Void) -> Cancellable {
        let registration: ListenerRegistration = db.collection("users").document(uid)
            .addSnapshotListener { snap, error in
                if let error = error { print("[Users] profile listener: \(error)") }
                let profile: UserProfile? = snap.flatMap { s in FirebaseUserRepository.decodeProfile(s) }
                FirestoreSupport.onMain { onChange(profile) }
            }
        return Cancellable { registration.remove() }
    }

    func saveProfile(_ profile: UserProfile) async throws {
        guard !profile.id.isEmpty else { throw EklendiServiceError.notSignedIn }
        var data: [String: Any] = try FirestoreSupport.encode(profile)
        // friendIds are only changed through addFriend (arrayUnion) so concurrent adds aren't lost.
        data.removeValue(forKey: "friendIds")
        // Merge keeps fields we don't manage; explicitly clear optionals that were removed.
        if profile.photoURL == nil { data["photoURL"] = FieldValue.delete() }
        if profile.homeLocation == nil { data["homeLocation"] = FieldValue.delete() }
        try await db.collection("users").document(profile.id).setData(data, merge: true)
    }

    func findUser(phoneE164: String) async throws -> UserProfile? {
        let phone = phoneE164.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !phone.contains("/") else { return nil }
        let indexSnap: DocumentSnapshot = try await db.collection("phoneIndex").document(phone).getDocument()
        guard let uid = indexSnap.data()?["uid"] as? String, !uid.isEmpty else { return nil }
        return try await profile(uid: uid)
    }

    func addFriend(myUid: String, friendUid: String) async throws {
        guard !myUid.isEmpty, !friendUid.isEmpty, myUid != friendUid else { return }
        let batch: WriteBatch = db.batch()
        batch.setData(["friendIds": FieldValue.arrayUnion([friendUid])],
                      forDocument: db.collection("users").document(myUid), merge: true)
        batch.setData(["friendIds": FieldValue.arrayUnion([myUid])],
                      forDocument: db.collection("users").document(friendUid), merge: true)
        try await batch.commit()
    }

    func friends(of uid: String) async throws -> [UserProfile] {
        guard let me = try await profile(uid: uid) else { return [] }
        var result: [UserProfile] = []
        for friendId in me.friendIds where !friendId.isEmpty {
            if let friend = try? await profile(uid: friendId) {
                result.append(friend)
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
