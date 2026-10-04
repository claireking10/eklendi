import Foundation

/// Pretend EventKit: access is granted on request, busy blocks are a few realistic
/// recurring commitments, and added events are kept in memory.
@MainActor
final class MockCalendarService: CalendarServicing {
    private(set) var isAuthorized: Bool
    private(set) var events: [String: (title: String, start: Date, end: Date, location: String?)] = [:]

    init() {
        // Signed-in UI tests / previews behave as if the calendar was connected at sign-up.
        let args: [String] = ProcessInfo.processInfo.arguments
        isAuthorized = !args.contains("-uiTesting") || args.contains("-uiTestingSignedIn")
    }

    func requestAccess() async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        isAuthorized = true
        return true
    }

    func busyBlocks(from: Date, to: Date) async throws -> [BusyBlock] {
        guard isAuthorized else { throw MockServiceError("Calendar access is off. Turn it on in Settings.") }
        let cal = Calendar.current
        var blocks: [BusyBlock] = []
        var day: Date = cal.startOfDay(for: from)
        while day < to {
            let weekday: Int = cal.component(.weekday, from: day)   // 1 = Sunday
            func at(_ h: Int, _ m: Int) -> Date {
                cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            }
            if weekday >= 2 && weekday <= 6 {
                blocks.append(BusyBlock(start: at(9, 0), end: at(12, 0)))      // class / work
                blocks.append(BusyBlock(start: at(13, 0), end: at(14, 45)))
                if weekday == 3 || weekday == 5 {
                    blocks.append(BusyBlock(start: at(17, 0), end: at(18, 15)))  // lab
                }
            } else if weekday == 7 {
                blocks.append(BusyBlock(start: at(14, 30), end: at(16, 0)))
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? to
        }
        return blocks.filter { $0.end > from && $0.start < to }
    }

    func addEvent(title: String, start: Date, end: Date, location: String?) async throws -> String {
        let id: String = "mock-event-\(UUID().uuidString)"
        events[id] = (title: title, start: start, end: end, location: location)
        return id
    }

    func removeEvent(identifier: String) async throws {
        events[identifier] = nil
    }
}
