# UI components, app shell and mocks — API reference

For the iOS UI agents. Everything lives in `Eklendi/DesignSystem/`, `Eklendi/App/` and `Eklendi/Services/Mock*.swift`. The app is dark-only. Read the matching `docs/design/*.dc.html` for each screen's layout and copy; CLAUDE.md wins on conflicts.

## Views you MUST define (referenced by RootView / MainTabView)

| View | Owner | Notes |
|---|---|---|
| `WelcomeView()` | Account UI (B2) | sign up / log in entry |
| `OnboardingFlowView(uid: String)` | Account UI (B2) | after saving the profile (name + `calendarConnected = true`) call `await env.auth.refresh()` → state becomes `.signedIn` |
| `HomeView(uid: String)` | Account UI (B2) | root of the Home tab's NavigationStack |
| `FriendsView(uid: String)` | Account UI (B2) | root of the Friends tab |
| `SettingsView(uid: String)` | Account UI (B2) | root of the Settings tab |
| `HangoutFlowView(hangoutId: String, uid: String)` | Hangout UI (B3) | pushed for `HangoutRoute` |
| `CreateHangoutFlowView(uid: String)` | Hangout UI (B3) | pushed for `CreateHangoutRoute` |

Read services with `@Environment(AppEnvironment.self) private var env` (`env.auth`, `env.users`, `env.hangouts`, `env.functions`, `env.calendar`). Previews: `.environment(AppEnvironment.mock)`.

## App shell and navigation

- `RootView` switches on `env.auth.state`: `.loading` → `SplashView`, `.signedOut` → `WelcomeView()`, `.needsOnboarding(uid)` → `OnboardingFlowView(uid:)`, `.signedIn(uid)` → `MainTabView(uid:)`.
- Routes (in `RootView.swift`): `struct HangoutRoute: Hashable { let hangoutId: String }`, `struct CreateHangoutRoute: Hashable {}`. Both are handled by the **Home tab's** NavigationStack, so from Home use `NavigationLink(value: HangoutRoute(hangoutId: h.id)) { … }` / `NavigationLink(value: CreateHangoutRoute()) { … }`.
- `MainTabView(uid:)`: `TabView` with three NavigationStacks (Home, Friends, Settings) and a custom icon-only bottom bar (`EKTabBar`, ids `tabHome`, `tabFriends`, `tabSettings`). The bar **hides automatically while the selected tab has pushed screens**, so hangout/create flows are full screen.
- **Tab switching / programmatic navigation:** `TabRouter` (`@Observable`) is injected into the environment by MainTabView:
  ```swift
  @Environment(TabRouter.self) private var router
  router.select(.friends)            // AppTab: .home, .friends, .settings (e.g. Home header icons)
  router.openHangout(id)             // Home tab, replaces path with HangoutRoute (e.g. after creating)
  router.startCreateHangout()        // Home tab, push CreateHangoutFlowView
  router.popToHome()                 // clear Home path (after decline / cancel / done)
  router.homePath / friendsPath / settingsPath   // NavigationPath, bindable if you need it
  ```
  Inside a pushed screen, `@Environment(\.dismiss)` / `BackButton()` pops one level.
- Every screen hides the system nav bar (ScreenScaffold does `.toolbar(.hidden, for: .navigationBar)`) and uses the top-left `BackButton` arrow (CLAUDE.md rule).

## Tokens (`Theme.swift`)

- `Color(hex: "#00C3D0")` (RRGGBB or AARRGGBB).
- `EKColor`: `background` #000, `card` #162022, `cardBorder` #243133, `swipeCardBorder` #2A3739, `raised` #1E2B2D, `raisedBorder` #2C3A3C, `divider` #3A4A4C, `sheet` #0E1617, `teal` #00C3D0, `tealPressed`, `onTeal` #00282B (text on teal), `yellow` #FFCC00, `purple` #CB30E0, `blue` #6E8BFF, `textPrimary` #FFF, `textSecondary` #E8ECEC, `muted` #A3AFB1, `placeholder` #8A9799, `body` #C9D2D3, `danger` #E5484D, `dangerText` #FF8A8A, vote colors `yesGlow` (teal) / `maybeGlow` (white) / `noRing` #E8ECEC / `maybeRing` (yellow), pills `pillTealBg/Fg`, `pillYellowBg/Fg`, `pillGrayBg/Fg`, `avatarPalette`, `avatarText`.
- `EKFont`: `wordmark`, `largeTitle`, `title` (28 bold, screen titles), `title2`, `headline` (18 bold), `button`, `body`, `bodyBold`, `callout` (15), `calloutBold`, `caption` (13 semibold), `section` (13 bold, used uppercase), `display` (46 black, weekday on time cards).
- `EKSpacing`: `xxs 4, xs 8, sm 12, md 16, lg 24, xl 32, screen 24`. `EKRadius`: `small 12, field 18, button 16, card 22, swipeCard 28`.
- `.ekScreenBackground()` — black full-bleed background.

