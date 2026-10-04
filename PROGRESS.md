# PROGRESS.md — Eklendi

Running log for agents and teammates. **Read this and `CLAUDE.md` before starting work.** Update it whenever you finish a ticket, start or merge a milestone branch, make a decision, or hit a blocker (newest entries at the top of the log).

## Current status

- **Phase:** Planning complete. **No app code written yet.**
- **Requirements:** `CLAUDE.md` (source of truth for product rules and engineering decisions).
- **Design:** clickable prototype canvas, 19 screens — https://claude.ai/artifact/SciRf8AwsmeDvkPSGDRtHv (shared "anyone with the link"). Screen numbers (01–12, with letter suffixes) are referenced in tickets.
- **Tickets:** Linear workspace `kalpeklendi`, team **Kalpeklendi**, project **Eklendi App**: KAL-5 to KAL-47, grouped into 6 milestones. KAL-1 to KAL-4 are Linear's default onboarding issues, not project work.
- **GitHub:** https://github.com/claireking10/eklendi. Planning docs are committed on branch `docs/planning` (not merged to `main`, not pushed).
- **Repo:** only `CLAUDE.md`, `PROGRESS.md`, `README.md`, `LICENSE`, `.gitignore`. 

## BUILD STATUS (read first) — hackathon, deadline noon CDT Sun Oct 4

- **Branch:** `hackathon/build` (all hackathon work; branched from `docs/planning`). Push with `git push -u origin hackathon/build` (Zach runs it).
- **Scope:** everything in CLAUDE.md + Linear, built in priority order: demo path first (sign up → create hangout → swipe times → survey → Gemini/Places cards → confirmed in Apple Calendar), then remaining tickets. Deferred: push notifications (needs paid Apple account), Google Calendar (OAuth).
- **Contract:** `docs/ARCHITECTURE.md` — Firestore model, state machine, functions, iOS structure. iOS contracts in `Eklendi/Core/` (Models.swift, Services.swift); logic types in `functions/src/logic/types.ts`.
- **Team (multi-agent workflow, directed by the main Claude session):**
  - Dev A — backend logic: `functions/src/` (scheduling, winner, state machine, triggers, callables) + `node:test` tests.
  - Dev B — iOS UI: `Eklendi/DesignSystem/`, `Eklendi/Features/`, `Eklendi/App/RootView.swift`, `Eklendi/Services/Mock*.swift`, UI tests.
  - Dev C — integrations: `Eklendi/Services/Firebase*.swift`, `CalendarService.swift`, `AppEnvironment+Live.swift`; `functions/src/{gemini,places,preferences,geo}` pieces.
  - QA — reviews each area against CLAUDE.md/tickets, runs logic tests, hunts Swift compile errors.
- **Tooling limits:** agents have no Swift/Xcode/npm. Logic tests run here (`cd functions && npm test`). iOS build + UI tests run in GitHub Actions (`.github/workflows/ci.yml`) and on the teammate's Mac (see README).
- **Status:** skeleton committed (project.yml, contracts, CI, harness). Agents being launched.

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
