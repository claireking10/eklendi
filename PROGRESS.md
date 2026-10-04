# PROGRESS.md — Eklendi

Running log for agents and teammates. **Read this and `CLAUDE.md` before starting work.** Update it whenever you finish a ticket, start or merge a milestone branch, make a decision, or hit a blocker (newest entries at the top of the log).

## Current status

- **Phase:** Planning complete. **No app code written yet.**
- **Requirements:** `CLAUDE.md` (source of truth for product rules and engineering decisions).
- **Design:** clickable prototype canvas, 19 screens — https://claude.ai/artifact/SciRf8AwsmeDvkPSGDRtHv (shared "anyone with the link"). Screen numbers (01–12, with letter suffixes) are referenced in tickets.
- **Tickets:** Linear workspace `kalpeklendi`, team **Kalpeklendi**, project **Eklendi App**: KAL-5 to KAL-47, grouped into 6 milestones. KAL-1 to KAL-4 are Linear's default onboarding issues, not project work.
- **GitHub:** https://github.com/claireking10/eklendi. Planning docs are committed on branch `docs/planning` (not merged to `main`, not pushed).
- **Repo:** only `CLAUDE.md`, `PROGRESS.md`, `README.md`, `LICENSE`, `.gitignore`. 

## >>> HANDOFF — START HERE (written 2026-10-04 ~02:50 CDT by the director session) <<<

