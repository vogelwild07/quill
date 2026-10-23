import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Tagesseite und heutige Termine (15.5, ADR-033).
@Suite("Tagesseite und Termine")
struct TodayTests {
    static let locale = Locale(identifier: "de_DE")
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = locale
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func titleIsTheLongDate() {
        #expect(TodayPage.title(for: Self.date(23, 22), locale: Self.locale, calendar: Self.calendar) == "Freitag, 23. Oktober 2026")
    }

    @Test func opensOrCreatesTheDayUnderDays() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let other = try await store.createPage(title: "Notizen")
        let today = TodayPage(store: store)

        let friday = try await today.open(now: Self.date(23, 8), locale: Self.locale, calendar: Self.calendar)
        let days = try #require(try await store.activeChild(titled: "Tage", in: nil))
        #expect(try await store.location(of: days).position == .after(other), "Sammelseite am Ende der obersten Ebene")
        #expect(try await store.activeTitles(of: [friday]) == [friday: "Freitag, 23. Oktober 2026"])
        #expect(try await store.location(of: friday).parentID == days)
        #expect(try await today.open(now: Self.date(23, 23), locale: Self.locale, calendar: Self.calendar) == friday)

        let saturday = try await today.open(now: Self.date(24, 7), locale: Self.locale, calendar: Self.calendar)
        #expect(saturday != friday)
        let location = try await store.location(of: saturday)
        #expect(location.parentID == days && location.position == .first, "Neuester Tag zuerst")

        try await store.trash(saturday)
        let again = try await today.open(now: Self.date(24, 9), locale: Self.locale, calendar: Self.calendar)
        #expect(again != saturday, "Tagesseite im Papierkorb zählt nicht")
        #expect(try await store.activeChild(titled: "Tage", in: nil) == days)
    }

    @Test func eventsBecomeSortedLines() async {
        let source = MemoryCalendarSource(events: [
            CalendarEvent(title: "Zahnarzt", start: Self.date(23, 9), end: Self.date(23, 10), isAllDay: false),
            CalendarEvent(title: "", start: Self.date(23, 7, 30), end: Self.date(23, 8), isAllDay: false),
            CalendarEvent(title: "Nachtzug", start: Self.date(22, 22), end: Self.date(23, 6, 15), isAllDay: false),
            CalendarEvent(title: "Party", start: Self.date(23, 21), end: Self.date(24, 2), isAllDay: false),
            CalendarEvent(title: "Geburtstag", start: Self.date(23), end: Self.date(24), isAllDay: true),
            CalendarEvent(title: "Messe", start: Self.date(22, 9), end: Self.date(25, 18), isAllDay: false),
            CalendarEvent(title: "Gestern", start: Self.date(22, 9), end: Self.date(22, 10), isAllDay: false),
            CalendarEvent(title: "Morgen", start: Self.date(24), end: Self.date(25), isAllDay: true),
        ])
        let outcome = await TodayEvents(source: source).lines(now: Self.date(23, 12), locale: Self.locale, calendar: Self.calendar)
        #expect(outcome == .lines([
            "Ganztägig: Messe", "Ganztägig: Geburtstag", "bis 6:15 Nachtzug", "7:30–8:00 Termin",
            "9:00–10:00 Zahnarzt", "ab 21:00 Party",
        ]))
    }

    @Test func asksOnlyWhenCalledAndExplainsDenialAndEmptiness() async {
        let denied = MemoryCalendarSource(events: [
            CalendarEvent(title: "Zahnarzt", start: Self.date(23, 9), end: Self.date(23, 10), isAllDay: false),
        ], allowed: false)
        #expect(await denied.accessRequests == 0)
        #expect(await TodayEvents(source: denied).lines(now: Self.date(23, 12), calendar: Self.calendar) == .denied)
        #expect(await denied.accessRequests == 1)

        let empty = MemoryCalendarSource()
        #expect(await TodayEvents(source: empty).lines(now: Self.date(23, 12), calendar: Self.calendar) == .empty)
    }

    @MainActor
    @Test func testStoresReadOnlyTheSampleCalendar() async throws {
        let persistence = QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        #expect(persistence.isTestStore)
        let source = try #require(persistence.calendar as? MemoryCalendarSource)
        guard case .lines(let lines) = await TodayEvents(source: source).lines() else {
            Issue.record("Keine Termine im Ersatz")
            return
        }
        #expect(lines.count == 2)
    }
}
