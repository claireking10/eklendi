import Foundation

// Codable mirrors of the Firestore data model in docs/ARCHITECTURE.md.
// Field names must match Firestore exactly. Dates map to Firestore Timestamps
// (FirebaseFirestore encodes/decodes `Date` as Timestamp).

struct Location: Codable, Hashable, Sendable {
    var text: String
    var lat: Double
    var lng: Double
}

struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    var id: String              // uid (document id, not stored as a field)
    var phone: String
    var name: String
    var photoURL: String?
    var homeLocation: Location?
    var bufferMinutes: Int = 15
    var interests: String = ""
    var calendarConnected: Bool = false
    var friendIds: [String] = []
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case phone, name, photoURL, homeLocation, bufferMinutes, interests, calendarConnected, friendIds, createdAt
    }

    init(id: String, phone: String, name: String, photoURL: String? = nil, homeLocation: Location? = nil,
         bufferMinutes: Int = 15, interests: String = "", calendarConnected: Bool = false,
         friendIds: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.phone = phone; self.name = name; self.photoURL = photoURL
        self.homeLocation = homeLocation; self.bufferMinutes = bufferMinutes; self.interests = interests
        self.calendarConnected = calendarConnected; self.friendIds = friendIds; self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        photoURL = try c.decodeIfPresent(String.self, forKey: .photoURL)
        homeLocation = try c.decodeIfPresent(Location.self, forKey: .homeLocation)
        bufferMinutes = try c.decodeIfPresent(Int.self, forKey: .bufferMinutes) ?? 15
        interests = try c.decodeIfPresent(String.self, forKey: .interests) ?? ""
        calendarConnected = try c.decodeIfPresent(Bool.self, forKey: .calendarConnected) ?? false
        friendIds = try c.decodeIfPresent([String].self, forKey: .friendIds) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

enum HangoutMode: String, Codable, Sendable { case timeAndActivity, timeOnly }

enum HangoutStatus: String, Codable, Sendable {
    case collectingAvailability, votingTimes, noMutualTime, survey, generating,
         votingCards, noAgreement, confirmed, cancelled
}

enum MemberRole: String, Codable, Sendable { case owner, member }
enum MemberState: String, Codable, Sendable { case invited, active, declined, removed }

/// Three-way swipe. Right = yes, down = maybe, left = no.
enum Vote: String, Codable, Sendable, CaseIterable { case yes, maybe, no }

/// Survey answers add the neutral "I don't care".
enum SurveyAnswer: String, Codable, Sendable { case yes, maybe, no, dontCare }

struct SlotRef: Codable, Hashable, Sendable {
    var id: String
    var start: Date
    var end: Date
}

struct ConfirmedPlan: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
    var activity: String
    var venueName: String
    var address: String
    var cardId: String?
}

struct Hangout: Codable, Identifiable, Hashable, Sendable {
    var id: String = ""                // document id
    var ownerId: String
    var title: String = ""
    var mode: HangoutMode
    var planDescription: String = ""
    var durationsMinutes: [Int]
    var durationAny: Bool = false
    var memberIds: [String]
    var status: HangoutStatus = .collectingAvailability
    var horizonDays: Int = 14
    var round: Int = 1
    var winningSlot: SlotRef?
    var confirmed: ConfirmedPlan?
    var statusMessage: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case ownerId, title, mode, planDescription, durationsMinutes, durationAny, memberIds, status,
             horizonDays, round, winningSlot, confirmed, statusMessage, createdAt, updatedAt
    }
}

struct BusyBlock: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
}

struct HangoutMember: Codable, Identifiable, Hashable, Sendable {
    var id: String = ""                // uid (document id)
    var name: String
    var role: MemberRole
    var state: MemberState
    var availabilitySubmitted: Bool = false
    var busy: [BusyBlock] = []
    var bufferMinutes: Int = 15
    var startLocation: Location?
    var timesDone: Bool = false
    var surveyDone: Bool = false
    var cardsDoneRound: Int = 0
    var notGoing: Bool = false
    var nudgedAt: Date?
    var timeZone: String?

    enum CodingKeys: String, CodingKey {
        case name, role, state, availabilitySubmitted, busy, bufferMinutes, startLocation,
             timesDone, surveyDone, cardsDoneRound, notGoing, nudgedAt, timeZone
    }

