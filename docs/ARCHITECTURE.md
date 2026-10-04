# Eklendi — Architecture & Contracts

This file is the **contract** every agent builds against. Change it only deliberately, and update both sides (iOS `Eklendi/Core/` and `functions/src/types.ts`) in the same commit.

## Overview

```
iOS app (SwiftUI, iOS 17)                    Firebase (project eklendi-633e3)
─────────────────────────                    ───────────────────────────────
Auth: phone verify + password  ───────────▶  Firebase Auth
Reads/writes documents          ◀─────────▶  Firestore (real-time listeners)
EventKit: reads busy blocks,                 Cloud Functions (Node 20, TypeScript)
  writes the confirmed event                   • advanceHangout (Firestore triggers):
Calls callables  ───────────────────────▶        availability → slots → time winner →
                                                 survey → cards → card winner → confirmed
                                               • callables: suggestTime, geocodeLocation
                                               • Gemini + Google Places (keys = function secrets)
```

- **All group logic runs in Cloud Functions** (free windows, buffers, slot ranking, horizon, fallback, winner rules + ties, preference model, centroid, Gemini, Places). It is unit-tested with `node:test` in `functions/test/`.
- **The iOS app never holds Gemini/Places keys.** It only talks to Firebase.
- **All times are stored as Firestore `Timestamp` (UTC)** and displayed in the device's local time zone.
- **Push notifications are out of scope for now** (need a paid Apple account). Screens update live via Firestore listeners.

## Firestore data model

`uid` = Firebase Auth user id. Field names are exactly as written (camelCase).

### `users/{uid}`
| field | type | notes |
|---|---|---|
| phone | string | E.164, e.g. `+15555550101` |
| name | string | |
| photoURL | string? | |
| homeLocation | Location? | approximate home (no zip-only) |
| bufferMinutes | int | default 15 |
| interests | string | optional free text, `""` if skipped |
| calendarConnected | bool | must be true to finish sign-up |
| friendIds | [string] | uids; adding a friend writes both users (arrayUnion) |
| createdAt | Timestamp | |

`Location` = `{ text: string, lat: double, lng: double }`

### `phoneIndex/{e164}`
`{ uid: string }` — written at sign-up; used to find friends by phone number.

### `hangouts/{hangoutId}`
| field | type | notes |
|---|---|---|
| ownerId | string | |
| title | string | `""` until confirmed; time-only mode uses `planDescription` |
| mode | string | `timeAndActivity` \| `timeOnly` |
| planDescription | string | time-only mode only |
| durationsMinutes | [int] | multi-select; custom = hours×60 |
| durationAny | bool | "I don't care how long" |
| memberIds | [string] | everyone still in (owner included). Used for queries. |
| status | string | see state machine |
| horizonDays | int | 14, extended to 30 |
| round | int | hangout-card round, starts 1 |
| winningSlot | Slot? | set when the time is decided |
| confirmed | Confirmed? | set when status = confirmed |
| statusMessage | string | short human text for UI, optional |
| createdAt / updatedAt | Timestamp | |

`Slot` = `{ id: string, start: Timestamp, end: Timestamp }`
`Confirmed` = `{ start, end, activity: string, venueName: string, address: string, cardId: string? }`

### `hangouts/{id}/members/{uid}`
| field | type | notes |
|---|---|---|
| name | string | denormalized |
| role | string | `owner` \| `member` |
| state | string | `invited` \| `active` \| `declined` \| `removed` |
| availabilitySubmitted | bool | busy blocks uploaded |
| busy | [{start, end}] | Timestamps, horizon window only, **no event details** |
| bufferMinutes | int | copied from user |
| startLocation | Location? | time+activity mode |
| timesDone | bool | finished swiping times |
| surveyDone | bool | |
| cardsDoneRound | int | last card round finished (0 = none) |
| notGoing | bool | "I'm no longer available" after confirmation |
| nudgedAt | Timestamp? | owner nudge |
| timeZone | string | IANA id (e.g. `America/Chicago`), written with availability; used for "sensible hours" |

A member counts as **participating** when `state == "active"` (invitees become active when they open the hangout; owner is active from creation). Declined/removed members are excluded from every "everyone" rule.

