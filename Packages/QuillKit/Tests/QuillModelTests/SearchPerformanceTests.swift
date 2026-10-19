import Foundation
import SwiftData
import Testing
@testable import QuillModel

/// Suche bei 1000 Seiten mit je 50 Blöcken: p95 unter 100 ms (Debug-Build, ADR-017).
@Suite("Navigation: Suche, Performance")
struct SearchPerformanceTests {
    @Test func searchStaysFastWithManyPages() async throws {
        let container = try QuillStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let words = ["Apfel", "Birne", "Reise", "Projekt", "Notiz", "Woche", "Termin", "Idee", "Liste", "Garten"]
        for pageIndex in 0..<1000 {
            let page = Page(title: "\(words[pageIndex % words.count]) \(pageIndex)")
            context.insert(page)
            for blockIndex in 0..<50 {
                let block = Block(text: "Absatz \(blockIndex) über \(words[(pageIndex + blockIndex) % words.count]) und anderes, Seite \(pageIndex).")
                block.sortKey = String(format: "a%03d", blockIndex)
                context.insert(block)
                block.page = page
            }
        }
        try context.save()
        let store = PageStore(modelContainer: container)

        var durations: [Duration] = []
        let clock = ContinuousClock()
        for query in ["reise", "garten 9", "termin", "absatz 49", "xyz", "über", "idee", "apfel 12", "notiz", "woche"] + Array(repeating: "projekt", count: 10) {
            let duration = try await clock.measure { _ = try await store.search(query) }
            durations.append(duration)
        }
        durations.sort()
        let p95 = durations[Int(Double(durations.count - 1) * 0.95)]
        #expect(p95 < .milliseconds(100), "p95 \(p95)")
    }
}
