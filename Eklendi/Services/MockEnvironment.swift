import Foundation

extension AppEnvironment {
    @MainActor private static var mockInstance: AppEnvironment? = nil

    /// One shared in-memory environment (previews, UI tests with `-uiTesting`, and the
    /// fallback when GoogleService-Info.plist is missing). Seed ids: `MockStore.Ids`.
    @MainActor static var mock: AppEnvironment {
        if let existing = mockInstance { return existing }
        let store = MockStore()
        // Demo mode on a simulator/device: real venues + photos from Google Places.
        if !ProcessInfo.processInfo.arguments.contains("-uiTesting") && !AppEnvironment.isPreview {
            store.loadDemoVenues()
        }
        let env = AppEnvironment(
            auth: MockAuthService(store: store),
            users: MockUserRepository(store: store),
            hangouts: MockHangoutRepository(store: store),
            functions: MockBackendFunctions(store: store),
            calendar: MockCalendarService()
        )
        mockInstance = env
        return env
    }
}
