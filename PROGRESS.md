# PROGRESS.md — Eklendi

Running log for agents and teammates. **Read this and `CLAUDE.md` before starting work.** Update it whenever you finish a ticket, start or merge a milestone branch, make a decision, or hit a blocker (newest entries at the top of the log).

## Current status

- **Phase:** Planning complete. **No app code written yet.**
- **Requirements:** `CLAUDE.md` (source of truth for product rules and engineering decisions).
- **Design:** clickable prototype canvas, 19 screens — https://claude.ai/artifact/SciRf8AwsmeDvkPSGDRtHv (shared "anyone with the link"). Screen numbers (01–12, with letter suffixes) are referenced in tickets.
- **Tickets:** Linear workspace `kalpeklendi`, team **Kalpeklendi**, project **Eklendi App**: KAL-5 to KAL-47, grouped into 6 milestones. KAL-1 to KAL-4 are Linear's default onboarding issues, not project work.
- **Repo:** only `CLAUDE.md`, `PROGRESS.md`, `README.md`, `LICENSE`, `.gitignore`. Planning docs not committed yet.

## Next steps

1. Create branch `milestone-1-foundations` and start **Milestone 1 · Foundations** (KAL-5 to KAL-12), in roughly this order:
   - KAL-5 iOS project (SwiftUI, iOS 17+), app shell, design tokens
   - KAL-6 Firebase project: Auth (phone), Firestore schema + security rules, Cloud Functions skeleton, FCM
   - KAL-7 phone sign-up (SMS verify) + password login, persistent session
   - KAL-12 reusable three-way swipe card stack (Urgent; most later screens depend on it)
   - KAL-8 onboarding: calendars (at least one required), buffer, approximate home location
   - KAL-9 optional interests, KAL-10 Home, KAL-11 push notifications
2. Set up XCTest + XCUITest targets in KAL-5 so every later ticket ships with tests.
3. Move tickets to In Progress / Done in Linear as they're picked up and finished; assign to Zach.
4. Open one PR per milestone branch.

## Things to know

- **Stack decisions:** Firebase replaces CloudKit. All third-party API keys (Gemini, Google Places, Google OAuth secrets) live only in Cloud Functions. Store times in UTC.
- **Order of decisions in a hangout:** time first (everyone swipes, winner picked), then activity survey, then hangout cards at the winning time.
- **The prototype is a design reference, not code to port.** It's HTML on a design canvas; build native SwiftUI.
- **Known prototype mismatches** (CLAUDE.md wins):
  - Screen 03 lets you continue without connecting a calendar; the app must require at least one.
  - Screen 08 shows one Friday slot as a range ("7:00 – 10:00 PM"); real slots are specific start/end times.
  - Screen 08a always shows Thursday (prototype limitation); the real day view shows the tapped card's day.
- **Open questions:** none (see CLAUDE.md "Open questions").

## Log

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
