# CLAUDE.md — Eklendi

Guidance for Claude agents working on this codebase. Read this before making changes.

## What Eklendi is

An iOS app that helps a friend group pick a **time** and an **activity** for a hangout without the back-and-forth.

- Each member answers prompts **asynchronously** by swiping.
- The app combines their calendars, preferences, and zip codes.
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
2. **Set constraints** (creator, right after inviting):
   - Duration: 30 min, 1 hr, 2 hr, 3 hr, longer — **multi-select**.
   - Travel mode: walking, driving, staying in — **multi-select**.
3. **Times.** The app reads each member's calendar for the selected week, removes busy times (with buffers), and computes mutual free windows. Members swipe on the candidate time slots.
4. **Activity preferences.** Members swipe on activity prompts, moving from **general → specific** (e.g. "Go out?" → "Food?" → "Cafe or restaurant?").
5. **Generate.** After everyone responds, the app builds a group preference model and generates a small set of hangout cards.
6. **Vote.** Members swipe on the cards.
7. **Confirm.** When a time and activity are agreed on, the app automatically creates and sends a calendar invite to every member.

## Hangout cards

Each card shows:

- Date and time
- Location (a real venue from Google Places, or "At home")
- Activity name
- A short description (Gemini)
- Background image of **that specific venue** (Places photo). Example: bowling at a given alley shows that alley.

## Requirements

### Calendars and scheduling

- Read calendars from **EventKit** and **Google Calendar**; merge both into one busy/free view per user.
- Display multiple friends' schedules for a selected week.
- Compute mutual free windows across all members.
- **Buffers:** never schedule a hangout to start the instant another event ends (or end the instant one starts). Default buffer is **15 minutes**, configurable per user. Example: class ends 3:00 PM → earliest start is 3:15 PM.
- A free window must fit at least one selected duration, including buffers.

### No mutual availability

- If no window works for everyone, suggest **alternative dates** (e.g. the following week, or windows where all but one member is free — show who is missing).

### Group preference model

Build one shared model from all members' inputs:

- Duration
- Walking vs. driving
- Staying in vs. going out
- Indoor vs. outdoor
- Budget
- Food preferences
- Activity preferences
- Group size
- Members' zip codes (for locality)

### "I don't care" handling — HIGH PRIORITY

Many users can't or won't decide. Treat this as a first-class case, not an edge case.

- Every preference prompt must offer an "I don't care" path.
- "I don't care" is **neutral**: it must not constrain the result, and it must not count as a No.
- If most of the group doesn't care about a dimension, the app picks a sensible default instead of asking more questions.

### Idea generation (Gemini)

- Return a **small** set of options that suit the whole group — the app decides so users don't have to search.
- Respect selected durations, travel modes, and locality (members' zip codes).
- Categories include: restaurants, cafes, parks, movies, games, events, at-home activities, walks, short trips.

### Confirmation

- Auto-generate and send a calendar invite (to EventKit and/or Google, per member) once a time and activity are agreed on.

## Open questions

Don't invent answers to these. Ask the user or leave a clear `TODO`.

- **Where do base preferences come from?** User profiles, an onboarding quiz, per-hangout prompts, or a mix?
- **"Longer" duration:** what range does it mean for scheduling?
- **Alternative-date rules:** how far out to look, and whether "all but one free" is acceptable.
- **Group location:** how to choose a search area when members live in different zip codes (centroid? travel-time fairness?).
- **Who can confirm** a hangout, and what happens if someone never responds (timeout?).
