# CLAUDE.md — Eklendi

Guidance for Claude agents working on this codebase. Read this before making changes.

## What Eklendi is

An iOS app that helps a friend group pick a **time** and an **activity** for a hangout without the back-and-forth.

- Each member answers prompts **asynchronously** by swiping.
- The app combines their calendars, preferences, and locations (approximate home, or where they'll travel from).
- Hangouts are always **out somewhere** — there are no stay-in or at-home options.
- It suggests a small set of specific, local hangouts (date + time + place + activity).
- Once the group agrees, it sends a calendar invite.

**Product goal:** reduce decision fatigue. Hangouts should feel relaxed, not transactional. When in doubt, choose the option that asks users to decide *less*.

## Tech stack

| Layer | Technology |
|---|---|
| App | Swift (iOS) |
| Backend / sync | CloudKit |
| Calendars | Apple EventKit **and** Google Calendar API |
| Idea generation | Gemini API |
| Real venues, hours, photos | Google Places API |

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
3. If nothing passes step 2, fall back to alternatives (see "No mutual availability" below).

## User flow

1. **Create.** A user starts a hangout and invites friends. Each invitee gets a push notification.
2. **Choose what to decide** (owner, right after inviting):
   - **A time and an activity** — the full flow below.
   - **Just a time** — the owner already has something in mind and enters a short description of the plan (used on the calendar invite). Skip activity preferences, generation and card voting (steps 5–7 below); the hangout confirms as soon as a time is agreed.
3. **Set constraints** (creator):
   - Duration: 30 min, 1 hr, 2 hr, 3 hr, custom (the creator enters a number of hours) — **multi-select**.
   - The creator is the hangout's **owner** (see "Unresponsive members").
4. **Times.** In "A time and an activity" mode, each member first picks the **location they'll be traveling from** (home, current location, or somewhere else); it's used to prioritize nearby hangouts. Skipped in "Just a time" mode. The app then reads each member's calendar across the **search horizon** (see "Time horizon"), removes busy times (with buffers), and computes mutual free windows. Members go straight to swiping on the candidate time slots (there is no week-overview screen).
5. **Activity preferences.** Members swipe on activity prompts, moving from **general → specific** (e.g. "Food?" → "Cafe or restaurant?").
6. **Generate.** After everyone responds, the app builds a group preference model and generates a small set of hangout cards.
7. **Vote.** Members swipe on the cards.
8. **Confirm.** A hangout is **confirmed automatically** when everyone agrees on a time and activity; there is no manual confirm step. The app then creates and sends a calendar invite to every member.

## Hangout cards

Each card shows:

- Date and time
- Location (a real venue from Google Places)
- Activity name
- A short description (Gemini)
- Background image of **that specific venue** (Places photo). Example: bowling at a given alley shows that alley.

## Requirements

### Accounts

- Users sign in with their **phone number** as their username. No email, and no Google or Apple sign-in.

### Friends

- A Friends screen lists the user's friends.
- Users can add new friends from their **iPhone contacts** (optional).

### Settings

Users can:

- Set their approximate home location.
- Change their buffer time.
- Change their name and profile picture.
- Delete their account.

### Calendars and scheduling

- Read calendars from **EventKit** and **Google Calendar**; merge both into one busy/free view per user.
- From a time-slot card, **View availability** opens a **one-day calendar** of just that day, showing every member's busy and free times (busy blocks only, never event details).
- From that day view, a member can **suggest another time**. The suggestion is forwarded to the rest of the group as a new candidate slot to swipe on.
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

**Base preferences start as a blank slate.** A user's preferences are populated only from their answers to per-hangout prompts over time.

### "I don't care" handling — HIGH PRIORITY

Many users can't or won't decide. Treat this as a first-class case, not an edge case.

- Every preference prompt must offer an "I don't care" path.
- "I don't care" is **neutral**: it must not constrain the result, and it must not count as a No.
- If most of the group doesn't care about a dimension, the app picks a sensible default instead of asking more questions.

### Idea generation (Gemini)

- Return a **small** set of options that suit the whole group — the app decides so users don't have to search.
- Respect selected durations and locality (members' starting locations).
- Categories include: restaurants, cafes, parks, movies, games, events, walks, short trips.

### Confirmation

- Confirmation is automatic once everyone agrees on a time and activity.
- Auto-generate and send a calendar invite (to EventKit and/or Google, per member) at that point.
- After confirmation, a member can tap **"I'm no longer available"**. The other members are notified that this person can't go; nothing else about the hangout changes (time, place and everyone else's invites stay the same). The member is simply marked as not going.

### Location

- Each user enters their **approximate home location**. Do not accept a zip code on its own: it isn't precise enough to find nearby places.
- Before swiping on times, each member picks where they'll be traveling from; it defaults to their approximate home location.
- The search area for venues is prioritized around the **centroid** of members' starting locations.

### Unresponsive members

- The hangout's owner (its creator) can **nudge** members who haven't responded.
- The owner can also **remove** an unresponsive member, so the group can move on without them.

## Open questions

Don't invent answers to open questions. Ask the user or leave a clear `TODO`.

_None right now._
