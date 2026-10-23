import Foundation

/// „Format › Heutige Termine einfügen“ (15.5, ADR-033): Termine des Tages als Zeilen.
struct TodayEvents: Sendable {
    enum Outcome: Equatable {
        /// Kein Zugriff auf den Kalender.
        case denied
        /// Heute keine Termine.
        case empty
        case lines([String])
    }

    let source: any CalendarSource

    /// Fragt erst hier nach dem Kalender; ganztägige Termine zuerst, dann nach Beginn.
    func lines(now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) async -> Outcome {
        guard (try? await source.requestAccess()) == true else { return .denied }
        let day = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? now
        let events = await source.events(from: day, to: next).sorted { lhs, rhs in
            let lhsAllDay = Self.coversDay(lhs, from: day, to: next)
            let rhsAllDay = Self.coversDay(rhs, from: day, to: next)
            if lhsAllDay != rhsAllDay { return lhsAllDay }
            return (lhs.start, lhs.title) < (rhs.start, rhs.title)
        }
        guard !events.isEmpty else { return .empty }
        return .lines(events.map { Self.line(for: $0, from: day, to: next, locale: locale, calendar: calendar) })
    }

    /// „09:00–10:00 Zahnarzt“; über Mitternacht „bis …“ bzw. „ab …“; über den ganzen Tag „Ganztägig: …“.
    static func line(for event: CalendarEvent, from day: Date, to next: Date, locale: Locale, calendar: Calendar) -> String {
        let title = event.title.isEmpty ? String(localized: "Termin", bundle: .module) : event.title
        if coversDay(event, from: day, to: next) {
            return String(localized: "Ganztägig: \(title)", bundle: .module)
        }
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let start = event.start.formatted(style)
        let end = event.end.formatted(style)
        if event.start < day {
            return String(localized: "bis \(end) \(title)", bundle: .module)
        }
        if event.end > next {
            return String(localized: "ab \(start) \(title)", bundle: .module)
        }
        return String(localized: "\(start)–\(end) \(title)", bundle: .module)
    }

    private static func coversDay(_ event: CalendarEvent, from day: Date, to next: Date) -> Bool {
        event.isAllDay || (event.start <= day && event.end >= next)
    }
}