### `hangouts/{id}/slots/{slotId}`
`{ start, end, source: "computed"|"suggested"|"fallback", suggestedBy?: uid, missingMemberIds: [uid], rank: int, label: string, reason: string }`
- "Sensible hours": slots start no earlier than 9:00 and end no later than 23:00 in the owner's `timeZone` (fallback `America/Chicago`). Slots start on :00 or :30. Never start within 1 hour of now.
- Max 8 `computed` slots. `label` e.g. "Best match", "Weeknight", "Weekend". `reason` e.g. "Starts 15 min after Matt's class ends".
- `missingMemberIds` non-empty only for "all but one" fallback slots.

### `hangouts/{id}/timeVotes/{uid}`  `{ votes: { [slotId]: "yes"|"maybe"|"no" } }`
### `hangouts/{id}/surveyAnswers/{uid}` `{ answers: { [questionId]: "yes"|"maybe"|"no"|"dontCare" } }`
### `hangouts/{id}/cards/{cardId}`
`{ round, activity, description, category, venueName, address, lat, lng, distanceMiles, priceLevel: int?, photoUrl: string?, placeId, start, end, tags: [string] }`
### `hangouts/{id}/cardVotes/{uid}_{round}` `{ round, votes: { [cardId]: "yes"|"maybe"|"no" } }`

## Hangout state machine (`status`)

```
collectingAvailability ──(all active members availabilitySubmitted)──▶ computeSlots
   computeSlots: 14-day horizon → ≤8 slots ? votingTimes
                 : extend to 30 days → slots ? votingTimes
                 : "all but one" slots ? votingTimes (fallback, shows who's missing)
                 : noMutualTime
votingTimes ──(all active timesDone, incl. answers to every slot)──▶ winner?
   winner → timeOnly ? confirmed : survey
   none   → noMutualTime  (fallback slots offered, see 08b)
survey ──(all active surveyDone)──▶ generating ──▶ votingCards (round N, 3 × active members cards)
votingCards ──(all active cardsDoneRound == round)──▶ winner ? confirmed : noAgreement
noAgreement ──(member taps "Swipe on new ideas" → round+1, status generating)──▶ votingCards
any ──owner cancel──▶ cancelled ;  confirmed ──owner reopen──▶ collectingAvailability (survey retaken)
```
- Suggested time (08a): adds a `suggested` slot; members with `timesDone` get `timesDone=false` so they swipe the new card; winner waits for everyone.
- Survey questions (ids) — fixed, same for everyone:
  `food, active, games, arts, nature, markets, events, indoors, outdoors, priceLow, priceMid, priceHigh, chill, lively`

### Winner rules (CLAUDE.md "Deciding a winner")
1. Options with **yes from every participating member** → pick best.
2. Else options where everyone said **yes or maybe** → pick best.
3. Else none. "Best" = most yes, then fewest maybe, then earliest start.

## Cloud Functions (`functions/src`)

| name | kind | purpose |
|---|---|---|
| `onMemberWrite`, `onTimeVoteWrite`, `onSurveyWrite`, `onCardVoteWrite`, `onHangoutWrite` | Firestore triggers | each calls `advanceHangout(hangoutId)` — idempotent state machine in a transaction |
| `suggestTime` | callable `{hangoutId, start, end}` | adds suggested slot, resets `timesDone` |
| `startNewRound` | callable `{hangoutId}` | from `noAgreement`: round+1 → generate |
| `geocodeLocation` | callable `{text}` → `{text, lat, lng}` | Places text search; used for home/start location |

Pure logic modules (no Firebase imports, fully unit-tested): `scheduling.ts`, `winner.ts`, `preferences.ts`, `geo.ts`. Firebase/HTTP glue: `advance.ts`, `gemini.ts`, `places.ts`, `index.ts`.

Secrets: `firebase functions:secrets:set GEMINI_API_KEY` and `GOOGLE_PLACES_API_KEY`.

## iOS structure (`Eklendi/`)

```
App/            EklendiApp, RootView (auth gate), AppEnvironment
Core/           Models.swift (Codable mirrors of the data model), Services.swift (protocols)
Services/       Firebase*.swift implementations, CalendarService (EventKit), Mock*.swift
DesignSystem/   Theme (tokens), buttons, chips, fields, SwipeCardStack
Features/       one folder per area: Auth, Onboarding, Home, Friends, Settings, Hangout
```
- Views depend only on the **protocols** in `Core/Services.swift`, injected via `AppEnvironment` (`@Environment(AppEnvironment.self)`). `AppEnvironment.mock` powers previews and UI work before the backend is ready.
- Screen numbers (01–12, 03a, 04a, 05a, 08a, 08b, 11a) match the design canvas and Linear tickets.
