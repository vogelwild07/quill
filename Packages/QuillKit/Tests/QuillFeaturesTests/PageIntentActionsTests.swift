import Foundation
@testable import QuillFeatures
import QuillModel
import Testing

/// Kurzbefehle (15.1, ADR-033): Seite anlegen, Text anhängen, Seiten finden.
@Suite("Kurzbefehle: Seiten")
struct PageIntentActionsTests {
    static func store() throws -> PageStore {
        PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
    }

    @discardableResult
    static func page(_ title: String, _ blocks: [BlockSnapshot], in store: PageStore) async throws -> UUID {
        let id = try await store.createPage(title: title)
        try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return id
    }

    static func block(_ kind: BlockKind, _ text: String, indent: Int = 0, checked: Bool = false) -> BlockSnapshot {
        BlockSnapshot(id: UUID(), kindRaw: kind.rawValue, text: text, properties: BlockProperties(indent: indent, isChecked: checked))
    }

    static func shape(_ blocks: [BlockSnapshot]) -> [String] {
        blocks.map { "\($0.kindRaw)/\($0.properties.indent)/\($0.properties.isChecked ? "x" : "-"): \($0.text)" }
    }

    @Test func newPageWithTitleAndOneParagraphPerLine() async throws {
        let store = try Self.store()
        let page = try await PageIntentActions(store: store).createPage(title: "  Ideen ", text: "Erste\r\n\n  Zweite  \u{2028}Dritte\u{FFFC}")
        #expect(page.title == "Ideen")
        #expect(Self.shape(try await store.blocks(of: page.id)) == [
            "paragraph/0/-: Erste", "paragraph/0/-: Zweite", "paragraph/0/-: Dritte",
        ])
        #expect(try await store.activeTitles(of: [page.id]) == [page.id: "Ideen"])
    }

    @Test func newPageWithoutAnythingIsEmptyAndUntitled() async throws {
        let store = try Self.store()
        let page = try await PageIntentActions(store: store).createPage(title: nil, text: nil)
        #expect(page.title.isEmpty)
        #expect(try await store.blocks(of: page.id).isEmpty)
    }

    @Test func appendingContinuesTheListBeforeEmptyBlocksAtTheEnd() async throws {
        let store = try Self.store()
        let first = Self.block(.todo, "Brot", indent: 1, checked: true)
        let empty = Self.block(.todo, "")
        let id = try await Self.page("Einkaufsliste", [Self.block(.heading1, "Markt"), first, empty], in: store)

        let added = try await PageIntentActions(store: store).append("Milch\nEier", to: id)
        #expect(added == 2)
        #expect(Self.shape(try await store.blocks(of: id)) == [
            "heading1/0/-: Markt", "todo/1/x: Brot", "todo/1/-: Milch", "todo/1/-: Eier", "todo/0/-: ",
        ])
    }

    @Test func appendingAfterTextAddsParagraphs() async throws {
        let store = try Self.store()
        let id = try await Self.page("Notiz", [Self.block(.quote, "Zitat"), Self.block(.divider, "")], in: store)
        try await PageIntentActions(store: store).append("Neu", to: id)
        #expect(Self.shape(try await store.blocks(of: id)) == ["quote/0/-: Zitat", "divider/0/-: ", "paragraph/0/-: Neu"])
    }

    @Test func appendingToAnEmptyPageAddsParagraphs() async throws {
        let store = try Self.store()
        let id = try await Self.page("Leer", [], in: store)
        try await PageIntentActions(store: store).append("Neu", to: id)
        #expect(Self.shape(try await store.blocks(of: id)) == ["paragraph/0/-: Neu"])
    }

    @Test func appendingNothingOrToTrashedPagesFails() async throws {
        let store = try Self.store()
        let actions = PageIntentActions(store: store)
        let id = try await Self.page("Notiz", [Self.block(.paragraph, "Text")], in: store)
        await #expect(throws: PageIntentActions.Failure.emptyText) { try await actions.append(" \n\u{FFFC}\n", to: id) }

        try await store.trash(id)
        await #expect(throws: PageIntentActions.Failure.pageMissing) { try await actions.append("Neu", to: id) }
        await #expect(throws: PageIntentActions.Failure.pageMissing) { try await actions.append("Neu", to: UUID()) }
        #expect(Self.shape(try await store.blocks(of: id)) == ["paragraph/0/-: Text"])
    }

    @Test func findsPagesByTitleOnlyAndNeverInTheTrash() async throws {
        let store = try Self.store()
        let actions = PageIntentActions(store: store)
        let list = try await Self.page("Einkaufsliste", [], in: store)
        try await Self.page("Rezepte", [Self.block(.paragraph, "Einkaufsliste für Kuchen")], in: store)
        let old = try await Self.page("Alte Einkaufsliste", [], in: store)
        try await store.trash(old)

        #expect(try await actions.pages(matching: "einkauf") == [.init(id: list, title: "Einkaufsliste")])
        #expect(try await actions.pages([old, list, UUID()]) == [.init(id: list, title: "Einkaufsliste")])
    }

    @Test func suggestsRecentlyEditedPages() async throws {
        let store = try Self.store()
        let actions = PageIntentActions(store: store)
        for index in 1...12 { try await Self.page("Seite \(index)", [], in: store) }
        let suggested = try await actions.suggestedPages()
        #expect(suggested.count == PageIntentActions.suggestionLimit)
        #expect(suggested.first?.title == "Seite 12")
    }
}
