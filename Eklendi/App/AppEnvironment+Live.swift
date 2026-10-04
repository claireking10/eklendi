import Foundation
import FirebaseCore

extension AppEnvironment {
    /// Firebase-backed services. Falls back to the mock environment when
    /// GoogleService-Info.plist isn't bundled (e.g. a fresh clone), so the app still launches.
    static func live() -> AppEnvironment {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Eklendi] GoogleService-Info.plist missing: running with mock services.")
            return AppEnvironment.mock
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return AppEnvironment(
            auth: FirebaseAuthService(),
            users: FirebaseUserRepository(),
            hangouts: FirebaseHangoutRepository(),
            functions: FirebaseBackendFunctions(),
            calendar: CalendarService()
        )
    }
}
