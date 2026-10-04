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

    /// Demo mode (the default): in-memory mock services with preset friends
    /// (Services/MockStore.swift, `DemoPersona`), so the app runs without real phone numbers, SMS
    /// codes, passwords or Firebase. Launch with `-liveBackend` to use Firebase instead.
    static var demoMode: Bool {
        !ProcessInfo.processInfo.arguments.contains("-liveBackend")
    }

    /// True in Xcode previews.
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// True in demo mode, when launched by UI tests (`-uiTesting` launch argument) or in previews.
    static var useMocks: Bool {
        demoMode || ProcessInfo.processInfo.arguments.contains("-uiTesting") || isPreview
    }
}
