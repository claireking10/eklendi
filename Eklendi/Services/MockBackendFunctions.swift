import Foundation
import FirebaseCore
import FirebaseFunctions

/// In-memory stand-ins for the callables (suggestTime, startNewRound, geocodeLocation).
@MainActor
final class MockBackendFunctions: BackendFunctions {
    private let store: MockStore

    init(store: MockStore) {
        self.store = store
    }

    /// Adds a `suggested` slot; members who finished swiping must answer it (others are
    /// simulated as having said yes right away).
    func suggestTime(hangoutId: String, start: Date, end: Date) async throws {
        guard end > start else { throw MockServiceError("The end time must be after the start time.") }
        guard store.hangouts[hangoutId] != nil else { throw MockServiceError("Hangout not found.") }
        var slot = TimeSlot(start: start, end: end, source: .suggested)
        slot.id = store.newId("\(hangoutId)_sugg")
        slot.rank = (store.slots[hangoutId]?.count ?? 0) + 1
        slot.label = "Suggested"
        slot.reason = "Suggested from the day view."
        store.slots[hangoutId, default: []].append(slot)
        // Everyone who already voted answers the new card immediately (simulated); the
        // signed-in user swipes it like any other card.
        let voters: [String] = Array((store.timeVotes[hangoutId] ?? [:]).keys)
        for uid in voters {
            store.timeVotes[hangoutId]?[uid]?[slot.id] = .yes
        }
        store.updateHangout(hangoutId) { h in
            if h.status == .noMutualTime { h.status = .votingTimes }
        }
        // From noMutualTime the user swipes again (just the new card is unanswered).
        if store.hangouts[hangoutId]?.status == .votingTimes {
            let all: [String] = Array((store.members[hangoutId] ?? [:]).keys)
            for uid in all where store.timeVotes[hangoutId]?[uid]?[slot.id] == nil {
                store.updateMember(hangoutId, uid) { $0.timesDone = false }
            }
        }
        store.notify()
    }

    func startNewRound(hangoutId: String) async throws {
        guard let h = store.hangouts[hangoutId] else { throw MockServiceError("Hangout not found.") }
        let next: Int = h.round + 1
        store.updateHangout(hangoutId) { h in
            h.round = next
            h.status = .generating
            h.statusMessage = ""
        }
        store.notify()
        store.later(1.5) { [weak store = self.store] in
            guard let store = store, store.hangouts[hangoutId]?.status == .generating else { return }
            let newCards: [HangoutCard] = store.generateCards(hangoutId: hangoutId, round: next)
            store.cards[hangoutId, default: []].append(contentsOf: newCards)
            store.updateHangout(hangoutId) { $0.status = .votingCards }
            store.notify()
        }
    }

    func geocode(_ text: String) async throws -> Location {
        try await Task.sleep(nanoseconds: 250_000_000)
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly: Bool = !trimmed.isEmpty && trimmed.allSatisfy { $0.isNumber }
        if trimmed.count < 3 || digitsOnly {
            throw MockServiceError("Enter a neighborhood, cross streets or an address (a zip code alone isn't enough).")
        }
        // Deterministic jitter around San Antonio so different inputs land in different spots.
        let sum: Int = trimmed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let lat: Double = 29.42 + Double(sum % 100) / 1000.0
        let lng: Double = -98.49 - Double((sum / 100) % 100) / 1000.0
        return Location(text: trimmed, lat: lat, lng: lng)
    }
}

extension MockStore {
    /// Demo mode: fetches the real venues, addresses and photos for the demo cards from
    /// Google Places via the `demoVenues` Cloud Function (functions/src/demo.ts). Needs
    /// GoogleService-Info.plist and a network connection; otherwise the cards keep their
    /// fallback names and category-colored backgrounds.
    func loadDemoVenues() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Eklendi] Demo venues: GoogleService-Info.plist isn't in the app bundle, so no Places photos. Put it in the repo root and run xcodegen generate.")
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Task { @MainActor [weak self] in
            do {
                let result: HTTPSCallableResult = try await Functions.functions().httpsCallable("demoVenues").call()
                guard let dict = result.data as? [String: Any],
                      let raw = dict["venues"] as? [String: Any] else {
                    print("[Eklendi] Demo venues: unexpected response from demoVenues: \(String(describing: result.data))")
                    return
                }
                var venues: [String: MockStore.DemoVenue] = [:]
                for (id, value) in raw {
                    guard let v = value as? [String: Any],
                          let name = v["venueName"] as? String,
                          let lat = (v["lat"] as? NSNumber)?.doubleValue,
                          let lng = (v["lng"] as? NSNumber)?.doubleValue else { continue }
                    venues[id] = MockStore.DemoVenue(name: name,
                                                     address: (v["address"] as? String) ?? "",
                                                     lat: lat, lng: lng,
                                                     photoUrl: v["photoUrl"] as? String,
                                                     placeId: (v["placeId"] as? String) ?? "")
                }
                let withPhotos: Int = venues.values.filter { $0.photoUrl != nil }.count
                print("[Eklendi] Demo venues: \(venues.count) of \(MockStore.cardPool.count) found, \(withPhotos) with photos.")
                self?.applyDemoVenues(venues)
            } catch {
                let ns = error as NSError
                // NOT FOUND = demoVenues isn't deployed yet; INTERNAL/UNAVAILABLE = Places failed (see the function logs).
                print("[Eklendi] Demo venues unavailable: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            }
        }
    }
}
