import Foundation
import FirebaseFirestore

/// Shared Firestore helpers for the Firebase* services.
enum FirestoreSupport {
    static var db: Firestore { Firestore.firestore() }

    /// Decodes a document with FirebaseFirestore's Codable support after filling in
    /// defaults for missing non-optional fields (synthesized Decodable ignores property
    /// defaults, so a field another writer left out would otherwise fail the whole decode).
    /// Sets nothing about the id; callers assign `.id = documentID`.
    static func decode<T: Decodable>(_ type: T.Type, data: [String: Any]?, defaults: [String: Any]) -> T? {
        guard let data = data else { return nil }
        var filled: [String: Any] = data
        for (key, value) in defaults {
            if filled[key] == nil || filled[key] is NSNull {
                filled[key] = value
            }
        }
        do {
            return try Firestore.Decoder().decode(T.self, from: filled)
        } catch {
            print("[Firestore] decode \(T.self) failed: \(error)")
            return nil
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        return try Firestore.Encoder().encode(value)
    }

    /// Runs `block` on the main thread (Firestore delivers on main by default; this is a safety net).
    static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async { block() }
        }
    }

    static func locationData(_ location: Location) -> [String: Any] {
        return ["text": location.text, "lat": location.lat, "lng": location.lng]
    }

    // MARK: Defaults for documents written by other code (Cloud Functions)

    static var profileDefaults: [String: Any] {
        ["phone": "", "name": "", "bufferMinutes": 15, "interests": "", "calendarConnected": false,
         "friendIds": [String](), "createdAt": Timestamp(date: Date())]
    }

    static var hangoutDefaults: [String: Any] {
        ["ownerId": "", "title": "", "mode": HangoutMode.timeAndActivity.rawValue, "planDescription": "",
         "durationsMinutes": [Int](), "durationAny": false, "memberIds": [String](),
         "status": HangoutStatus.collectingAvailability.rawValue, "horizonDays": 14, "round": 1,
         "statusMessage": "", "createdAt": Timestamp(date: Date()), "updatedAt": Timestamp(date: Date())]
    }

    static var memberDefaults: [String: Any] {
        ["name": "", "role": MemberRole.member.rawValue, "state": MemberState.invited.rawValue,
         "availabilitySubmitted": false, "busy": [[String: Any]](), "bufferMinutes": 15,
         "timesDone": false, "surveyDone": false, "cardsDoneRound": 0, "notGoing": false]
    }

    static var slotDefaults: [String: Any] {
        ["source": SlotSource.computed.rawValue, "missingMemberIds": [String](), "rank": 0, "label": "", "reason": ""]
    }

    static var cardDefaults: [String: Any] {
        ["round": 1, "activity": "", "description": "", "category": "", "venueName": "", "address": "",
         "lat": 0.0, "lng": 0.0, "placeId": "", "tags": [String]()]
    }
}

/// Readable errors for Firebase-backed services.
enum EklendiServiceError: LocalizedError {
    case notSignedIn
    case notFound(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're signed out. Please log in again."
        case .notFound(let what): return "\(what) couldn't be found."
        case .message(let text): return text
        }
    }
}
