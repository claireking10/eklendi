# CLAUDE.md — Eklendi

Guidance for Claude agents working on this codebase. Read this before making changes.

**Also read `PROGRESS.md`** before starting work, and update it as you go (see "Progress log" below).

## What Eklendi is

An iOS app that helps a friend group pick a **time** and an **activity** for a hangout without the back-and-forth.

- Each member answers prompts **asynchronously** by swiping.
- The app combines their calendars, preferences, and locations (approximate home, or where they'll travel from).
- Hangouts are always **out somewhere** — there are no stay-in or at-home options.
- It suggests a set of specific, local hangouts (date + time + place + activity): **3 × the number of people in the group** per round.
- Once the group agrees, it sends a calendar invite.

**Product goal:** reduce decision fatigue. Hangouts should feel relaxed, not transactional. When in doubt, choose the option that asks users to decide *less*.

## Tech stack

| Layer | Technology |
|---|---|
| App | Swift + **SwiftUI**, minimum **iOS 17** |
| Backend / sync | **Firebase**: Auth (phone), Firestore (data + real-time sync), Cloud Functions (server logic, API calls), FCM (push) |
| Calendars | Apple EventKit **and** Google Calendar API |
| Idea generation | Gemini API |
| Real venues, hours, photos | Google Places API |

All third-party API keys (Gemini, Google Places, Google Calendar OAuth secrets) live **only in Cloud Functions**, never in the app.

Gemini decides *what kinds* of hangouts fit the group and writes descriptions. Google Places supplies *real* venues and photos. Never show a venue, address, or image that came only from Gemini output — always resolve it through Places.

## Core interaction: the swipe

Every prompt in the app (time slots, activity types, final hangout cards) uses the same three-way swipe:

| Swipe | Meaning |
|---|---|
| Right | **Yes** — I want this |
| Down | **Maybe** — I'd do it if nothing I prefer is chosen |
| Left | **No** — decline |

Keep this mapping consistent across every screen.

### Deciding a winner

1. If one or more options got **Yes from every member**, choose from those.
2. Otherwise, include Maybes: consider options where every member said Yes **or** Maybe. Rank by number of Yes votes.
   - **Ties:** rank by most Yes, then fewest Maybes, then earliest date.
3. If nothing passes step 2, fall back to alternatives: for time slots, see "No mutual availability" below; for hangout cards, see "No agreement on a hangout" below.

## User flow

1. **Create.** A user starts a hangout and invites friends. Each invitee gets a push notification.
2. **Choose what to decide** (owner, right after inviting):
   - **A time and an activity** — the full flow below.
   - **Just a time** — the owner already has something in mind and enters a short description of the plan (used on the calendar invite). Skip activity preferences, generation and card voting (steps 5–7 below); the hangout confirms as soon as a time is agreed.
3. **Set constraints** (creator):
   - Duration: 30 min, 1 hr, 2 hr, 3 hr, custom (the creator enters **1–12 hours**, default 4) — **multi-select**.
   - The creator is the hangout's **owner** (see "Unresponsive members").
4. **Times.** (The time is decided **first**: everyone swipes on times and a winning time is chosen before the activity steps start; all hangout cards are at that time.) In "A time and an activity" mode, each member first picks the **location they'll be traveling from** (home, current location, or somewhere else); it's used to prioritize nearby hangouts. Skipped in "Just a time" mode. The app then reads each member's calendar across the **search horizon** (see "Time horizon"), removes busy times (with buffers), and computes mutual free windows. Members go straight to swiping on the candidate time slots (there is no week-overview screen).
5. **Activity preferences.** Every member answers the **same fixed survey** (no branching), swiping on each prompt. The survey covers every general category: **activity type** (food & drink, active, games, arts & entertainment, nature, markets & shopping, events), **setting** (indoors, outdoors), **price** (free/under $15, $15–$30, over $30 per person) and **vibe** (chill, lively). Each prompt offers "I don't care".
6. **Generate.** After everyone responds, the app builds a group preference model and generates a round of hangout cards (3 × the number of people in the group).
7. **Vote.** Members swipe on the cards.
8. **Confirm.** A hangout is **confirmed automatically** when everyone agrees on a time and activity; there is no manual confirm step. The app then creates and sends a calendar invite to every member.

## Hangout cards

Each card shows:

- Date and time
- Location (a real venue from Google Places)
- Activity name
- A short description (Gemini)
- Background image of **that specific venue** (Places photo). Example: bowling at a given alley shows that alley.

Each round contains **3 × the number of people in the group** cards (e.g. 12 cards for 4 people).

### No agreement on a hangout

- Once everyone has finished swiping a round, apply "Deciding a winner". If no card passes, show a **"Not everyone agrees"** screen.
- That screen lists the **top 3** hangouts that the most people agreed to (ranked by Yes votes), showing how each member voted.
- From there, members swipe on a **new round** of cards (again 3 × the number of people).

## Requirements

### Accounts

- Users sign in with their **phone number** as their username. No email, and no Google or Apple sign-in.
- Sign-up verifies the number with an **SMS code**; after that, users log in with **phone number + password**.
- Users **stay logged in** on the same device until they log out or delete their account.

### Friends

- A Friends screen lists the user's friends.
- Users can add new friends from their **iPhone contacts** (optional). Contacts already on Eklendi get an **Add** button; contacts not on Eklendi get an **Invite** button that texts them an invite.

### Settings

Users can:

- Set their approximate home location.
- Change their buffer time.
- Change their name and profile picture.
- Edit the hangout interests they entered at sign-up.
- Delete their account.

### Calendars and scheduling

- Read calendars from **EventKit** and **Google Calendar**; merge both into one busy/free view per user.
- Connecting **at least one calendar is required** to finish sign-up.
- Show **at most 8** candidate time slots per hangout, ranked (soonest, roomiest, sensible hours).
- Each slot is a **specific start and end time** (e.g. 7:00–8:00 PM), not a whole free window.
- Store all times in **UTC**; display them in each viewer's local time zone.
- From a time-slot card, **View availability** opens a **one-day calendar** of just that day, showing every member's busy and free times (busy blocks only, never event details).
- From that day view, a member can **suggest another time**. The suggestion is forwarded to the rest of the group as a new candidate slot to swipe on: members who already finished get a push and swipe just that one card, and the time isn't decided until everyone has answered it.
- Compute mutual free windows across all members.
- **Buffers:** never schedule a hangout to start the instant another event ends (or end the instant one starts). Default buffer is **15 minutes**, configurable per user. Example: class ends 3:00 PM → earliest start is 3:15 PM.
- A free window must fit at least one selected duration, including buffers.

### Time horizon

- Search for time matches over the **next 2 weeks** first.
- If no matches are found, extend the horizon to **one month**.
- Members don't pick a week; the app searches the horizon automatically.

### No mutual availability

- If no window works for everyone, suggest **alternative dates**:
  - Extend the search horizon from 2 weeks to **one month** (see "Time horizon").
  - Windows where **all but one** member is free are acceptable suggestions — always show who is missing.

### Group preference model

Build one shared model from all members' inputs:

- Duration
- Indoor vs. outdoor
- Budget
- Food preferences
- Activity preferences
- Group size
- Members' starting locations (for locality)

**Base preferences:**

- At sign-up, users get an **optional** free-text prompt to describe the kinds of hangouts they're interested in (natural language, in a text box). They can skip it and edit it later in Settings. Tappable suggestion chips (e.g. Coffee shops, Live music, Hiking) append to the text.
- If provided, this text seeds the user's personal preferences. Otherwise preferences start as a blank slate.
- Preferences are then refined from their answers to per-hangout prompts over time.
- These interests are a **soft signal**: they make matching hangouts more likely but must never completely prevent the app from suggesting hangouts that don't match them.

### "I don't care" handling — HIGH PRIORITY

Many users can't or won't decide. Treat this as a first-class case, not an edge case.

- Every preference prompt must offer an "I don't care" path.
- "I don't care" is **neutral**: it must not constrain the result, and it must not count as a No.
- If most of the group doesn't care about a dimension, the app picks a sensible default instead of asking more questions.

### Idea generation (Gemini)

- Return **3 × the number of people in the group** options per round that suit the whole group — the app decides so users don't have to search.
- Respect selected durations and locality (members' starting locations).
- Categories include: restaurants, cafes, parks, movies, games, events, walks, short trips.

### Confirmation

- Confirmation is automatic once everyone agrees on a time and activity.
- At that point, write the event **directly into each member's own calendar** (EventKit for Apple Calendar, Google Calendar API for Google). No email invites.
- After confirmation, a member can tap **"I'm no longer available"**. The other members are notified that this person can't go; nothing else about the hangout changes (time, place and everyone else's invites stay the same). The member is simply marked as not going. They can undo with **"Actually, I can make it"**, which marks them as going again and notifies the others.

### Location

- Each user enters their **approximate home location**. Do not accept a zip code on its own: it isn't precise enough to find nearby places.
- Before swiping on times, each member picks where they'll be traveling from; it defaults to their approximate home location.
- The search area for venues is prioritized around the **centroid** of members' starting locations.

### Declining a hangout

- Anyone added to a hangout by someone else has a **"Decline hangout"** button.
- Declining removes them from the group; the rest of the group keeps planning without them, and the owner is told they declined.

### Groups and ownership

- A hangout has **2 to 8 people** (including the owner).
- The owner can **cancel** the hangout at any time (everyone is notified; calendar events are removed).
- The owner can **reopen** a confirmed hangout and send it back to planning. Everyone takes the activity survey again.
- The owner can **hand off ownership** to another member. Ownership must also pass to someone else if the owner declines or deletes their account; in that case the new owner is picked **at random** from the remaining members.

### Unresponsive members

- The hangout's owner (its creator) can **nudge** members who haven't responded.
- The owner can also **remove** an unresponsive member, so the group can move on without them.

## Engineering workflow

- One git branch **per Linear milestone**, merged by pull request after review.
- **Secrets (the repo is public):** never commit `GoogleService-Info.plist`, `.env` or `Config/Secrets.xcconfig` (all gitignored). Gemini and Places keys live only in Cloud Functions secrets (`firebase functions:secrets:set`); the app never holds them. `scripts/make-secrets.sh` generates `Config/Secrets.xcconfig` (Firebase encoded app id) from the plist. Teammates get the plist privately; CI gets it from the `GOOGLE_SERVICE_INFO_PLIST_BASE64` GitHub secret.
- **Pushing:** agents can commit but **cannot push** (GitHub is blocked from the agent environment). Whenever a push is needed, give Zach the exact command to paste into his terminal, e.g. `git push -u origin <branch>`, and note it in PROGRESS.md.
- **Architecture contract:** `docs/ARCHITECTURE.md` (Firestore data model, hangout state machine, functions, iOS structure). Build against it; change it deliberately and update both sides.
- Tests: **core group logic** (free windows, buffers, slot ranking, horizon extension, winner rules and ties, "I don't care", centroid, preference model) lives in `functions/src/logic/` as pure TypeScript with **Node `node:test` tests** (`cd functions && npm test`), runnable in the agent environment. **XCTest** for iOS view-model logic and **XCUITest** for the main flows (run with the `-uiTesting` launch argument, which swaps in mock services).
- Work through the Linear tickets in milestone order (Foundations first).
- **CI:** a GitHub Actions workflow on a **macOS runner** builds the app and runs all unit and UI tests on every milestone-branch push and PR. Check it passes before handing a branch to the team.
- Agents work in a Linux environment **without Xcode, Swift, or npm access** (only Node 22 + global `tsc`). Keep group logic in `functions/src/logic/` (no imports outside that folder) so it compiles and tests here; Firebase glue code and all Swift are verified only by CI and the Mac. Write Swift conservatively.
- **Xcode project is generated by XcodeGen** from `project.yml` (the `.xcodeproj` is not committed). New Swift files under `Eklendi/` are picked up automatically after `xcodegen generate`.
- **Push notifications (FCM) and Google Calendar are deferred**: push needs a paid Apple account; Google Calendar needs OAuth setup. Screens update live via Firestore listeners; calendars use EventKit.
- **Manual testing** is done by a teammate on a Mac (Xcode Simulator or their iPhone over cable). There's no paid Apple Developer account yet, so no TestFlight or device push notifications until one is added.

## Progress log

`PROGRESS.md` is the running log of what has been done and what's next, so a new agent can pick up where the last one stopped.

- Read it before starting.
- Update it whenever you finish a ticket, start or merge a milestone branch, make a decision, or hit a blocker. Add a dated entry at the top of the log and keep "Current status" and "Next steps" accurate.
- Keep entries short and factual: what changed, where (files, branch, ticket), and what's left.

## Open questions

Don't invent answers to open questions. Ask the user or leave a clear `TODO`.

_None right now._
