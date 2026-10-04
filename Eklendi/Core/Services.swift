import Foundation

// Service protocols. Views depend ONLY on these, injected through AppEnvironment.
// Real implementations: Eklendi/Services/Firebase*.swift, CalendarService.swift.
// Mock implementations: Eklendi/Services/Mock*.swift (previews + UI work + UI tests).

enum AuthState: Equatable, Sendable {
    case loading
    case signedOut
    /// Signed in but onboarding (name, calendar, home location) not finished.
    case needsOnboarding(uid: String)
    case signedIn(uid: String)
}

@MainActor
protocol AuthServicing: AnyObject {
    var state: AuthState { get }
    /// Sign-up step 1: send SMS code to an E.164 number. Returns a verification id.
    func sendCode(to phoneE164: String) async throws -> String
    /// Sign-up step 2: verify the code and create the account with a password.
    func verifyAndCreateAccount(verificationId: String, code: String, phoneE164: String, password: String) async throws
    /// Returning users: phone number + password.
    func signIn(phoneE164: String, password: String) async throws
    func signOut() throws
    func deleteAccount() async throws
}

@MainActor
protocol UserRepository: AnyObject {
    func profile(uid: String) async throws -> UserProfile?
    func observeProfile(uid: String, onChange: @escaping (UserProfile?) -> Void) -> Cancellable
    func saveProfile(_ profile: UserProfile) async throws
    /// Finds a registered user by phone (phoneIndex). nil if not on Eklendi.
    func findUser(phoneE164: String) async throws -> UserProfile?
    func addFriend(myUid: String, friendUid: String) async throws
    func friends(of uid: String) async throws -> [UserProfile]
}

@MainActor
protocol HangoutRepository: AnyObject {
    /// Hangouts where memberIds contains uid, newest first.
    func observeMyHangouts(uid: String, onChange: @escaping ([Hangout]) -> Void) -> Cancellable
    func observeHangout(id: String, onChange: @escaping (Hangout?) -> Void) -> Cancellable
    func observeMembers(hangoutId: String, onChange: @escaping ([HangoutMember]) -> Void) -> Cancellable
    func observeSlots(hangoutId: String, onChange: @escaping ([TimeSlot]) -> Void) -> Cancellable
    func observeCards(hangoutId: String, round: Int, onChange: @escaping ([HangoutCard]) -> Void) -> Cancellable

    /// Owner creates a hangout; returns its id. Owner is active, invitees are `invited`.
    func createHangout(owner: UserProfile, invitees: [UserProfile], mode: HangoutMode, planDescription: String,
                       durationsMinutes: [Int], durationAny: Bool) async throws -> String
    /// Invitee opens the hangout → state becomes active.
    func join(hangoutId: String, uid: String) async throws
    func setStartLocation(hangoutId: String, uid: String, location: Location) async throws
    /// Upload busy blocks (UTC, horizon window, no event details) and mark availabilitySubmitted.
    func submitAvailability(hangoutId: String, uid: String, busy: [BusyBlock], bufferMinutes: Int) async throws
    func submitTimeVotes(hangoutId: String, uid: String, votes: [String: Vote]) async throws
    func submitSurvey(hangoutId: String, uid: String, answers: [String: SurveyAnswer]) async throws
    func submitCardVotes(hangoutId: String, uid: String, round: Int, votes: [String: Vote]) async throws
    /// All members' time votes (for 11a-style tallies / day view).
    func cardVotes(hangoutId: String, round: Int) async throws -> [String: [String: Vote]]

    // Member / owner actions
    func decline(hangoutId: String, uid: String) async throws
    func setNotGoing(hangoutId: String, uid: String, notGoing: Bool) async throws
    func nudge(hangoutId: String, memberUid: String) async throws
    func remove(hangoutId: String, memberUid: String) async throws
    func cancel(hangoutId: String) async throws
    func reopen(hangoutId: String) async throws
    func handOff(hangoutId: String, toUid: String) async throws
}

@MainActor
protocol BackendFunctions: AnyObject {
    func suggestTime(hangoutId: String, start: Date, end: Date) async throws
    func startNewRound(hangoutId: String) async throws
    func geocode(_ text: String) async throws -> Location
}

@MainActor
protocol CalendarServicing: AnyObject {
    var isAuthorized: Bool { get }
    func requestAccess() async throws -> Bool
    /// Busy blocks between from and to (no titles/details).
    func busyBlocks(from: Date, to: Date) async throws -> [BusyBlock]
    /// Writes the confirmed hangout; returns the event identifier.
    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> String
    func removeEvent(identifier: String) async throws
}

/// Tiny cancellation handle for listeners (wraps ListenerRegistration).
final class Cancellable {
    private var onCancel: (() -> Void)?
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() { onCancel?(); onCancel = nil }
    deinit { onCancel?() }
}
