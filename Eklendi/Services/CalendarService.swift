import Foundation
import EventKit

enum CalendarServiceError: LocalizedError {
    case notAuthorized
    case noDefaultCalendar

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Eklendi needs calendar access. Turn it on in Settings > Privacy > Calendars."
        case .noDefaultCalendar: return "No calendar is available to add the hangout to."
        }
    }
}

/// Apple Calendar via EventKit (iOS 17 full access). Reads busy blocks only (never titles/details)
/// and writes the confirmed hangout into the user's default calendar.
@MainActor
final class CalendarService: CalendarServicing {
    private var store = EKEventStore()

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async throws -> Bool {
        if isAuthorized { return true }
        let granted: Bool = try await store.requestFullAccessToEvents()
        if granted {
            // A store created before access was granted can miss calendars; start fresh.
            store = EKEventStore()
        }
        return granted
    }

    func busyBlocks(from: Date, to: Date) async throws -> [BusyBlock] {
        guard isAuthorized else { throw CalendarServiceError.notAuthorized }
        guard to > from else { return [] }
        let predicate: NSPredicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        let events: [EKEvent] = store.events(matching: predicate)
        var blocks: [BusyBlock] = []
        for event in events {
            if event.isAllDay { continue }
            if event.availability == .free { continue }
            if event.status == .canceled { continue }
            guard let s = event.startDate, let e = event.endDate else { continue }
            let start = max(s, from)
            let end = min(e, to)
            if end > start { blocks.append(BusyBlock(start: start, end: end)) }
        }
        return CalendarService.merge(blocks)
    }

    /// Sorts and merges overlapping/adjacent blocks.
    nonisolated static func merge(_ blocks: [BusyBlock]) -> [BusyBlock] {
        let sorted = blocks.sorted { $0.start < $1.start }
        var out: [BusyBlock] = []
        for block in sorted {
            if let last = out.last, block.start <= last.end {
                out[out.count - 1].end = max(last.end, block.end)
            } else {
                out.append(block)
            }
        }
        return out
    }

    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> String {
        guard isAuthorized else { throw CalendarServiceError.notAuthorized }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarServiceError.noDefaultCalendar }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? ""
    }

    func removeEvent(identifier: String) async throws {
        guard isAuthorized else { throw CalendarServiceError.notAuthorized }
        guard !identifier.isEmpty, let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }
}
