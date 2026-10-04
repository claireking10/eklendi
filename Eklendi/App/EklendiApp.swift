import SwiftUI

@main
struct EklendiApp: App {
    @State private var env: AppEnvironment

    init() {
        // Owned by the Integrations agent: AppEnvironment.live() configures Firebase
        // (FirebaseApp.configure()) and returns the Firebase-backed services.
        // Owned by the UI agent: AppEnvironment.mock (Services/Mock*.swift).
        _env = State(initialValue: AppEnvironment.useMocks ? AppEnvironment.mock : AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .preferredColorScheme(.dark)
        }
    }
}