    var isParticipating: Bool { state == .active }
}

enum SlotSource: String, Codable, Sendable { case computed, suggested, fallback }

struct TimeSlot: Codable, Identifiable, Hashable, Sendable {
    var id: String = ""                // document id
    var start: Date
    var end: Date
    var source: SlotSource
    var suggestedBy: String?
    var missingMemberIds: [String] = []
    var rank: Int = 0
    var label: String = ""
    var reason: String = ""

    enum CodingKeys: String, CodingKey {
        case start, end, source, suggestedBy, missingMemberIds, rank, label, reason
    }
}

struct HangoutCard: Codable, Identifiable, Hashable, Sendable {
    var id: String = ""                // document id
    var round: Int
    var activity: String
    var description: String
    var category: String = ""
    var venueName: String
    var address: String
    var lat: Double
    var lng: Double
    var distanceMiles: Double?
    var priceLevel: Int?
    var photoUrl: String?
    var placeId: String = ""
    var start: Date
    var end: Date
    var tags: [String] = []

    enum CodingKeys: String, CodingKey {
        case round, activity, description, category, venueName, address, lat, lng, distanceMiles,
             priceLevel, photoUrl, placeId, start, end, tags
    }
}

/// The fixed activity survey (same for everyone). Ids match functions/src/types.ts.
struct SurveyQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let category: String   // "Type" | "Setting" | "Price" | "Vibe"
    let question: String
    let subtitle: String
    let examples: String

    static let all: [SurveyQuestion] = [
        .init(id: "food", category: "Type", question: "Food & drink?", subtitle: "Restaurants, cafés, dessert spots.", examples: "Tacos, brunch, bubble tea"),
        .init(id: "active", category: "Type", question: "Something active?", subtitle: "Get moving a little.", examples: "Bowling, mini golf, climbing"),
        .init(id: "games", category: "Type", question: "Games?", subtitle: "Play something together.", examples: "Board game café, arcade, trivia"),
        .init(id: "arts", category: "Type", question: "Arts & entertainment?", subtitle: "Watch, listen or look around.", examples: "Movies, live music, museums"),
        .init(id: "nature", category: "Type", question: "Nature?", subtitle: "Parks, trails and open air.", examples: "Picnic, hike, botanical garden"),
        .init(id: "markets", category: "Type", question: "Markets & shopping?", subtitle: "Wander and browse.", examples: "Farmers market, thrift stores"),
        .init(id: "events", category: "Type", question: "Events?", subtitle: "Something happening that day.", examples: "Festivals, shows, pop-ups"),
        .init(id: "indoors", category: "Setting", question: "Indoors?", subtitle: "Inside, whatever the weather.", examples: "Cafés, theaters, game rooms"),
        .init(id: "outdoors", category: "Setting", question: "Outdoors?", subtitle: "Out in the open air.", examples: "Patios, parks, open-air markets"),
        .init(id: "priceLow", category: "Price", question: "Free or under $15?", subtitle: "Per person.", examples: "Parks, coffee, markets"),
        .init(id: "priceMid", category: "Price", question: "$15–$30?", subtitle: "Per person.", examples: "Bowling, casual dinner, movies"),
        .init(id: "priceHigh", category: "Price", question: "Over $30?", subtitle: "Per person, for something special.", examples: "Concerts, nicer dinners"),
        .init(id: "chill", category: "Vibe", question: "Chill and low-key?", subtitle: "Easy to talk, nothing loud.", examples: "Quiet café, a walk in the park"),
        .init(id: "lively", category: "Vibe", question: "Lively and busy?", subtitle: "Crowds and energy are fine.", examples: "Food halls, trivia night, arcades"),
    ]
}

/// Duration options for screen 06. Custom is 1–12 hours, default 4.
enum DurationOption: Hashable, Sendable {
    case minutes(Int)
    case custom(hours: Int)
    var totalMinutes: Int {
        switch self {
        case .minutes(let m): return m
        case .custom(let h): return h * 60
        }
    }
    static let presets: [DurationOption] = [.minutes(30), .minutes(60), .minutes(120), .minutes(180)]
}
