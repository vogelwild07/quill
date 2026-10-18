import Foundation
import SwiftData
import Testing
@testable import QuillModel

@Suite("Navigation: Favoriten, Papierkorb, Suche")
struct PageStoreNavigationTests {
    let container: ModelContainer
    let store: PageStore

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
    }

    private func pages() throws -> [Page] {
        try ModelContext(container).fetch(FetchDescriptor<Page>())
    }

    private func favoriteTitles() throws -> [String] {
        try pages().filter(\.isFavorite).sorted { ($0.favoriteSortKey ?? "") < ($1.favoriteSortKey ?? "") }.map(\.title)
    }

    @discardableResult
    private func page(_ title: String, in parent: UUID? = nil, text: [String] = []) async throws -> UUID {
        let id = try await store.createPage(title: title, in: parent)
        let blocks = text.map { BlockSnapshot(id: UUID(), kindRaw: BlockKind.paragraph.rawValue, text: $0, properties: BlockProperties()) }
        if !blocks.isEmpty {
            try await store.applyEdits(id, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        }
        return id
    }

    // MARK: Favoriten

    @Test func favoritesKeepOrderAndCanBeMoved() async throws {
        let a = try await page("A"), b = try await page("B"), c = try await page("C")
        try await store.setFavorite(b, true)
        try await store.setFavorite(a, true)
        try await store.setFavorite(c, true)
        #expect(try favoriteTitles() == ["B", "A", "C"])

        try await store.moveFavorite(c, at: .first)
        #expect(try favoriteTitles() == ["C", "B", "A"])
        try await store.moveFavorite(b, at: .after(a))
        #expect(try favoriteTitles() == ["C", "A", "B"])

        try await store.setFavorite(a, false)
        #expect(try favoriteTitles() == ["C", "B"])
        // Erneut hinzugefügt: ans Ende.
        try await store.setFavorite(a, true)
        #expect(try favoriteTitles() == ["C", "B", "A"])
    }

    @Test func favoritePositionRestoresPlaceAfterRemoval() async throws {
        let a = try await page("A"), b = try await page("B"), c = try await page("C")
        for id in [a, b, c] { try await store.setFavorite(id, true) }
        #expect(try await store.favoritePosition(of: a) == .first)
        let old = try await store.favoritePosition(of: b)
        #expect(old == .after(a))

        try await store.setFavorite(b, false)
        #expect(try await store.favoritePosition(of: b) == nil)
        try await store.setFavorite(b, true, at: old ?? .last)
        #expect(try favoriteTitles() == ["A", "B", "C"])
    }

    @Test func favoriteWithoutKeyIsRepaired() async throws {
        let a = try await page("A"), b = try await page("B")
        let context = ModelContext(container)
        for page in try context.fetch(FetchDescriptor<Page>()) where page.id == a {
            page.isFavorite = true
            page.favoriteSortKey = nil
        }
        try context.save()
        try await store.setFavorite(b, true)
        #expect(try favoriteTitles() == ["A", "B"])
        #expect(try pages().filter(\.isFavorite).allSatisfy { $0.favoriteSortKey.map(FractionalIndex.isValid) == true })
    }

    // MARK: Papierkorb

    @Test func trashedPagesListNewestFirstWithPathAndPreview() async throws {
        let parent = try await page("Projekte")
        let child = try await page("Reise", in: parent, text: ["", "Flug buchen und Hotel suchen"])
        let other = try await page("Alt")
        try await store.trash(other)
        try await Task.sleep(for: .milliseconds(5))
        try await store.trash(child)

        let trashed = try await store.trashedPages()
        #expect(trashed.map(\.title) == ["Reise", "Alt"])
        #expect(trashed[0].path == ["Projekte"])
        #expect(trashed[0].preview == "Flug buchen und Hotel suchen")
        #expect(trashed[1].preview.isEmpty)
    }

    @Test func deletePermanentlyRemovesSubtreeBlocksAndAssets() async throws {
        let parent = try await page("Oben", text: ["Text"])
        let child = try await page("Unten", in: parent, text: ["Mehr"])
        let imported = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let image = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: imported.assetID))
        try await store.applyEdits(child, BlockEdits(upserts: [image], order: nil))
        let keep = try await page("Bleibt", text: ["bleibt"])

        await #expect(throws: PageStoreError.notInTrash(parent)) { try await store.deletePermanently(parent) }
        try await store.trash(parent)
        try await store.deletePermanently(parent)

        let context = ModelContext(container)
        #expect(try pages().map(\.id) == [keep])
        #expect(try context.fetch(FetchDescriptor<Block>()).map(\.text) == ["bleibt"])
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0)
    }

    @Test func deletePermanentlyWorksForPageInTrashedParent() async throws {
        let parent = try await page("Oben")
        let child = try await page("Unten", in: parent)
        try await store.trash(parent)
        try await store.deletePermanently(child)
        #expect(try pages().map(\.title) == ["Oben"])
    }

    @Test func emptyTrashRespectsAgeAndSubpages() async throws {
        let old = try await page("Alt")
        let oldChild = try await page("Alt-Kind", in: old)
        let recent = try await page("Neu")
        let oldInsideRecent = try await page("Altes Kind", in: recent)
        let active = try await page("Aktiv")
        let now = Date.now
        let context = ModelContext(container)
        for page in try context.fetch(FetchDescriptor<Page>()) {
            switch page.id {
            case old: page.trashedAt = now.addingTimeInterval(-31 * 86_400)
            case recent: page.trashedAt = now.addingTimeInterval(-2 * 86_400)
            case oldInsideRecent: page.trashedAt = now.addingTimeInterval(-40 * 86_400)
            default: break
            }
        }
        try context.save()

        let removed = try await store.emptyTrash(olderThan: 30 * 86_400, now: now)
        #expect(removed == 2)
        let left = Set(try pages().map(\.id))
        #expect(left == [recent, active])
        #expect(!left.contains(oldChild))

        #expect(try await store.emptyTrash() == 1)
        #expect(try pages().map(\.id) == [active])
    }

    // MARK: Suche

    @Test func searchRanksTitlesThenContent() async throws {
        try await page("Reisekosten")
        try await page("Lissabon Reise")
        try await page("Kreisel")
        try await page("Inbox", text: ["Anfang", "Flug für die Reise buchen"])
        let hits = try await store.search("reise")
        #expect(hits.map(\.title) == ["Reisekosten", "Lissabon Reise", "Kreisel", "Inbox"])
        guard case .content(_, let match) = hits[3].kind else {
            Issue.record("Kein Inhaltstreffer")
            return
        }
        #expect(("Flug für die Reise buchen" as NSString).substring(with: match) == "Reise")
        #expect(hits[3].excerpt == "Flug für die Reise buchen")
    }

    @Test func searchIgnoresCaseAndAccentsAndTrash() async throws {
        try await page("Café Müller")
        let trashed = try await page("Cafeteria")
        let parent = try await page("Ordner")
        try await page("Cafe im Ordner", in: parent)
        try await store.trash(trashed)
        try await store.trash(parent)
        #expect(try await store.search("CAFE").map(\.title) == ["Café Müller"])
        #expect(try await store.search("muller").map(\.title) == ["Café Müller"])
        #expect(try await store.search("  ").isEmpty)
    }

    @Test func oneContentHitPerPageFromFirstBlock() async throws {
        let id = try await store.createPage(title: "Notizen")
        // Zuerst gespeichert, aber in der Seite hinten: Der Treffer kommt vom ersten Block.
        let later = BlockSnapshot(id: UUID(), kindRaw: BlockKind.paragraph.rawValue, text: "hinten ein Apfel", properties: BlockProperties())
        let first = BlockSnapshot(id: UUID(), kindRaw: BlockKind.paragraph.rawValue, text: "vorne ein Apfel", properties: BlockProperties())
        try await store.applyEdits(id, BlockEdits(upserts: [later, first], order: [first.id, later.id]))
        let hits = try await store.search("apfel")
        #expect(hits.count == 1)
        #expect(hits.first?.excerpt == "vorne ein Apfel")
    }

    @Test func recentPagesSkipTrash() async throws {
        let a = try await page("A")
        try await page("B")
        try await store.rename(a, to: "A2")
        let c = try await page("C")
        try await store.trash(c)
        #expect(try await store.recentPages().map(\.title) == ["A2", "B"])
    }

    @Test func snippetCutsAtWordsAroundMatch() {
        let text = "Ein ziemlich langer Absatz mit vielen Worten, in dem irgendwo weit hinten das gesuchte Stichwort Lissabon steht und danach noch viel mehr Text folgt, damit auch hinten gekürzt wird."
        let match = (text as NSString).range(of: "Lissabon")
        let excerpt = TextSnippet.excerpt(text, around: match)
        #expect(excerpt.hasPrefix("…") && excerpt.hasSuffix("…"))
        #expect(excerpt.contains("Lissabon"))
        #expect((excerpt as NSString).length <= TextSnippet.maxLength + 2)
        #expect(!excerpt.dropFirst().hasPrefix(" "))
        #expect(TextSnippet.excerpt("kurz\nund gut") == "kurz und gut")
        #expect(TextSnippet.preview(of: ["", "  ", "Erste Worte"]) == "Erste Worte")
    }
}
