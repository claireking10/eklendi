import SwiftUI

/// Navigation value: open a hangout (pushed on the Home tab's NavigationStack).
/// `NavigationLink(value: HangoutRoute(hangoutId: h.id)) { ... }` or `router.openHangout(id)`.
struct HangoutRoute: Hashable {
    let hangoutId: String
}

/// Navigation value: start the "Plan a hangout" flow (pushed on the Home tab).
struct CreateHangoutRoute: Hashable {}

/// Auth gate (KAL-5): splash while loading, then Welcome / Onboarding / main tabs.
/// Views referenced here are defined by the feature agents (see docs/UI_COMPONENTS.md).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env: AppEnvironment

    var body: some View {
        ZStack {
            EKColor.background.ignoresSafeArea()
            switch env.auth.state {
            case .loading:
                SplashView()
            case .signedOut:
                WelcomeView()
            case .needsOnboarding(let uid):
                OnboardingFlowView(uid: uid)
                    .id("onboarding-\(uid)")
            case .signedIn(let uid):
                MainTabView(uid: uid)
                    .id("main-\(uid)")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: env.auth.state)
        .tint(EKColor.teal)
        // Inter for any text that doesn't set its own font.
        .font(EKFont.body)
    }
}

/// Launch splash: wordmark + spinner.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("eklendi")
                .font(EKFont.wordmark)
                .tracking(-1.2)
                .foregroundStyle(EKColor.textPrimary)
            ProgressView().tint(EKColor.teal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ekScreenBackground()
        .accessibilityIdentifier("splash")
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.mock)
        .preferredColorScheme(.dark)
}
