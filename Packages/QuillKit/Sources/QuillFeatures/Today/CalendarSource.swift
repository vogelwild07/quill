import EventKit
import Foundation

/// Ein Termin, nur was Quill einfügt (15.5, ADR-033).
struct CalendarEvent: Equatable, Sendable {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// Kalender, aus dem Quill liest: der des Macs oder ein Ersatz für Test-Stores und Tests.
protocol CalendarSource: Sendable {
    /// Fragt beim ersten Mal nach dem Zugriff; `false`, wenn er fehlt.
    func requestAccess() async throws -> Bool
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
}

/// Kalender des Macs, nur für den echten Store; nur gelesen.
actor SystemCalendarSource: CalendarSource {
    /// Erst beim ersten Klick, nie beim Start.
    private lazy var store = EKEventStore()

    func requestAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .notDetermined: return try await store.requestFullAccessToEvents()
        case .denied, .restricted, .writeOnly: return false
        @unknown default: return false
        }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEvent(title: event.title ?? "", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay)
        }
    }
}

/// Ersatz im Speicher: Test-Stores lesen nie den Kalender des Macs, denn Debug-Builds
/// haben dieselbe Kennung wie die echte App.
actor MemoryCalendarSource: CalendarSource {
    private let allEvents: [CalendarEvent]
    private let allowed: Bool
    /// Wie oft nach dem Zugriff gefragt wurde.
    private(set) var accessRequests = 0

    init(events: [CalendarEvent] = [], allowed: Bool = true) {
        allEvents = events
        self.allowed = allowed
    }

    #if DEBUG || QUILL_SYNCTEST
    /// Zwei feste Termine des Tages für Test-Stores (UI-Tests), nur im Debug-Build.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> MemoryCalendarSource {
        let day = calendar.startOfDay(for: now)
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let ten = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return MemoryCalendarSource(events: [
            CalendarEvent(title: "Zahnarzt", start: nine, end: ten, isAllDay: false),
            CalendarEvent(title: "Geburtstag", start: day, end: tomorrow, isAllDay: true),
        ])
    }
    #endif

    func requestAccess() -> Bool {
        accessRequests += 1
        return allowed
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        allEvents.filter { $0.start < end && $0.end > start }
    }
}
