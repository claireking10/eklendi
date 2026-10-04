import SwiftUI
import Observation

enum AppTab: Hashable, CaseIterable {
    case home, friends, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .friends: return "Friends"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .friends: return "person.2"
        case .settings: return "gearshape"
        }
    }

    var accessibilityId: String {
        switch self {
        case .home: return "tabHome"
        case .friends: return "tabFriends"
        case .settings: return "tabSettings"
        }
    }
}

/// Tab selection + per-tab navigation paths. Injected by MainTabView:
///     @Environment(TabRouter.self) private var router
///     router.select(.friends)                 // e.g. Home header icon → Friends tab
///     router.openHangout(id)                  // Home tab, push HangoutFlowView
///     router.startCreateHangout()             // Home tab, push CreateHangoutFlowView
///     router.popToHome()                      // back to Home root (e.g. after declining)
/// The bottom tab bar hides automatically while the selected tab has pushed screens.
@Observable
final class TabRouter {
    var selected: AppTab = .home
    var homePath: NavigationPath = NavigationPath()
    var friendsPath: NavigationPath = NavigationPath()
    var settingsPath: NavigationPath = NavigationPath()

    func select(_ tab: AppTab) {
        selected = tab
    }

    func openHangout(_ hangoutId: String) {
        selected = .home
        var path = NavigationPath()
        path.append(HangoutRoute(hangoutId: hangoutId))
        homePath = path
    }

    func startCreateHangout() {
        selected = .home
        var path = NavigationPath()
        path.append(CreateHangoutRoute())
        homePath = path
    }

    func popToHome() {
        selected = .home
        homePath = NavigationPath()
    }

    var showsTabBar: Bool {
        switch selected {
        case .home: return homePath.isEmpty
        case .friends: return friendsPath.isEmpty
        case .settings: return settingsPath.isEmpty
        }
    }
}

/// Main shell (KAL-5): Home / Friends / Settings, each with its own NavigationStack,
/// and the icon-only bottom bar from docs/design/Home.dc.html.
struct MainTabView: View {
    let uid: String
    @State private var router: TabRouter = TabRouter()

    var body: some View {
        @Bindable var router = router
        // The tab bar sits below the tab content (not over it), so every screen's bottom
        // buttons stay visible above it.
        VStack(spacing: 0) {
            TabView(selection: $router.selected) {
                NavigationStack(path: $router.homePath) {
                    HomeView(uid: uid)
                        .navigationDestination(for: HangoutRoute.self) { route in
                            HangoutFlowView(hangoutId: route.hangoutId, uid: uid)
                        }
                        .navigationDestination(for: CreateHangoutRoute.self) { _ in
                            CreateHangoutFlowView(uid: uid)
                        }
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.home)

                NavigationStack(path: $router.friendsPath) {
                    FriendsView(uid: uid)
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.friends)

                NavigationStack(path: $router.settingsPath) {
                    SettingsView(uid: uid)
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.settings)
            }
            if router.showsTabBar {
                EKTabBar(selected: $router.selected)
            }
        }
        .background(EKColor.background.ignoresSafeArea())
        .environment(router)
    }
}

/// Icon-only bottom bar: white = selected, gray = others; thin top border.
struct EKTabBar: View {
    @Binding var selected: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(EKColor.card).frame(height: 1)
            HStack(spacing: 40) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selected = tab
                    } label: {
                        Image(systemName: selected == tab ? tab.systemImage + ".fill" : tab.systemImage)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(selected == tab ? EKColor.textPrimary : EKColor.placeholder)
                            .frame(width: 56, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityIdentifier(tab.accessibilityId)
                    .accessibilityAddTraits(selected == tab ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
        }
        .background(EKColor.background.ignoresSafeArea(edges: .bottom))
    }
}
