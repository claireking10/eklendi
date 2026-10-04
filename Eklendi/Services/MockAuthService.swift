import Foundation
import Observation

struct MockServiceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// In-memory auth. Launch args:
/// - `-uiTesting` → starts `.signedOut` (UI tests walk sign-up)
/// - `-uiTesting -uiTestingSignedIn` → starts `.signedIn(uid: "u_zach")`
/// - `-uiTesting -uiTestingOnboarding` → starts `.needsOnboarding` for a fresh user
/// - no args (previews / no GoogleService-Info.plist) → signed in as Zach
/// Any 6-digit SMS code verifies. Zach logs in with +15555550100 / password123.
@MainActor
@Observable
final class MockAuthService: AuthServicing {
    private(set) var state: AuthState = .loading

    private let store: MockStore
    @ObservationIgnored private var currentUid: String? = nil

    init(store: MockStore) {
        self.store = store
        let args: [String] = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestingSignedIn") {
            currentUid = MockStore.Ids.zach
            state = .signedIn(uid: MockStore.Ids.zach)
        } else if args.contains("-uiTestingOnboarding") {
            let uid = "u_new"
            let profile = UserProfile(id: uid, phone: "+15555550199", name: "")
            store.users[uid] = profile
            store.passwords["+15555550199"] = MockStore.zachPassword
            store.enrollNewUser(uid: uid)
            currentUid = uid
            state = .needsOnboarding(uid: uid)
        } else if args.contains("-uiTesting") {
            state = .signedOut
        } else {
            currentUid = MockStore.Ids.zach
            state = .signedIn(uid: MockStore.Ids.zach)
        }
    }

    func sendCode(to phoneE164: String) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        guard phoneE164.hasPrefix("+"), phoneE164.count >= 10 else {
            throw MockServiceError("That doesn't look like a valid phone number.")
        }
        return "mock-verification:\(phoneE164)"
    }

    func verifyAndCreateAccount(verificationId: String, code: String, phoneE164: String, password: String) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        let digitsOnly: String = code.filter { $0.isNumber }
        guard digitsOnly.count == 6, digitsOnly.count == code.count else {
            throw MockServiceError("That code didn't work. Enter the 6-digit code we texted you.")
        }
        guard password.count >= 6 else {
            throw MockServiceError("Use at least 6 characters for your password.")
        }
        if store.users.values.contains(where: { $0.phone == phoneE164 }) {
            throw MockServiceError("That number already has an account. Log in instead.")
        }
        let uid: String = "u_" + phoneE164.filter { $0.isNumber }
        store.users[uid] = UserProfile(id: uid, phone: phoneE164, name: "")
        store.passwords[phoneE164] = password
        store.enrollNewUser(uid: uid)
        store.notify()
        currentUid = uid
        state = .needsOnboarding(uid: uid)
    }

    func signIn(phoneE164: String, password: String) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let user = store.users.values.first(where: { $0.phone == phoneE164 }) else {
            throw MockServiceError("No account for that number. Sign up first.")
        }
        guard store.passwords[phoneE164] == password else {
            throw MockServiceError("Wrong password. Try again.")
        }
        currentUid = user.id
        state = MockAuthService.isOnboarded(user) ? .signedIn(uid: user.id) : .needsOnboarding(uid: user.id)
    }

    func signOut() throws {
        currentUid = nil
        state = .signedOut
    }

    func deleteAccount() async throws {
        guard let uid = currentUid else { return }
        if let phone = store.users[uid]?.phone { store.passwords[phone] = nil }
        store.users[uid] = nil
        for (otherUid, profile) in store.users where profile.friendIds.contains(uid) {
            store.users[otherUid]?.friendIds.removeAll { $0 == uid }
        }
        for hid in Array(store.hangouts.keys) {
            guard store.members[hid]?[uid] != nil else { continue }
            store.updateMember(hid, uid) { $0.state = .removed }
            store.updateHangout(hid) { h in
                h.memberIds.removeAll { $0 == uid }
                if h.ownerId == uid, let next = h.memberIds.randomElement() {
                    h.ownerId = next
                }
            }
            if let newOwner = store.hangouts[hid]?.ownerId {
                store.updateMember(hid, newOwner) { $0.role = .owner }
            }
        }
        store.notify()
        currentUid = nil
        state = .signedOut
    }

    func refresh() async {
        guard let uid = currentUid, let user = store.users[uid] else {
            state = .signedOut
            return
        }
        state = MockAuthService.isOnboarded(user) ? .signedIn(uid: uid) : .needsOnboarding(uid: uid)
    }

    static func isOnboarded(_ user: UserProfile) -> Bool {
        !user.name.trimmingCharacters(in: .whitespaces).isEmpty && user.calendarConnected
    }
}
