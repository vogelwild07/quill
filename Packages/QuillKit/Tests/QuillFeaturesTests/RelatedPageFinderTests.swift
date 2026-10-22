import Foundation
import QuillAI
@testable import QuillFeatures
import QuillModel
import Testing

/// Verwandte Seiten (16.5, ADR-032): Begriffe des Modells aus der Seite, Seiten aus der Suche.
@Suite("KI: Verwandte Seiten")
struct RelatedPageFinderTests {
    /// Gibt feste Suchbegriffe zurück und merkt sich jede Anfrage nach Begriffen.
    actor RecordingModel: TextModel {
        let terms: [String]
        private(set) var prompts: [String] = []

        init(terms: [String]) { self.terms = terms }

        func respond(instructions: String, prompt: String) async throws -> String { "" }

        func list(instructions: String, prompt: String) async throws -> [String] {
            prompts.append(prompt)
            return terms
        }
    }

    static func store() throws -> PageStore {
        PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
    }

    @discardableResult
    static func page(_ title: String, _ texts: [String], in store: PageStore) async throws -> UUID {
        let id = try await store.createPage(title: title)
        let blocks = texts.map { BlockSnapshot(id: UUID(), text: $0) }
        try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        return id
    }

    @Test func pagesWithSharedTermsWithoutThePageItselfAndTrash() async throws {
        let store = try Self.store()
        let trip = try await Self.page("Gardasee", ["Zug bis Verona", "Fahrräder reservieren"], in: store)
        let packing = try await Self.page("Packliste", ["Fahrräder", "Badesachen"], in: store)
        let route = try await Self.page("Route", ["Verona, dann Gardasee"], in: store)
        try await Self.page("Kuchen", ["Zwetschgen"], in: store)
        let trashed = try await Self.page("Alt", ["Verona 2019"], in: store)
        try await store.trash(trashed)
        let model = RecordingModel(terms: ["Gardasee", "Verona", "Fahrräder"])

        let pages = try await RelatedPageFinder(model: model, store: store).related(to: trip, title: "Gardasee")
        #expect(pages == [
            .init(pageID: route, title: "Route", terms: ["Gardasee", "Verona"]),
            .init(pageID: packing, title: "Packliste", terms: ["Fahrräder"]),
        ])
        #expect(await model.prompts == ["Gardasee\n\nZug bis Verona\nFahrräder reservieren"])
    }

    @Test func emptyPageAsksNothing() async throws {
        let store = try Self.store()
        let empty = try await Self.page("", ["", "  "], in: store)
        let model = RecordingModel(terms: ["Milch"])
        await #expect(throws: RelatedPageFinder.Failure.empty) {
            try await RelatedPageFinder(model: model, store: store).related(to: empty, title: " ")
        }
        #expect(await model.prompts.isEmpty)
    }

    @Test func pageWithOnlyATitleAsksWithTheTitle() async throws {
        let store = try Self.store()
        let page = try await Self.page("Urlaub", [], in: store)
        let model = RecordingModel(terms: ["Urlaub"])
        let pages = try await RelatedPageFinder(model: model, store: store).related(to: page, title: "Urlaub")
        #expect(pages.isEmpty)
        #expect(await model.prompts == ["Urlaub"])
    }

    @Test func atMostFivePagesMoreSharedTermsFirst() async throws {
        let store = try Self.store()
        let page = try await Self.page("Frühstück", ["Milch und Brot"], in: store)
        // Zuerst angelegt: Die Suche zeigt sie unter „Milch“ zuletzt.
        let both = try await Self.page("Bäcker", ["Brot, Milch"], in: store)
        for index in 1...6 { try await Self.page("Liste \(index)", ["Milch"], in: store) }
        let model = RecordingModel(terms: ["Milch", "Brot"])
        let pages = try await RelatedPageFinder(model: model, store: store).related(to: page, title: "Frühstück")
        #expect(pages.count == RelatedPageFinder.maxPages)
        #expect(pages.first?.pageID == both)
        #expect(!pages.contains { $0.pageID == page })
    }

    @Test func longPagesSendOnlyTheirBeginning() async throws {
        let store = try Self.store()
        let filler = String(repeating: "Füllwort ", count: 1500)
        let page = try await Self.page("Haus", ["Anfang", filler, "Ende"], in: store)
        let model = RecordingModel(terms: [])
        _ = try await RelatedPageFinder(model: model, store: store).related(to: page, title: "Haus")
        let prompt = try #require(await model.prompts.first)
        #expect(prompt.hasPrefix("Haus\n\nAnfang\n"))
        #expect(prompt.count == RelatedPageFinder.textLimit)
        #expect(!prompt.contains("Ende"))
    }
}
