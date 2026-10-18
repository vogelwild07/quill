import Foundation
import SwiftData
import Testing
@testable import QuillModel

@Suite struct PageStoreBlocksTests {
    let container: ModelContainer
    let store: PageStore

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
    }

    /// Frischer Kontext, damit der Test sieht, was der Store gespeichert hat.
    private func stored(_ pageID: UUID) throws -> [Block] {
        try ModelContext(container).fetch(FetchDescriptor<Block>())
            .filter { $0.page?.id == pageID }
            .sorted { $0.sortKey < $1.sortKey }
    }

    private func snapshots(_ texts: [String]) -> [BlockSnapshot] {
        texts.map { BlockSnapshot(id: UUID(), text: $0) }
    }

    @Test func applyEditsCreatesBlocksInOrder() async throws {
        let page = try await store.createPage(title: "Seite")
        let blocks = snapshots(["eins", "zwei", "drei"])
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        #expect(try stored(page).map(\.text) == ["eins", "zwei", "drei"])
        #expect(try await store.blocks(of: page) == blocks)
    }

    @Test func onlyChangedBlocksGetNewTimestamp() async throws {
        let page = try await store.createPage()
        var blocks = snapshots(["a", "b"])
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        let before = try stored(page).map(\.updatedAt)
        try await Task.sleep(for: .milliseconds(5))

        blocks[1].text = "B"
        try await store.applyEdits(page, BlockEdits(upserts: blocks))
        let after = try stored(page)
        #expect(after[0].updatedAt == before[0])
        #expect(after[1].updatedAt > before[1])
        #expect(after.map(\.text) == ["a", "B"])
    }

    @Test func deletionRemovesBlock() async throws {
        let page = try await store.createPage()
        let blocks = snapshots(["a", "b", "c"])
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        try await store.applyEdits(page, BlockEdits(deletions: [blocks[1].id]))
        #expect(try stored(page).map(\.text) == ["a", "c"])
    }

    @Test func movingOneBlockChangesOnlyItsKey() async throws {
        let page = try await store.createPage()
        let blocks = snapshots(["a", "b", "c", "d", "e"])
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        let keys = Dictionary(uniqueKeysWithValues: try stored(page).map { ($0.id, $0.sortKey) })

        let order = [blocks[0], blocks[3], blocks[1], blocks[2], blocks[4]].map(\.id)
        try await store.applyEdits(page, BlockEdits(order: order))
        let after = try stored(page)
        #expect(after.map(\.text) == ["a", "d", "b", "c", "e"])
        #expect(after.filter { keys[$0.id] != $0.sortKey }.map(\.text) == ["d"])
    }

    @Test func blocksMissingFromOrderKeepTheirKeys() async throws {
        let page = try await store.createPage()
        let blocks = snapshots(["a", "b", "c"])
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        let keyOfB = try stored(page)[1].sortKey

        // Ein anderes Fenster kennt „b“ nicht und stellt „c“ vor „a“.
        try await store.applyEdits(page, BlockEdits(order: [blocks[2].id, blocks[0].id]))
        let after = try stored(page)
        #expect(after.first { $0.text == "b" }?.sortKey == keyOfB)
        #expect(after.map(\.text).firstIndex(of: "c")! < after.map(\.text).firstIndex(of: "a")!)
    }

    @Test func manyInsertsIntoOneGapStayShort() async throws {
        let page = try await store.createPage()
        let ends = snapshots(["Anfang", "Ende"])
        try await store.applyEdits(page, BlockEdits(upserts: ends, order: ends.map(\.id)))
        let middle = snapshots((0..<500).map { "Zeile \($0)" })
        let order = [ends[0].id] + middle.map(\.id) + [ends[1].id]
        try await store.applyEdits(page, BlockEdits(upserts: middle, order: order))
        let after = try stored(page)
        #expect(after.map(\.id) == order)
        #expect(after.map(\.sortKey.count).max()! <= 12)
    }

    @Test func newBlocksWithoutOrderAreAppended() async throws {
        let page = try await store.createPage()
        let first = snapshots(["a"])
        try await store.applyEdits(page, BlockEdits(upserts: first, order: first.map(\.id)))
        try await store.applyEdits(page, BlockEdits(upserts: snapshots(["b"])))
        #expect(try stored(page).map(\.text) == ["a", "b"])
    }

    @Test func emptyOrUnchangedEditsDoNotTouchPage() async throws {
        let page = try await store.createPage()
        let blocks = snapshots(["a"])
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        let pageUpdated = try ModelContext(container).fetch(FetchDescriptor<Page>()).first!.updatedAt
        try await store.applyEdits(page, BlockEdits())
        try await store.applyEdits(page, BlockEdits(upserts: blocks, order: blocks.map(\.id)))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Page>()).first!.updatedAt == pageUpdated)
    }

    @Test func longestIncreasingRunIgnoresInvalidKeys() {
        let keep = PageStore.longestIncreasingRun(["a1", "", "a3", "a2", "a4"])
        #expect(keep == [0, 2, 4] || keep == [0, 3, 4])
    }
}
