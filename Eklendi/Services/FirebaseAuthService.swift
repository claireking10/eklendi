import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// Readable messages for Firebase Auth errors (codes are FIRAuthErrorCode raw values,
/// compared as integers so this works across SDK versions).
enum AuthServiceError: LocalizedError {
    case invalidCode
    case codeExpired
    case invalidPhone
    case wrongPassword
    case noAccount
    case weakPassword
    case tooManyRequests
    case network
    case recentLoginRequired
    case alreadyRegistered
    case notSignedIn
    case other(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "That code isn't right. Check the text and try again."
        case .codeExpired: return "That code expired. Request a new one."
        case .invalidPhone: return "That phone number doesn't look right."
        case .wrongPassword: return "Wrong phone number or password."
        case .noAccount: return "No account for that number yet. Sign up first."
        case .weakPassword: return "Choose a stronger password (at least 6 characters)."
        case .tooManyRequests: return "Too many tries. Wait a bit and try again."
        case .network: return "No connection. Check your internet and try again."
        case .recentLoginRequired: return "For security, log out and log back in, then try again."
        case .alreadyRegistered: return "This number already has an account. Log in instead."
        case .notSignedIn: return "You're signed out. Please log in again."
        case .other(let message): return message
        }
    }

    static func from(_ error: Error) -> Error {
        if error is AuthServiceError { return error }
        let ns = error as NSError
        guard ns.domain == "FIRAuthErrorDomain" else { return error }
        switch ns.code {
        case 17044: return AuthServiceError.invalidCode                      // invalidVerificationCode
        case 17046, 17051: return AuthServiceError.codeExpired               // invalidVerificationID, sessionExpired
        case 17042, 17041, 17008: return AuthServiceError.invalidPhone       // invalidPhoneNumber, missingPhoneNumber, invalidEmail
        case 17009, 17004: return AuthServiceError.wrongPassword             // wrongPassword, invalidCredential
        case 17011: return AuthServiceError.noAccount                        // userNotFound
        case 17026: return AuthServiceError.weakPassword                     // weakPassword
        case 17010, 17052: return AuthServiceError.tooManyRequests           // tooManyRequests, quotaExceeded
        case 17020: return AuthServiceError.network                          // networkError
        case 17014: return AuthServiceError.recentLoginRequired              // requiresRecentLogin
        case 17007, 17025: return AuthServiceError.alreadyRegistered         // emailAlreadyInUse, credentialAlreadyInUse
        default: return AuthServiceError.other(ns.localizedDescription)
        }
    }
}

/// Phone sign-up (SMS) + phone/password login on Firebase Auth.
/// The password is attached as an email/password credential on a synthetic address
/// derived from the phone number ("<digits>@phone.eklendi.app"); users never see it.
@MainActor
@Observable
final class FirebaseAuthService: AuthServicing {
    private(set) var state: AuthState = .loading

    @ObservationIgnored private var listenerHandle: AuthStateDidChangeListenerHandle?

    init() {
        #if DEBUG
        // Lets Firebase test phone numbers work in the Simulator without APNs/reCAPTCHA.
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #endif
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let strongSelf = self else { return }
            let uid: String? = user?.uid
            Task { @MainActor in
                await strongSelf.evaluate(uid: uid)
            }
        }
    }

    static func syntheticEmail(for phoneE164: String) -> String {
        let digits = phoneE164.filter { $0.isNumber }
        return "\(digits)@phone.eklendi.app"
    }

    private var db: Firestore { Firestore.firestore() }

    /// signedOut / needsOnboarding / signedIn from the current user + users/{uid}.
    private func evaluate(uid: String?) async {
        guard let uid = uid else {
            state = .signedOut
            return
        }
        var complete = false
        do {
            let snap: DocumentSnapshot = try await db.collection("users").document(uid).getDocument()
            if let data = snap.data() {
                let connected = (data["calendarConnected"] as? Bool) ?? false
                let name = ((data["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                complete = connected && !name.isEmpty
            }
        } catch {
            print("[Auth] could not read profile: \(error)")
        }
        // Ignore stale results if the user changed while we were reading.
        guard Auth.auth().currentUser?.uid == uid else { return }
        state = complete ? .signedIn(uid: uid) : .needsOnboarding(uid: uid)
    }

    func refresh() async {
        await evaluate(uid: Auth.auth().currentUser?.uid)
    }

    func sendCode(to phoneE164: String) async throws -> String {
        do {
            let verificationId: String = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneE164, uiDelegate: nil)
            return verificationId
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    func verifyAndCreateAccount(verificationId: String, code: String, phoneE164: String, password: String) async throws {
        do {
            let phoneCredential: PhoneAuthCredential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationId, verificationCode: code)
            let result: AuthDataResult = try await Auth.auth().signIn(with: phoneCredential)
            let user: User = result.user

            // Attach the password (phone + password logins afterwards).
            let emailCredential: AuthCredential = EmailAuthProvider.credential(
                withEmail: Self.syntheticEmail(for: phoneE164), password: password)
            do {
                _ = try await user.link(with: emailCredential)
            } catch {
                let ns = error as NSError
                if ns.domain == "FIRAuthErrorDomain" && ns.code == 17015 {
                    // providerAlreadyLinked: re-verifying an existing account → just reset the password.
                    try await user.updatePassword(to: password)
                } else {
                    throw error
                }
            }

            let uid = user.uid
            try await db.collection("phoneIndex").document(phoneE164).setData(["uid": uid])
            let userRef = db.collection("users").document(uid)
            let existing: DocumentSnapshot = try await userRef.getDocument()
            if existing.exists {
                try await userRef.setData(["phone": phoneE164], merge: true)
            } else {
                let starter: [String: Any] = [
                    "phone": phoneE164,
                    "name": "",
                    "bufferMinutes": 15,
                    "interests": "",
                    "calendarConnected": false,
                    "friendIds": [String](),
                    "createdAt": Timestamp(date: Date()),
                ]
                try await userRef.setData(starter)
            }
            await evaluate(uid: uid)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    func signIn(phoneE164: String, password: String) async throws {
        do {
            let result: AuthDataResult = try await Auth.auth().signIn(
                withEmail: Self.syntheticEmail(for: phoneE164), password: password)
            await evaluate(uid: result.user.uid)
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            state = .signedOut
        } catch {
            throw AuthServiceError.from(error)
        }
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthServiceError.notSignedIn }
        let uid = user.uid
        do {
            var phone: String? = user.phoneNumber
            let userRef = db.collection("users").document(uid)
            if let snap = try? await userRef.getDocument(), let stored = snap.data()?["phone"] as? String, !stored.isEmpty {
                phone = stored
            }
            try await userRef.delete()
            if let phone = phone, !phone.isEmpty {
                try await db.collection("phoneIndex").document(phone).delete()
            }
            try await user.delete()
            state = .signedOut
        } catch {
            throw AuthServiceError.from(error)
        }
    }
}
