import Foundation
import Observation

/// Holds the service implementations. Inject with `.environment(env)` and read with
/// `@Environment(AppEnvironment.self) private var env`.
@MainActor
@Observable
final class AppEnvironment {
    let auth: AuthServicing
    let users: UserRepository
    let hangouts: HangoutRepository
    let functions: BackendFunctions
    let calendar: CalendarServicing

    init(auth: AuthServicing, users: UserRepository, hangouts: HangoutRepository,
         functions: BackendFunctions, calendar: CalendarServicing) {
        self.auth = auth
        self.users = users
        self.hangouts = hangouts
        self.functions = functions
        self.calendar = calendar
    }

    /// True when launched by UI tests (`-uiTesting` launch argument) or in previews.
    static var useMocks: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
            || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
