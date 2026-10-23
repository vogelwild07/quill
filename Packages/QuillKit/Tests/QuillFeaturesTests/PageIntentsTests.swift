import AppIntents
import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Die Aktionen selbst, ohne das System (15.1, ADR-033): Über Kurzbefehle erreicht ein
/// Test nur die App, die das System für diese Kennung kennt, nicht die Test-Instanz.
@Suite("Kurzbefehle: Aktionen", .serialized)
@MainActor
struct PageIntentsTests {
    let store: PageStore

    init() throws {
        store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        PageIntentStore.store = store
    }

    @Test func newPageWithTitleAndText() async throws {
        var intent = NewPageIntent()
        intent.pageTitle = "Aus dem Kurzbefehl"
        intent.text = "Erste Zeile\nZweite Zeile"
        _ = try await intent.perform()

        let hit = try #require(try await store.search("Aus dem Kurzbefehl").first)
        #expect(try await store.blocks(of: hit.pageID).map(\.text) == ["Erste Zeile", "Zweite Zeile"])
    }

    @Test func addToPageContinuesTheList() async throws {
        let id = try await store.createPage(title: "Einkaufsliste")
        let first = BlockSnapshot(id: UUID(), kindRaw: BlockKind.todo.rawValue, text: "Brot")
        try await store.applyEdits(id, BlockEdits(upserts: [first], order: [first.id]))

        var intent = AddToPageIntent()
        intent.page = PageEntity(.init(id: id, title: "Einkaufsliste"))
        intent.text = "Milch"
        _ = try await intent.perform()
        #expect(try await store.blocks(of: id).map { "\($0.kindRaw): \($0.text)" } == ["todo: Brot", "todo: Milch"])
    }

    @Test func pagesFoundByTitle() async throws {
        let id = try await store.createPage(title: "Einkaufsliste")
        try await store.createPage(title: "Rezepte")
        let found = try await PageQuery().entities(matching: "einkauf")
        #expect(found.map(\.id) == [id])
        #expect(found.first?.title == "Einkaufsliste")
        #expect(try await PageQuery().entities(for: [id]).map(\.id) == [id])
        #expect(Set(try await PageQuery().suggestedEntities().map(\.title)) == ["Einkaufsliste", "Rezepte"])
    }

    @Test func withoutStoreTheActionsSayQuillIsNotReady() async throws {
        PageIntentStore.store = nil
        await #expect(throws: PageIntentError.self) { _ = try await NewPageIntent().perform() }
        await #expect(throws: PageIntentError.self) { _ = try await PageQuery().suggestedEntities() }
    }
}
