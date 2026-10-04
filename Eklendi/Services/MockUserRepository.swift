import Foundation

/// In-memory users/{uid} + phoneIndex.
@MainActor
final class MockUserRepository: UserRepository {
    private let store: MockStore

    init(store: MockStore) {
        self.store = store
    }

    func profile(uid: String) async throws -> UserProfile? {
        store.users[uid]
    }

    func observeProfile(uid: String, onChange: @escaping (UserProfile?) -> Void) -> Cancellable {
        store.observe { [weak store = self.store] in
            onChange(store?.users[uid])
        }
    }

    func saveProfile(_ profile: UserProfile) async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
        store.users[profile.id] = profile
        store.syncMemberNames(uid: profile.id)
        store.notify()
    }

    func findUser(phoneE164: String) async throws -> UserProfile? {
        store.users.values.first { $0.phone == phoneE164 }
    }

    func addFriend(myUid: String, friendUid: String) async throws {
        guard store.users[friendUid] != nil, myUid != friendUid else {
            throw MockServiceError("Couldn't add that friend.")
        }
        if store.users[myUid]?.friendIds.contains(friendUid) == false {
            store.users[myUid]?.friendIds.append(friendUid)
        }
        if store.users[friendUid]?.friendIds.contains(myUid) == false {
            store.users[friendUid]?.friendIds.append(myUid)
        }
        store.notify()
    }

    func friends(of uid: String) async throws -> [UserProfile] {
        let ids: [String] = store.users[uid]?.friendIds ?? []
        return ids.compactMap { store.users[$0] }.sorted { $0.name < $1.name }
    }
}
