import Foundation
import QuillModel
import Testing
@testable import QuillFeatures

@MainActor
@Suite("Schnell öffnen: Abschnitte und Auswahl")
struct QuickOpenModelTests {
    let store: PageStore

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
    }

    private func page(_ title: String, text: String? = nil) async throws {
        let id = try await store.createPage(title: title)
        guard let text else { return }
        let block = BlockSnapshot(id: UUID(), kindRaw: BlockKind.paragraph.rawValue, text: text, properties: BlockProperties())
        try await store.applyEdits(id, BlockEdits(upserts: [block], order: [block.id]))
    }

    @Test func emptyQueryShowsRecentPages() async throws {
        try await page("Alt")
        try await page("Neu")
        let model = QuickOpenModel()
        await model.load(from: store, debounce: .zero)
        #expect(model.sections.map(\.kind) == [.recent])
        #expect(model.hits.map(\.title) == ["Neu", "Alt"])
    }

    @Test func searchSplitsPagesAndContentAndClampsSelection() async throws {
        try await page("Reiseplan")
        try await page("Inbox", text: "Die Reise nach Lissabon")
        try await page("Sonstiges")
        let model = QuickOpenModel()
        model.query = "  reise "
        await model.load(from: store, debounce: .zero)
        #expect(model.sections.map(\.kind) == [.pages, .content])
        #expect(model.hits.map(\.title) == ["Reiseplan", "Inbox"])
        #expect(model.selectedHit?.title == "Reiseplan")

        model.moveSelection(by: 1)
        #expect(model.selectedHit?.title == "Inbox")
        model.moveSelection(by: 5)
        #expect(model.selection == 1)
        model.moveSelection(by: -9)
        #expect(model.selection == 0)

        model.query = "nichts davon"
        await model.load(from: store, debounce: .zero)
        #expect(model.sections.isEmpty && model.hasLoaded)
        #expect(model.selectedHit == nil)
    }

    @Test func staleResultsAreDropped() async throws {
        try await page("Reiseplan")
        let model = QuickOpenModel()
        model.query = "reise"
        let loading = Task { await model.load(from: store, debounce: .milliseconds(50)) }
        await Task.yield()
        // Weitergetippt, bevor die Suche fertig ist: Das alte Ergebnis bleibt aus.
        model.query = "reisepläne"
        await loading.value
        #expect(!model.hasLoaded)
        #expect(model.hits.isEmpty)
    }
}