## Components

```swift
// Buttons (Buttons.swift)
PrimaryButton(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void)
SecondaryButton(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void)
Button("…") {}.buttonStyle(PrimaryButtonStyle())     // teal, 56pt, full width
Button("…") {}.buttonStyle(SecondaryButtonStyle())   // dark raised + border
Button("…") {}.buttonStyle(DestructiveButtonStyle()) // red (Decline, Delete account, Cancel hangout)
Button("…") {}.buttonStyle(LinkButtonStyle())        // inline teal text; LinkButtonStyle(color: EKColor.dangerText)

// Chips (Chips.swift)
Chip(_ title: String, isSelected: Bool = false, style: ChipStyle = .standard, systemImage: String? = nil, action: @escaping () -> Void)
enum ChipStyle { case standard, dontCare, suggestion }   // suggestion = small "+ Coffee shops"
ChipGroup(options: [String], selection: Binding<Set<String>>, style: ChipStyle = .standard)   // multi
ChipGroup(options: [String], selection: Binding<String?>, style: ChipStyle = .standard)       // single, tap again clears
ChipGroup(options: [T], title: (T) -> String, selection: Binding<Set<T>> | Binding<T?>, style:, spacing:) // generic T: Hashable
FlowLayout(spacing: CGFloat = 8, lineSpacing: CGFloat? = nil) { … }   // wrapping layout
Pill(_ text: String, background: Color = EKColor.pillTealBg, foreground: Color = EKColor.pillTealFg)

// Fields (Fields.swift)
EKTextField(_ placeholder: String, text: Binding<String>, kind: EKFieldKind = .text, label: String? = nil, systemImage: String? = nil, accessibilityId: String? = nil)
enum EKFieldKind { case text, phone, secure, code, multiline }   // secure has show/hide eye; code = one-time-code number pad
EKPhoneField(text: Binding<String>, placeholder: String = "(210) 555-0142", accessibilityId: String = "phoneField")  // fixed "+1" prefix
EKSecureField(_ placeholder: String, text: Binding<String>, accessibilityId: String? = nil)
PhoneFormat.e164(from: "(210) 555-0142") -> "+12105550142"?   // nil if invalid
PhoneFormat.display("+12105550142") -> "(210) 555-0142";  PhoneFormat.digits(_:)
// accessibilityIdentifier defaults to the placeholder if accessibilityId is nil.

// Layout & misc (Components.swift)
SectionHeader(_ title: String, color: Color = EKColor.teal)       // uppercase teal label
BackButton(action: (() -> Void)? = nil)                           // top-left chevron, default = dismiss(); id "backButton"
Card(padding: CGFloat = 18, cornerRadius: CGFloat = 22, borderColor: Color = EKColor.cardBorder) { content }
Avatar(name: String, photoURL: String? = nil, size: CGFloat = 40, ringColor: Color? = nil)   // initials or AsyncImage
Avatar.initials(for:) / Avatar.color(for:)                        // deterministic per name
AvatarStack(names: [String], size: CGFloat = 34, ringColor: Color = EKColor.card, maxVisible: Int = 5)
EKProgressBar(progress: Double /*0...1*/, label: String? = nil)   // "3 of 8"
LoadingView(_ message: String? = nil)                             // full-screen spinner; id "loadingView"
ErrorBanner(message: String, onDismiss: (() -> Void)? = nil)      // id "errorBanner"
someView.errorBanner($errorMessage)                               // String? binding; overlay at top, auto dismiss button
ScreenScaffold(title: String, subtitle: String? = nil, eyebrow: String? = nil, showsBack: Bool = false,
               onBack: (() -> Void)? = nil, scrolls: Bool = true,
               content: { … }, footer: { … }, trailing: { … })   // footer and trailing optional
//   eyebrow = teal section label above the title (e.g. "Thursday crew · Step 1 of 3")
//   footer is pinned to the bottom (usually PrimaryButton); trailing sits top-right (e.g. "Decline hangout")
//   title "" hides the title. Hides the system nav bar.
```

## SwipeCardStack (KAL-12)

