import Foundation
import QuillModel
@testable import QuillSync
import Testing

/// Stand am Ende eines Tages (12.2, ADR-031). Feste Zeiten und fester Kalender.
@Suite("Zeitreise: Tagesstände")
struct PageHistoryTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private static func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func write(_ document: PageDocument, _ blocks: [BlockSnapshot], at time: Date) throws {
        document.clock = { time }
        try document.update(to: blocks)
    }

    @Test func eachDayShowsItsLastState() throws {
        let document = PageDocument()
        let block = UUID()
        try write(document, [BlockSnapshot(id: block, text: "Morgens")], at: Self.time(20, 9))
        try write(document, [BlockSnapshot(id: block, text: "Abends")], at: Self.time(20, 23, 59))
        try write(document, [BlockSnapshot(id: block, text: "Neuer Tag")], at: Self.time(21, 0, 1))
        try write(document, [BlockSnapshot(id: block, text: "Zwei Tage später")], at: Self.time(23, 12))

        let history = try PageHistory(pageID: UUID(), document: document.save(), calendar: Self.calendar)
        #expect(history.days.map(\.day) == [Self.time(20, 0), Self.time(21, 0), Self.time(23, 0)])
        #expect(try history.days.map { try history.blocks(on: $0).map(\.text) } == [["Abends"], ["Neuer Tag"], ["Zwei Tage später"]])
    }

    @Test func dayBoundaryFollowsTheCalendar() throws {
        // 23:30 in Berlin ist in UTC noch derselbe Tag, 0:30 in Berlin schon der nächste,
        // in UTC aber der Vortag.
        let document = PageDocument()
        let block = UUID()
        try write(document, [BlockSnapshot(id: block, text: "Spät")], at: Self.time(20, 23, 30))
        try write(document, [BlockSnapshot(id: block, text: "Nach Mitternacht")], at: Self.time(21, 0, 30))
        let berlin = try PageHistory(pageID: UUID(), document: document.save(), calendar: Self.calendar)
        #expect(berlin.days.count == 2)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let inUTC = try PageHistory(pageID: UUID(), document: document.save(), calendar: utc)
        #expect(try inUTC.days.map { try inUTC.blocks(on: $0).map(\.text) } == [["Nach Mitternacht"]])
    }

    @Test func pageWithoutDocumentHasNoDays() throws {
        let history = try PageHistory(pageID: UUID(), document: nil)
        #expect(history.days.isEmpty)
        #expect(try PageHistory(pageID: UUID(), document: PageDocument().save()).days.isEmpty)
    }

    @Test func dayContainsEverythingItsChangesBuildOn() throws {
        // Gerät B geht einen Tag vor: Seine Änderung baut auf A vom 21. auf, trägt aber
        // den 22. Am 21. abends bearbeitet A weiter, ohne B zu kennen. Am 21. steht also
        // nur A; der 22. enthält beides.
        let a = PageDocument(), b = PageDocument()
        let first = UUID(), second = UUID()
        try write(a, [BlockSnapshot(id: first, text: "A")], at: Self.time(21, 10))
        try b.apply(changes: a.save())
        try write(b, [BlockSnapshot(id: first, text: "A"), BlockSnapshot(id: second, text: "B")], at: Self.time(22, 10))
        try write(a, [BlockSnapshot(id: first, text: "A2")], at: Self.time(21, 20))
        try a.apply(changes: b.save())

        let history = try PageHistory(pageID: UUID(), document: a.save(), calendar: Self.calendar)
        #expect(try history.days.map { try history.blocks(on: $0).map(\.text) } == [["A2"], ["A2", "B"]])

        // Uhr von B geht nach: Seine Änderung trägt den 20., baut aber auf dem 21. auf.
        // Der Stand des 20. enthält dann auch A vom 21., der 21. bringt nichts Neues.
        let c = PageDocument()
        try write(c, [BlockSnapshot(id: first, text: "A")], at: Self.time(21, 10))
        try write(c, [BlockSnapshot(id: first, text: "A"), BlockSnapshot(id: second, text: "B")], at: Self.time(20, 10))
        let skewed = try PageHistory(pageID: UUID(), document: c.save(), calendar: Self.calendar)
        #expect(skewed.days.map(\.day) == [Self.time(20, 0)])
        #expect(try skewed.blocks(on: skewed.days[0]).map(\.text) == ["A", "B"])

        // Kette über drei Tage, rückwärts datiert: Der 20. baut auf dem 22. auf, der auf
        // dem 21. Der 20. enthält alles; der 21. und der 22. sind kein neuer Stand.
        let chain = PageDocument()
        try write(chain, [BlockSnapshot(id: first, text: "1")], at: Self.time(21, 10))
        try write(chain, [BlockSnapshot(id: first, text: "2")], at: Self.time(22, 10))
        try write(chain, [BlockSnapshot(id: first, text: "3")], at: Self.time(20, 10))
        let backwards = try PageHistory(pageID: UUID(), document: chain.save(), calendar: Self.calendar)
        #expect(backwards.days.map(\.day) == [Self.time(20, 0)])
    }

    @Test func loadsRecordedHistoryFromTheStore() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let page = try await store.createPage(title: "Notiz")
        let block = UUID()
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: "Heute")], order: [block]))
        #expect(try await HistoryRecorder(store: store).record(page))
        let history = try await PageHistory.load(page, from: store)
        #expect(history.days.map(\.day) == [Calendar.current.startOfDay(for: Date())])
        #expect(try history.blocks(on: history.days[0]).map(\.text) == ["Heute"])
    }
}
