import Foundation
import QuillEditor
import QuillEditorCore
import QuillExport
@testable import QuillModel
import SwiftData
import Testing

/// Bestand für die Messungen am Store: 1000 Seiten mit je 50 Blöcken als Baum unter
/// einer Wurzel (zehn Kinder pro Seite), dazu eine Seite mit 1000 Blöcken.
private struct LargeStore {
    let container: ModelContainer
    let store: PageStore
    let rootID: UUID
    let longPageID: UUID

    static let words = ["Apfel", "Birne", "Reise", "Projekt", "Notiz", "Woche", "Termin", "Idee", "Liste", "Garten"]

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let words = Self.words
        var pages: [Page] = []
        for pageIndex in 0..<1000 {
            let page = Page(title: "\(words[pageIndex % words.count]) \(pageIndex)")
            page.sortKey = String(format: "a%04d", pageIndex)
            context.insert(page)
            if pageIndex > 0 { page.parent = pages[(pageIndex - 1) / 10] }
            pages.append(page)
            for blockIndex in 0..<50 {
                let block = Block(text: "Absatz \(blockIndex) über \(words[(pageIndex + blockIndex) % words.count]) und anderes, Seite \(pageIndex).")
                block.sortKey = String(format: "a%03d", blockIndex)
                context.insert(block)
                block.page = page
            }
        }
        let long = Page(title: "Lang")
        context.insert(long)
        for blockIndex in 0..<1000 {
            let block = Block(text: "Zeile \(blockIndex) mit etwas Text, damit es nach einem Absatz aussieht.")
            block.sortKey = String(format: "a%04d", blockIndex)
            context.insert(block)
            block.page = long
        }
        try context.save()
        store = PageStore(modelContainer: container)
        rootID = pages[0].id
        longPageID = long.id
    }
}

extension PerformanceSuites {
    @Suite("Store")
    struct Store {
        private let clock = ContinuousClock()

        /// Suche: p95 von 20 Anfragen (Produktziel < 100 ms, ADR-017).
        @Test func search() async throws {
            let large = try LargeStore()
            let queries = ["reise", "garten 9", "termin", "absatz 49", "xyz", "über", "idee", "apfel 12", "notiz", "woche"]
                + Array(repeating: "projekt", count: 10)
            let values = try await Performance.repeated {
                var samples: [Double] = []
                for query in queries {
                    samples.append(Performance.milliseconds(try await clock.measure { _ = try await large.store.search(query) }))
                }
                return Performance.p95(samples)
            }
            Performance.report("search", runs: values)
        }

        /// Einen Block in einer Seite mit 1000 Blöcken verschieben (Ziehen): p95 von 20.
        @Test func applyEditsMove() async throws {
            let large = try LargeStore()
            var order = try await large.store.blocks(of: large.longPageID).map(\.id)
            var generator = SystemRandomNumberGenerator()
            let values = try await Performance.repeated {
                var samples: [Double] = []
                for _ in 0..<20 {
                    let moved = order.remove(at: Int.random(in: 0..<order.count, using: &generator))
                    order.insert(moved, at: Int.random(in: 0...order.count, using: &generator))
                    let edits = BlockEdits(order: order)
                    samples.append(Performance.milliseconds(try await clock.measure { try await large.store.applyEdits(large.longPageID, edits) }))
                }
                return Performance.p95(samples)
            }
            Performance.report("applyEditsMove", runs: values)
        }

        /// Alle 1000 Blöcke umkehren (schlechtester Fall der Reihenfolge).
        @Test func applyEditsReverse() async throws {
            let large = try LargeStore()
            var order = try await large.store.blocks(of: large.longPageID).map(\.id)
            let values = try await Performance.repeated {
                order.reverse()
                let edits = BlockEdits(order: order)
                return Performance.milliseconds(try await clock.measure { try await large.store.applyEdits(large.longPageID, edits) })
            }
            Performance.report("applyEditsReverse", runs: values)
        }

        /// Seite mit 1000 Blöcken laden wie beim Öffnen: p95 von 10.
        @MainActor
        @Test func bridgeLoad() async throws {
            let large = try LargeStore()
            let values = try await Performance.repeated {
                var samples: [Double] = []
                for _ in 0..<10 {
                    let bridge = EditorPersistenceBridge(pageID: large.longPageID, store: large.store)
                    samples.append(Performance.milliseconds(try await clock.measure { _ = try await bridge.load() }))
                }
                return Performance.p95(samples)
            }
            Performance.report("bridgeLoad", runs: values)
        }

        /// Export von 1000 Seiten: lesen und Markdown planen, ohne Schreiben.
        @Test func exportPlan() async throws {
            let large = try LargeStore()
            let strings = ExportStrings(untitled: "Ohne Titel", subpages: "Unterseiten", missingImage: "Bild fehlt")
            let values = try await Performance.repeated {
                let start = ContinuousClock.now
                let snapshot = try await large.store.exportSnapshot(of: large.rootID, includeSubpages: true)
                let plan = MarkdownExporter.plan(for: snapshot, strings: strings)
                let elapsed = Performance.milliseconds(ContinuousClock.now - start)
                #expect(plan.pageCount == 1000)
                return elapsed
            }
            Performance.report("exportPlan", runs: values)
        }
    }
}
