import Foundation
import QuillModel
@testable import QuillSync
import Testing

/// Seite mit 100 Blöcken, ein Jahr lang an jedem Tag dreimal aufgezeichnet (ADR-031).
private struct YearOfHistory {
    let bytes: Data

    init() throws {
        let document = PageDocument()
        var blocks = (0..<100).map { BlockSnapshot(id: UUID(), text: "Absatz \($0) mit etwas Text, damit es nach einem Absatz aussieht.") }
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        for day in 0..<365 {
            for edit in 0..<3 {
                let index = (day * 7 + edit * 31) % blocks.count
                blocks[index].text += " Tag \(day), Änderung \(edit)."
                let time = start.addingTimeInterval(Double(day) * 86_400 + Double(edit) * 3_600)
                document.clock = { time }
                try document.update(to: blocks)
            }
        }
        bytes = document.save()
    }
}

extension PerformanceSuites {
    @Suite("Zeitreise")
    struct History {
        private let clock = ContinuousClock()

        /// Tage einer Seite mit einem Jahr Geschichte bilden, samt Laden des Dokuments.
        @Test func historyDays() throws {
            let year = try YearOfHistory()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
            var days = 0
            let values = try Performance.repeated {
                Performance.milliseconds(try clock.measure {
                    days = try PageHistory(pageID: UUID(), document: year.bytes, calendar: calendar).days.count
                })
            }
            #expect(days == 365)
            Performance.report("historyDays", runs: values)
        }

        /// Blöcke eines Tages in der Mitte des Jahres lesen.
        @Test func historyDayBlocks() throws {
            let year = try YearOfHistory()
            let history = try PageHistory(pageID: UUID(), document: year.bytes)
            let day = history.days[history.days.count / 2]
            var count = 0
            let values = try Performance.repeated {
                Performance.milliseconds(try clock.measure { count = try history.blocks(on: day).count })
            }
            #expect(count == 100)
            Performance.report("historyDayBlocks", runs: values)
        }
    }
}