```swift
SwipeCardStack(items: [Item],                 // Item: Identifiable
               showsButtons: Bool = true,
               onVote: @escaping (Item, Vote) -> Void,
               onFinished: @escaping () -> Void = {},
               skipTitle: String? = nil,           // e.g. "I don't care" (survey)
               onSkip: ((Item) -> Void)? = nil,
               content: @escaping (Item) -> Content)   // @ViewBuilder
```
- Right = `.yes`, left = `.no`, down = `.maybe` (90pt threshold, flicks count). Up is ignored.
- The stack draws the card chrome (card fill, 28pt corners, border, clipping, glow). `content` fills the card — add your own padding (design uses 22) and draw a photo background inside it if you want one (e.g. `AsyncImage` + dark gradient for hangout cards).
- Give the stack a height (`.frame(height: 420)`) or let it take the remaining space; it reserves 28pt at the bottom for the peeking cards and draws the No / Maybe / Yes buttons below (ids `swipeNo`, `swipeMaybe`, `swipeYes`; top card id `swipeCard`).
- Glow: yes = teal border glow, maybe = white border glow, no = shadow sweeping in from the top-left corner (full at 220pt). No text stamps. Next card is already underneath (no drop-in).
- `onVote` fires once per card after its exit animation; `onFinished` fires after the vote that leaves no unvoted items. Progress is tracked by item id: appending items (a suggested time) adds cards at the end. Restart ("Redo my swipes") by changing `.id(...)` on the stack.
- `VoteCircleButton(vote: Vote, action:)` is public if you need the round buttons elsewhere. `NoShadowOverlay(progress:)` too.
- Typical submit: collect votes in a `[String: Vote]` in `onVote`, call `env.hangouts.submitTimeVotes / submitCardVotes` in `onFinished`.
- **Survey "I don't care"**: pass `skipTitle: "I don't care", onSkip: { q in answers[q.id] = .dontCare }` (after `onFinished`, before the content closure). A `.dontCare` chip appears under the buttons (id `swipeSkip`); the card fades out and counts as done, so `onFinished` still fires after the last card.

## Mock services (`Services/Mock*.swift`)

- `AppEnvironment.mock` — one cached in-memory environment (`MockStore` + `MockAuthService`, `MockUserRepository`, `MockHangoutRepository`, `MockBackendFunctions`, `MockCalendarService`).
- Launch args: `-uiTesting` → mocks, starts **signed out**; add `-uiTestingSignedIn` → signed in as Zach; add `-uiTestingOnboarding` → `.needsOnboarding(uid: "u_new")`. (`AppEnvironment.useMocks` checks only `-uiTesting`, so always pass it.) Without args (previews / no plist) → signed in as Zach.
- Auth: any 6-digit code verifies; password ≥ 6 chars; new accounts get uid `u_<digits>`, friends Seth/Matt/Claire/Ava, a seat in `h_voting_times` and an invite to `h_collecting`. Zach logs in with `+15555550100` / `password123` (all seeded users use `password123`).
- Listeners fire immediately and after every change. Simulated backend delay 1 s (0.3 s with `-uiTesting`).
- **Progression:** submitAvailability → (others simulated) `votingTimes` with 8 slots → submitTimeVotes → `survey` (or `confirmed` in timeOnly mode, or `noMutualTime` + fallback slots if you said no to everything) → submitSurvey → `generating` → `votingCards` (3 × members cards) → submitCardVotes → `confirmed` (or `noAgreement` if all no) → `startNewRound` → next round. Other members mirror your yes/maybe votes. createHangout → invitees "join and submit" after ~2 s.
- `geocode(text)` rejects zip-only / <3 chars; `suggestTime` appends a `suggested` slot (and reopens voting from `noMutualTime`).

### Seed ids (`MockStore.Ids`)

| id | what |
|---|---|
| `u_zach` | Zach Weiss, +15555550100 (current user) |
| `u_seth`, `u_matt`, `u_claire`, `u_ava` | Seth Fox +15555550101, Matt Hill …102, Claire Kim …103, Ava Lopez …104 (Zach's friends) |
| `u_noah` | Noah Park +15555550106 — on Eklendi, not a friend (contacts "Add") |
| `h_voting_times` | owner Seth; Zach + Matt + Claire; `votingTimes`, 8 slots, Zach hasn't swiped |
| `h_survey` | owner Zach; Ava + Matt; `survey`, winningSlot set, Zach's survey pending |
| `h_voting_cards` | owner Claire; Zach + Seth; `votingCards` round 1, 9 cards (3 with photos) |
| `h_confirmed` | owner Zach; Seth, Matt, Claire; `confirmed` "Coffee at Juniper Café" in 4 days 3–4 PM |
| `h_no_agreement` | owner Matt; Zach + Ava; `noAgreement` round 1, everyone's votes in `cardVotes(round: 1)` |
| `h_no_mutual_time` | owner Ava; Zach + Matt; `noMutualTime`, 3 fallback slots missing Matt |
| `h_collecting` | owner Matt; Zach is `invited` (call `join`), `collectingAvailability` |

Hangouts have no name field: `title` is `""` until confirmed. Show e.g. "\(ownerFirstName)'s hangout" or member first names until then.