**Deadline: noon CDT Sun Oct 4, 2026.** Branch `hackathon/build`. Ignore branch `claude/eklendi-core-flow-review-wvmd9r` completely (Zach's instruction). Build from CLAUDE.md + Linear (KAL-5..KAL-47, project "Eklendi App", team Kalpeklendi).

### Where things stand
- **All code is written** (commit `2b69277` and earlier): functions logic + state machine + triggers/callables (Dev A), Firebase iOS services + EventKit + Gemini + Places + preferences/geo (Dev C), design system + SwipeCardStack + mocks + RootView/MainTabView (Dev B), account UI (Dev B2), hangout UI (Dev B3). Each agent's summary, files and known gaps are in the "### 2026-10-04 — <role>" sections at the end of this file — read them.
- **Functions are DEPLOYED** to Firebase `eklendi-633e3` (built on Zach's machine, so the TS compiles). Secrets set. Logic tests: `cd functions && npm test` (pass).
- **NOT done: QA.** The QA/fix agent was stopped before it made any changes. **No Swift has ever been compiled.** Expect compile errors from 5 agents writing Swift blind.
- **GitHub:** Zach has pushed through `2576842`. Commits after that (account UI, hangout UI, PROGRESS) are only in the cloud clone and/or need moving to Zach's machine (see below).
- **Linear:** KAL-5 and KAL-6 marked In Progress; all others still Backlog. Statuses not yet updated for finished work.

### Next steps (in order)
1. **Get the latest commits to Zach** (see "How commits reach GitHub") and have him push.
2. **Compile on the Mac / CI.** Teammate: `brew install xcodegen`, put `GoogleService-Info.plist` in repo root (already sent privately), `./scripts/make-secrets.sh && xcodegen generate`, open `Eklendi.xcodeproj`, ⌘B. Paste errors back to Claude. CI (`.github/workflows/ci.yml`, macos-15) also builds on push to `hackathon/**` — check the Actions tab for the `xcodebuild` log artifact. This compile-fix loop is the critical path.
3. **QA pass** (if a new session has budget): static audit of all Swift — duplicate/undefined symbols across agents' files, protocol conformance (Mock* and Firebase* vs Core/Services.swift incl. `refresh()` and `TimeSlot.offerOnly`), main-actor hops in Firestore/EventKit callbacks, missing imports, project.yml products (FirebaseCore/Auth/Firestore/Functions). The full QA prompt is in the workflow script `eklendi-hackathon-build` (QA section) — can be re-dispatched as a single agent.
4. **Demo test on device/simulator:** Firebase Console → Authentication → Sign-in method: Phone enabled, add test numbers (e.g. +1 555-555-0101 / code 123456) for the Simulator. Walk: sign up → onboarding (Apple Calendar) → add friend → create hangout → swipe times → survey → cards (Gemini+Places) → confirmed → add to calendar. Use 2 accounts (Simulator + another sim/device).
5. Update Linear statuses (Done/In Progress) from the agent sections; Google Calendar (KAL-23) and push (KAL-11) are deferred.

### How commits reach GitHub (agents cannot push)
- Cloud clone `/home/claude/eklendi` (if the new session has it). Otherwise work directly in Zach's local repo `C:\Users\m86an\PersonalRepos\eklendi` via the device bridge, or in a fresh clone of GitHub.
- Transfer: `git bundle create out.bundle <last-pushed>..hackathon/build` → SendUserFile → device_commit_files into the repo folder → on device `git fetch ./out.bundle hackathon/build:hackathon/build` (if hackathon/build is checked out there, fetch into a temp ref and `git merge --ff-only`) → delete bundle + `.git/*.lock` + `tmp_obj_*`. Then Zach runs `git push origin hackathon/build`.
- Never commit `GoogleService-Info.plist`, `.env`, `Config/Secrets.xcconfig` (repo is PUBLIC). Never print keys.

### Deploy notes (Windows)
- `$env:FUNCTIONS_DISCOVERY_TIMEOUT=60` then `firebase deploy --only functions --project eklendi-633e3 --force`. Firestore rules/indexes: `--only firestore`.

## BUILD STATUS — hackathon, deadline noon CDT Sun Oct 4

- **Branch:** `hackathon/build` (all hackathon work; branched from `docs/planning`). Push with `git push -u origin hackathon/build` (Zach runs it).
- **Scope:** everything in CLAUDE.md + Linear, built in priority order: demo path first (sign up → create hangout → swipe times → survey → Gemini/Places cards → confirmed in Apple Calendar), then remaining tickets. Deferred: push notifications (needs paid Apple account), Google Calendar (OAuth).
- **Contract:** `docs/ARCHITECTURE.md` — Firestore model, state machine, functions, iOS structure. iOS contracts in `Eklendi/Core/` (Models.swift, Services.swift); logic types in `functions/src/logic/types.ts`.
- **Team (multi-agent workflow, directed by the main Claude session):**
  - Dev A — backend logic: `functions/src/` (scheduling, winner, state machine, triggers, callables) + `node:test` tests.
  - Dev B — iOS UI: `Eklendi/DesignSystem/`, `Eklendi/Features/`, `Eklendi/App/RootView.swift`, `Eklendi/Services/Mock*.swift`, UI tests.
  - Dev C — integrations: `Eklendi/Services/Firebase*.swift`, `CalendarService.swift`, `AppEnvironment+Live.swift`; `functions/src/{gemini,places,preferences,geo}` pieces.
  - QA — reviews each area against CLAUDE.md/tickets, runs logic tests, hunts Swift compile errors.
- **Tooling limits:** agents have no Swift/Xcode/npm. Logic tests run here (`cd functions && npm test`). iOS build + UI tests run in GitHub Actions (`.github/workflows/ci.yml`) and on the teammate's Mac (see README).
- **Status:** all code written; functions deployed; Swift never compiled; QA not run. See HANDOFF above.

## Hackathon setup (2026-10-04)

- **Deadline: noon CDT, Sunday Oct 4.** Scope is being cut to the demo path (sign up → hangout → swipe times → survey → Gemini/Places cards → confirmed into Apple Calendar); everything else is stretch. Not started yet; waiting for Zach's go-ahead.
- **Firebase:** project `eklendi-633e3`, iOS bundle ID `devplaceholder.B1Q5FZOR.MyApp`. Phone sign-in with fictional test numbers; Firestore in test mode. Hackathon simplifications under discussion: no Cloud Functions (app calls Gemini/Places directly), no push.
- **Secrets:** `GoogleService-Info.plist` and `.env` (GEMINI_API_KEY, GOOGLE_PLACES_API_KEY) are in Zach's repo folder, gitignored. The repo is **public**, so they must never be committed. Teammate with the Mac needs both files sent privately.
- Keys couldn't be tested from the agent environment (no network to Google); first real test is on the Mac.

## Next steps

1. Create branch `milestone-1-foundations` and start **Milestone 1 · Foundations** (KAL-5 to KAL-12), in roughly this order:
   - KAL-5 iOS project (SwiftUI, iOS 17+), app shell, design tokens
   - KAL-6 Firebase project: Auth (phone), Firestore schema + security rules, Cloud Functions skeleton, FCM
   - KAL-7 phone sign-up (SMS verify) + password login, persistent session
   - KAL-12 reusable three-way swipe card stack (Urgent; most later screens depend on it)
   - KAL-8 onboarding: calendars (at least one required), buffer, approximate home location
   - KAL-9 optional interests, KAL-10 Home, KAL-11 push notifications
2. In KAL-5, also set up XCTest + XCUITest targets, a separate Foundation-only Swift package for core logic (testable on Linux), and the **GitHub Actions macOS CI workflow** (build + unit + UI tests on milestone pushes and PRs).
3. Move tickets to In Progress / Done in Linear as they're picked up and finished; assign to Zach.
4. Open one PR per milestone branch.

## Things to know

- **Stack decisions:** Firebase replaces CloudKit. All third-party API keys (Gemini, Google Places, Google OAuth secrets) live only in Cloud Functions. Store times in UTC.
- **Order of decisions in a hangout:** time first (everyone swipes, winner picked), then activity survey, then hangout cards at the winning time.
- **Pushing:** agents can't reach GitHub. Commit locally, then give Zach the exact push command to run in his terminal.
- **Build/test setup:** agents can't run Xcode (Linux). CI on GitHub Actions macOS runners builds and runs tests; a teammate with a Mac does manual testing (Simulator or iPhone via cable). No paid Apple Developer account yet → no TestFlight or device push.
- **The prototype is a design reference, not code to port.** It's HTML on a design canvas; build native SwiftUI.
- **Known prototype mismatches** (CLAUDE.md wins):
  - Screen 03 lets you continue without connecting a calendar; the app must require at least one.
  - Screen 08 shows one Friday slot as a range ("7:00 – 10:00 PM"); real slots are specific start/end times.
  - Screen 08a always shows Thursday (prototype limitation); the real day view shows the tapped card's day.
- **Open questions:** none (see CLAUDE.md "Open questions").

## Log

### 2026-10-04 — Layout fixes + real demo venues/photos (Claude, for Claire)
- **Bottom buttons cut off:** ScreenScaffold footers now float over the scrolling content (`FloatingFooter` via `.safeAreaInset`); Home's "Plan a hangout" and the day view's "Send to the group" float the same way. The custom tab bar now sits below the tab content instead of over it (`MainTabView`). Swipe cards (times, survey, hangout cards) shrink to fit short screens (`ShrinkToFit` in `SwipeCardStack`), so Yes/Maybe/No stay visible. Decline and hand-off sheets scroll instead of a fixed 300 pt height. Files: `DesignSystem/Components.swift`, `DesignSystem/SwipeCardStack.swift`, `App/MainTabView.swift`, `Features/Home/HomeView.swift`, `Features/Hangout/{HangoutComponents,HangoutTimesViews}.swift`.
- **Demo photos:** the made-up demo venues and Unsplash stock photos are gone. `MockStore.cardPool` now lists real San Antonio places; new callable `demoVenues` (`functions/src/demo.ts`, allowlist only, no sign-in) returns their Places name, address, location and photo, and `MockStore.loadDemoVenues()` swaps them into the cards at launch. Offline / UI tests / before deploy: fallback names + category colors.
- **Needs a deploy (Zach):** `firebase deploy --only functions:demoVenues --project eklendi-633e3 --force` (Windows: set `$env:FUNCTIONS_DISCOVERY_TIMEOUT=60` first).
- Swift unverified until CI/Mac. Logic tests 41/41; `demo.ts` type-checked against stubs.

### 2026-10-04 — Demo mode + relaxed login (Claude, for Claire)
- **Demo mode is now the default launch** (`AppEnvironment.demoMode`): mock services, starts on the login screen. `-liveBackend` launch arg switches back to Firebase. UI-test args unchanged.
- **Login:** the only requirement is a 10-digit username; the password can be anything (including empty). Button enables at exactly 10 digits. In demo, a number belonging to an account logs into it, any other number logs in as the demo user (Zach). Files: `Features/Auth/WelcomeView.swift`, `Features/Auth/AccountLogic.swift` (`isValidUsername`, `demoUsernameDigits`), `Services/MockAuthService.swift`.
- **Preset friends:** new `Services/MockStore.swift, `DemoPersona`` gives Seth/Matt/Claire/Ava/Noah fixed time votes (by slot rank), card votes (by category, with a price ceiling) and survey answers. Replaces "others mirror your votes" in `MockHangoutRepository`/`MockStore`; card order follows the group's survey answers. Every friend combination keeps ≥2 times and ≥3 cards nobody vetoes, so voting yes still always finds a winner (existing UI tests rely on this).
- Tests: `EklendiTests/DemoModeTests.swift`. Docs: README, `docs/UI_COMPONENTS.md`. Swift unverified until CI/Mac.
- Fix: `DemoPersona` moved into `Services/MockStore.swift` ("cannot find DemoPersona in scope" on a project generated before the new file existed). New files need `xcodegen generate`; `EklendiTests/DemoModeTests.swift` only runs after regenerating.

### 2026-10-04 — Push workflow
- Agents commit; Zach pushes. Asked Zach to run `git push -u origin docs/planning`.

### 2026-10-04 — Build and test setup decided
- Teammate with a Mac will test; agents push milestone branches to GitHub.
- Added free GitHub Actions macOS CI to KAL-5 and CLAUDE.md; core logic goes in a Linux-testable Swift package.
- Committed CLAUDE.md + PROGRESS.md on branch `docs/planning` (40442a0).

### 2026-10-04 — Planning wrap-up (Claude, with Zach)
- Confirmed the six prototype-only details (interest chips, text invites, 1–12 hr custom duration, 14-question survey and price cut-offs, top 3 on "Not everyone agrees", "I can make it" undo); recorded in CLAUDE.md and tickets.
- Decided: reopening a confirmed hangout makes everyone retake the survey; automatic ownership hand-off picks a random remaining member (KAL-46, KAL-47).
- Created this file and added a "Progress log" section to CLAUDE.md.

### 2026-10-03/04 — Clarifying questions answered
- Firebase only; SwiftUI iOS 17+; password login with SMS verification at sign-up and persistent session; events written directly into each member's calendar; time decided before activities; ties = most Yes → fewest Maybes → earliest; at least one calendar required; max 8 time slots, specific times; suggested times add one card for everyone; owner can cancel, reopen and hand off (KAL-45–47 created); groups of 2–8; UTC storage; branch per milestone; unit + UI tests; build all tickets in milestone order.

### 2026-10-03 — Tickets created
- 40 tickets (KAL-5 to KAL-44) plus milestones and area labels (iOS, Backend, Calendars, AI & Places, Notifications) in the Eklendi App project; key blocking relations added.

### 2026-10-03 — Design and requirements
- Built and iterated the prototype canvas from the original Figma (https://www.figma.com/design/uM2EZfZGQwyxU82xmmbAOu/Eklendi) and CLAUDE.md.
- CLAUDE.md updated throughout with every product decision made during design review.

### 2026-10-04 — Director: build workflow launched (how to continue if this session dies)
- Workflow "eklendi-hackathon-build" runs Dev A (functions logic/state machine), Dev C (Firebase iOS services, EventKit, Gemini, Places, preferences, geo), Dev B foundations (DesignSystem, SwipeCardStack, mocks, RootView/MainTabView) → then Dev B2 (Auth/Onboarding/Home/Friends/Settings) and Dev B3 (Hangout flow) in parallel → QA audit + fixes.
- Ownership by path is listed in each agent's section below. Claire's branch (claude/eklendi-core-flow-review-wvmd9r) is NOT used — build from scratch per CLAUDE.md + Linear.
- To continue in a new session: read CLAUDE.md, docs/ARCHITECTURE.md, docs/UI_COMPONENTS.md, and the agent sections at the end of this file; check `git log --oneline hackathon/build`; dispatch agents for whatever is listed as gaps; run `cd functions && npm test`.
- Hand-off of commits to GitHub: agents can't push. The cloud clone's commits are moved to Zach's local repo via `git bundle`, then Zach runs `git push -u origin hackathon/build`.

### 2026-10-04 — Dev C (integrations)
- **Built:** Firebase iOS services, EventKit calendar, live environment; Cloud Functions preference model, geo helpers, Gemini idea generation, Places venues/photos/geocode.
- **iOS files:** `Eklendi/App/AppEnvironment+Live.swift` (FirebaseApp.configure; falls back to `AppEnvironment.mock` if GoogleService-Info.plist is missing), `Eklendi/Services/FirebaseAuthService.swift` (phone SMS sign-up → links email/password credential on `<digits>@phone.eklendi.app`; login = phone + password; writes `phoneIndex/{e164}` + starter `users/{uid}`; DEBUG disables app verification so Firebase test numbers work in the Simulator; readable `AuthServiceError`), `FirebaseUserRepository.swift`, `FirebaseHangoutRepository.swift`, `FirebaseBackendFunctions.swift` (suggestTime sends epoch **ms**), `FirebaseSupport.swift` (Codable decode with defaults for missing fields, `EklendiServiceError`), `CalendarService.swift` (iOS 17 full access; busy blocks skip all-day/free/cancelled, merged; writes to default calendar).
- **Contract change (additive):** `AuthServicing.refresh() async` + default no-op extension in `Core/Services.swift`. **Onboarding must call `env.auth.refresh()` after saving the profile with a non-empty name and `calendarConnected = true`** — that is what moves `state` from `.needsOnboarding` to `.signedIn`.
- **project.yml:** added `FirebaseCore` product to the Eklendi target.
- **Functions files:** `functions/src/logic/preferences.ts` (yes +2 / maybe +1 / no −2 / dontCare 0; majority-dontCare dimension → default: types food/games/arts, setting either, price mid, vibe either; price ceiling = highest tier nobody said no to; interests soft only), `functions/src/logic/geo.ts` (centroid, haversineMiles), `functions/src/gemini.ts` (Gemini REST, JSON schema, 20 s timeout, never throws; built-in preference-filtered fallback list; filters walk/stay-in ideas and repeats), `functions/src/places.ts` (searchText + photo `skipHttpRedirect` → key-free `photoUri`; geocode returns the user's text with coordinates rounded to ~100 m). Tests: `functions/test/preferences.test.mjs`, `functions/test/geo.test.mjs` (all pass; 41/41 total).
- **Behaviour notes:** `reopen` resets members' availabilitySubmitted/timesDone/surveyDone/notGoing, increments round, clears winningSlot/confirmed, and deletes old slots/timeVotes/surveyAnswers. `decline` by the owner passes ownership to a random remaining member. `createHangout` pre-fills each member's `startLocation` with their home location. Time votes are merged (suggested-slot re-swipe only sends one vote).
- **Tickets:** KAL-6, KAL-7, KAL-8 (backend), KAL-13/14 (data), KAL-16, KAL-22, KAL-31, KAL-32, KAL-33, KAL-34, KAL-35, KAL-36, KAL-42 (calendar write).
- **Gaps/TODO:** Swift unverified until CI/Mac. In DEBUG builds real SMS numbers won't work (app verification disabled for test numbers). deleteAccount doesn't yet hand off hangouts the user owns. Gemini/Places untested against live APIs (no network here); fallback ideas keep cards flowing if Gemini fails, but cards still need Places to return venues. Firestore security rules not touched (test mode).

### 2026-10-04 — Dev A (backend group logic + state machine)
- **Built:** pure scheduling + winner logic with `node:test` tests, the idempotent hangout state machine, Firestore triggers and callables.
- **Files:** `functions/src/logic/scheduling.ts` (free windows, per-member buffers, 9:00–23:00 sensible hours in owner tz via Intl, :00/:30 starts, ≥1h lead, ≤8 specific slots spread across days with weekend/weeknight/duration mix, label + reason, 14→30 day horizon, "all but one" fallback, 08b offers), `functions/src/logic/winner.ts` (allYes → yesOrMaybe → none; most yes, fewest maybe, earliest; `topOptions` for 11a), `functions/src/advance.ts` (state machine), `functions/src/callables.ts` (suggestTime, startNewRound, geocodeLocation), `functions/src/index.ts` (v2 triggers + callables, secrets bound), `functions/test/scheduling.test.mjs`, `functions/test/winner.test.mjs`. `npm test`: 41/41 pass.
- **Tickets:** KAL-24, KAL-25, KAL-29, KAL-40; backend parts of KAL-6, KAL-21, KAL-26–28, KAL-37–47.
- **State machine notes:** every transition is a guarded transaction keyed on `status`; generation is claimed by flipping to `generating` with `generationRound` (stale after 4 min → retried); 0 venues or a generation error → `noAgreement` with a statusMessage so `startNewRound` can retry. Invited members count as pending in every gate. <2 people left → statusMessage, no advance. Owner declined/removed → random active member becomes owner (client decline already does this; server is the backstop). Reopen: client batch resets; server only resets if the round wasn't bumped.
- **Contract (additive, documented in ARCHITECTURE.md):** slots get `durationMinutes` and `offerOnly` (08b alternatives, not swiped; pick → `suggestTime`); hangout gets `topCardIds`, `generationRound`, `generationStartedAt`, `reopenResetRound`.
- **Verified:** glue type-checked against hand-written Firebase stubs and run end to end against an in-memory fake Firestore (create → join → availability → slots → time vote → survey → 9 cards → no agreement → new round → confirmed → owner decline hand-off → reopen → no winner → 08b offers → suggestTime → <2 people → cancel). Real deploy untested (no network).
- **Gaps/TODO for others:** iOS should upload **30 days** of busy blocks; swipe screens should skip `offerOnly` slots; 11a can use `topCardIds`. Push/nudge notifications not implemented (deferred). Random owner pick uses Web Crypto (`globalThis.crypto`), not `crypto.randomInt`, to avoid a Node-types dependency.

### 2026-10-04 — Dev B part 1 (design system, mocks, app shell)
- **Built:** design tokens + components, the reusable three-way `SwipeCardStack`, full in-memory mock services with a simulated state machine, the auth-gated app shell with tabs. API reference for the other UI agents: `docs/UI_COMPONENTS.md`.
- **Files:** `Eklendi/DesignSystem/Theme.swift` (EKColor/EKFont/EKSpacing/EKRadius, `Color(hex:)`), `Buttons.swift` (Primary/Secondary/Destructive/Link styles, PrimaryButton/SecondaryButton), `Chips.swift` (Chip, ChipGroup single/multi, FlowLayout, Pill), `Fields.swift` (EKTextField text/phone/secure/code/multiline, EKPhoneField, EKSecureField, PhoneFormat), `Components.swift` (SectionHeader, BackButton, Card, Avatar, AvatarStack, EKProgressBar, LoadingView, ErrorBanner + `.errorBanner($msg)`, ScreenScaffold), `SwipeCardStack.swift` (right yes / left no / down maybe; teal / white border glow, top-left shadow for no; no drop-in; No/Maybe/Yes buttons `swipeNo/swipeMaybe/swipeYes`; optional "I don't care" skip `swipeSkip`); `Eklendi/Services/MockStore.swift`, `MockAuthService.swift`, `MockUserRepository.swift`, `MockHangoutRepository.swift`, `MockBackendFunctions.swift`, `MockCalendarService.swift`, `MockEnvironment.swift` (`AppEnvironment.mock`); `Eklendi/App/RootView.swift` (auth gate, `HangoutRoute`, `CreateHangoutRoute`, SplashView), `Eklendi/App/MainTabView.swift` (`TabRouter` in environment, icon tab bar that hides on pushed screens).
- **Mock launch args:** `-uiTesting` (signed out), `-uiTesting -uiTestingSignedIn` (Zach), `-uiTesting -uiTestingOnboarding` (fresh user needing onboarding). Any 6-digit code; Zach = +15555550100 / password123. Seed ids in docs/UI_COMPONENTS.md.
- **Tickets:** KAL-5 (app shell, tokens), KAL-12 (swipe stack).
- **Gaps/TODO:** Swift unverified until CI/Mac. RootView/MainTabView reference WelcomeView, OnboardingFlowView, HomeView, FriendsView, SettingsView (B2) and HangoutFlowView, CreateHangoutFlowView (B3) — the app won't build until those exist. Mock TimeSlot ignores the server-only `durationMinutes`/`offerOnly` fields (not in the Swift model). Mock simulation: other members mirror the user's yes/maybe votes.

### 2026-10-04 — Dev B2 (account UI: auth, onboarding, Home, Friends, Settings)
- **Built:** every account-side screen against the mocks/protocols, matching docs/design (Main, Phone, Connect, Interests, Home, Friends, Settings).
  - `WelcomeView()`: 01 log in (phone + password, "+1" field) with a "Sign up" link. Sign-up is pushed in its own NavigationStack: 02 phone → SMS code (resend, digits-only, 6 long) → create password (≥ 6). Calls `sendCode`, then `verifyAndCreateAccount`. No email, Google or Apple sign-in. Input is normalized to E.164 (10 digits → +1).
  - `OnboardingFlowView(uid:)`: name + optional photo (PhotosPicker, saved on the device only in Documents/profile-<uid>.jpg; `photoURL` is not touched) → 03 (Apple Calendar required, Google shown as "Coming soon"; buffer stepper default 15 in 5-min steps with live example; approximate home rejects zip-only, then `env.functions.geocode`, keeping the text at 0/0 if that fails) → 03a optional interests (text + suggestion chips, "Skip for now"). It re-reads the profile, saves with `calendarConnected = true`, then calls `await env.auth.refresh()`.
  - `HomeView(uid:)`: live `observeMyHangouts` plus `observeMembers` per hangout. Sections: Needs your swipes / In progress / Coming up / Past, with a status line and call to action per status and member state (invite → Join, times/survey/cards not done → Swipe, noMutualTime → Pick, noAgreement → Swipe). Has a date tile + "N going", an empty state, header icons that switch to the Friends/Settings tabs via `TabRouter`, and `NavigationLink(value: HangoutRoute)` rows (`hangoutRow_<id>`) and `CreateHangoutRoute` (`createHangoutButton`). Cancelled and declined hangouts are hidden.
  - `FriendsView(uid:)`: friends list that reloads when the profile's friendIds change. Add by phone (`findUser` → `addFriend`; if the number isn't on Eklendi, show "Text an invite" (sms: link) + ShareLink). "Add from your contacts" opens the system CNContactPickerViewController (multi-select, no permission needed), normalizes and looks up each number, and shows the "Your contacts" sheet with On Eklendi (Add/Added) and Not on Eklendi yet (Invite → Messages).
  - `SettingsView(uid:)`: photo, name, phone (read-only), home location (re-geocoded on change), interests editor, buffer, Save changes (enabled only when something changed), Apple Calendar status/connect (Google coming soon), Log out, Delete account with inline confirmation.
- **Files:** `Eklendi/Features/Auth/{AccountLogic,WelcomeView}.swift`, `Eklendi/Features/Onboarding/{AccountComponents,OnboardingFlowView}.swift`, `Eklendi/Features/Home/{HomeSectioning,HomeView}.swift`, `Eklendi/Features/Friends/{ContactPicker,FriendsView}.swift`, `Eklendi/Features/Settings/SettingsView.swift`, `EklendiTests/AccountTests.swift`, `EklendiUITests/AccountFlowUITests.swift`.
- **Pure helpers (XCTest):** `AccountValidation` (phone → E.164, password, code), `HomeLocationValidation` (zip-only rejection), `BufferSetting`, `InterestSuggestions`, `InviteMessage.smsURL`, `ContactMatching`, `AccountFormat` (time range, dates), `HomeSectioning` (section/status/title per hangout).
- **UI tests:** sign up (5555550177, code 123456) → onboarding → Home; onboarding rejects zip-only and saves interests (`-uiTestingOnboarding`); Zach logs in → adds Noah by phone on Friends → logs out from Settings. **5555550101 is seeded as Seth in MockStore, so sign-up uses an unused number.**
- **Tickets:** KAL-7 (UI), KAL-8, KAL-9, KAL-10, KAL-13, KAL-14, KAL-15, KAL-16.
- **No changes** to Core/, ARCHITECTURE.md, App/ or mocks.
- **Gaps/TODO:** Swift unverified until CI/Mac. Profile photos stay on the device (no upload, so friends see initials). The phone screen has no country picker (US +1 only; any "+"-prefixed number still normalizes). Disconnecting Apple Calendar has to be done in iOS Settings. On Firebase, delete account may require a recent login; the error is shown. The "Your contacts" sheet only lists the contacts the user picked, not every contact on Eklendi.

### 2026-10-04 — Dev B3 (hangout UI)
- **Built:** the whole hangout UI on top of the B1 design system and mocks. `CreateHangoutFlowView(uid:)`: 05 Invite (1–7 friends, 2–8 people), 05a Plan (time + activity / just a time with required plan text, "what happens next" steps), 06 Duration (30m/1h/2h/3h + custom 1–12 h default 4, multi-select, "I don't care how long"; no travel/walk/stay-in), then `createHangout` and `router.openHangout(newId)` (replaces the create flow). `HangoutFlowView(hangoutId:uid:)` observes hangout + members + slots + current-round cards (`HFHangoutStore`) and routes by status and my progress (`HFRouting.screen`): join (Join / Decline sheet), starting point (home or somewhere else → geocode → setStartLocation; skipped in time-only) + automatic EventKit read (now…+30 days, requests access) → submitAvailability with my bufferMinutes, 10 Waiting (x of y, per-member status, owner Nudge/Remove with confirm), 08 Swipe times (SwipeCardStack; label, duration pill, date, weekday, range, reason, "Everyone's free"/"Without <name>"), 08a Day view (fullScreenCover; lanes of busy blocks + buffer shading, tapped slot highlighted, draggable/tap-to-teleport "your idea" block snapping to 15 min, −/+ steppers, length chips, day prev/next, live "Everyone's free"/"Matt is busy", Send / Send anyway → suggestTime), 08b No times (offers grouped everyone-free / all-but-one with who's missing, multi-pick → suggestTime each, "Suggest a different time" → day view, owner cancel), 09 Survey (14 cards, Yes/Maybe/No + "I don't care", "x of 14", no progress bar), generating, 11 Cards (photo or category gradient, bubble with when/duration/price/activity/venue·distance/address/description), 11a Not everyone agrees (top 3 by most yes → most maybe → earliest, per-member vote dots, "Swipe on N new ideas" → startNewRound), 12 It's a plan (details, who's going, calendar status, "I'm no longer available"/"Actually, I can make it"), cancelled, not-a-member. Owner menu (ellipsis): Reopen (confirmed only), Hand off (member picker), Cancel. Non-owners get "Decline hangout" top right until confirmed. Top-left back arrow everywhere, no "back to home" buttons, no "See the other ideas".
- **Calendar:** confirmed hangout is added to my calendar once (UserDefaults `ek.calendarEvent.<hangoutId>` = start|eventId; a reopened hangout with a new time replaces it), removed while I'm not going and when the hangout is cancelled/reopened.
- **Files:** `Eklendi/Features/Hangout/{CreateHangoutFlowView,HangoutFlowView,HangoutStore,HangoutFlowLogic,HangoutComponents,HangoutJoinViews,HangoutWaitingView,HangoutTimesViews,HangoutDecideViews}.swift`, `EklendiTests/HangoutTests.swift` (routing, formatting, winner/top-3 tallies, durations, day-view snap/clamp/buffer clashes/day clipping, local store, offerOnly decode), `EklendiUITests/HangoutFlowUITests.swift` (swipe 8 times → survey; day view open/close; survey + 9 cards → It's a plan; create hangout → starting point → times).
- **Contract change (additive):** `TimeSlot.offerOnly: Bool?` in `Core/Models.swift` (mirrors the server-written 08b offers). Swipe screens use `votableSlots` (offerOnly != true); 08b uses offerOnly slots, falling back to `source == .fallback` for the mock.
- **Tickets:** KAL-17, 18, 19, 20, 21, 26, 27, 28, 29, 30, 31 (UI), 37, 38, 39, 41, 42 (UI + calendar write), 43, 44, 45, 46, 47.
- **Gaps/TODO:** Swift unverified until CI/Mac. Starting point has Home + Somewhere else only ("Where I am now" needs CoreLocation, not added). Which slots I already swiped is remembered per device (UserDefaults), because the repository has no read for my own time votes; on a new device a re-swipe shows all slots again (votes merge, so harmless). Waiting screen shows "Nudged" but no push is sent (push deferred). 11a ranks from `cardVotes` on the client (server `topCardIds` isn't in the Swift model). Calendar invite status per other member isn't knowable client-side, so 12 shows Going / Not going instead of Sending… → Sent.

### 2026-10-04 — Director: Cloud Functions deployed
- Zach deployed functions + Firestore rules/indexes to eklendi-633e3 (us-central1; Firestore in nam5). Secrets GEMINI_API_KEY and GOOGLE_PLACES_API_KEY set in Secret Manager.
- Windows deploy tips: set FUNCTIONS_DISCOVERY_TIMEOUT=60 before `firebase deploy`; first 2nd-gen deploy needs a retry after Eventarc permissions propagate; use `--force` for the artifact cleanup policy.
- Redeploy after functions changes: `firebase deploy --only functions --project eklendi-633e3 --force`.
