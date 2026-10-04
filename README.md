# Eklendi

Friend groups swipe on times and activities; the app finds a time everyone's free and a real local hangout, then puts it on everyone's calendar.

- Product rules: [`CLAUDE.md`](CLAUDE.md) · Architecture & data model: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) · Progress log: [`PROGRESS.md`](PROGRESS.md)

## Run the iOS app (Mac)

1. Install Xcode 16+ and XcodeGen: `brew install xcodegen`
2. Put `GoogleService-Info.plist` (from Zach, never commit it) in the repo root.
3. `./scripts/make-secrets.sh && xcodegen generate`
4. `open Eklendi.xcodeproj` → choose an iPhone simulator → ⌘R (run) or ⌘U (tests).
   - Demo logins use Firebase test phone numbers (e.g. +1 555-555-0101, code 111111).
   - The app runs in **demo mode** by default: mock data, log in with any 10-digit number and any password, and preset friends whose choices your swipes are compared against. Launch with `-liveBackend` to use Firebase.
5. Re-run `xcodegen generate` after pulling (the .xcodeproj is generated, not committed).

## Cloud Functions

- Logic tests (no network needed): `cd functions && npm test`
- Deploy (needs Firebase Blaze plan + CLI login):
  ```
  npm i -g firebase-tools && firebase login
  firebase functions:secrets:set GEMINI_API_KEY
  firebase functions:secrets:set GOOGLE_PLACES_API_KEY
  cd functions && npm install && cd .. && firebase deploy --only functions,firestore
  ```
