import Foundation
import ImageIO
import SwiftData
import Testing
@testable import QuillModel

@Suite("Bilder: Assets im PageStore")
struct PageStoreAssetTests {
    let container: ModelContainer
    let store: PageStore

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
    }

    private func assets() throws -> [Asset] {
        try ModelContext(container).fetch(FetchDescriptor<Asset>())
    }

    private func blocks() throws -> [Block] {
        try ModelContext(container).fetch(FetchDescriptor<Block>())
    }

    private func imageBlock(_ assetID: UUID, id: UUID = UUID()) -> BlockSnapshot {
        BlockSnapshot(id: id, kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: assetID))
    }

    @Test func importStoresDataWithoutLocation() async throws {
        let imported = try await store.importImage(TestImages.photoWithLocation())
        let stored = try #require(try await store.imageData(imported.assetID))
        #expect(TestImages.properties(of: stored.data)[kCGImagePropertyGPSDictionary] == nil)
        #expect(stored.uti == "public.jpeg")
        #expect(imported.pixelWidth == 20 && imported.pixelHeight == 40)
        let asset = try #require(try assets().first)
        #expect(asset.block == nil)
        #expect(asset.pixelWidth == 20 && asset.pixelHeight == 40)
    }

    @Test func blockLinksAssetOnSave() async throws {
        let page = try await store.createPage(title: "Bilder")
        let imported = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let block = imageBlock(imported.assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        #expect(try blocks().first?.asset?.id == imported.assetID)
        #expect(try await store.blocks(of: page).first?.properties.assetID == imported.assetID)
    }

    @Test func deletingBlockKeepsAssetForUndo() async throws {
        let page = try await store.createPage(title: "Bilder")
        let imported = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let block = imageBlock(imported.assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))

        try await store.applyEdits(page, BlockEdits(deletions: [block.id]))
        #expect(try blocks().isEmpty)
        #expect(try assets().map(\.id) == [imported.assetID])
        #expect(try assets().first?.block == nil)

        // Undo im Editor schickt denselben Block wieder.
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        #expect(try blocks().first?.asset?.id == imported.assetID)
        #expect(try assets().count == 1)
    }

    @Test func secondBlockWithSameAssetGetsACopy() async throws {
        let page = try await store.createPage(title: "Bilder")
        let imported = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let first = imageBlock(imported.assetID)
        let second = imageBlock(imported.assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [first, second], order: [first.id, second.id]))
        let stored = try blocks()
        let firstAsset = try #require(stored.first { $0.id == first.id }?.asset)
        let secondAsset = try #require(stored.first { $0.id == second.id }?.asset)
        #expect(firstAsset.id == imported.assetID)
        #expect(secondAsset.id != imported.assetID)
        #expect(secondAsset.data == firstAsset.data)
    }

    /// Der Editor schickt weiter die ID des Originals; wiederholte Änderungen am Block
    /// dürfen keine weiteren Kopien anlegen: nie mehr als ein Asset pro Bild.
    @Test func repeatedEditsNeverCreateMoreAssets() async throws {
        let page = try await store.createPage(title: "Bilder")
        let imported = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let first = imageBlock(imported.assetID)
        let second = imageBlock(imported.assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [first, second], order: [first.id, second.id]))
        let copyID = try #require(try blocks().first { $0.id == second.id }?.asset?.id)
        #expect(try assets().count == 2)

        for round in 0..<5 {
            var edited = second
            edited.properties.indent = round % 2
            let order = round % 2 == 0 ? [second.id, first.id] : [first.id, second.id]
            try await store.applyEdits(page, BlockEdits(upserts: [edited, first], order: order))
            #expect(try assets().count == 2, "Runde \(round)")
        }
        let stored = try blocks()
        #expect(stored.first { $0.id == first.id }?.asset?.id == imported.assetID)
        #expect(stored.first { $0.id == second.id }?.asset?.id == copyID)
    }

    @Test func importLinksAlreadySavedPlaceholderBlock() async throws {
        let page = try await store.createPage(title: "Bilder")
        let assetID = UUID()
        // Der Editor speichert den Block, bevor der Import fertig ist.
        let block = imageBlock(assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        #expect(try blocks().first?.asset == nil)

        let imported = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png), assetID: assetID, linkTo: block.id)
        #expect(imported.assetID == assetID)
        #expect(try blocks().first?.asset?.id == assetID)
        #expect(try await store.blocks(of: page).first?.properties.assetID == assetID)
    }

    @Test func importLinkNeverReplacesAnExistingImage() async throws {
        let page = try await store.createPage(title: "Bilder")
        let existing = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let block = imageBlock(existing.assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        _ = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png), linkTo: block.id)
        #expect(try blocks().first?.asset?.id == existing.assetID)
    }

    @Test func duplicateAssetCopiesDataAndSize() async throws {
        let imported = try await store.importImage(TestImages.make(width: 6, height: 3, type: .png))
        let copyID = try #require(try await store.duplicateAsset(imported.assetID))
        #expect(copyID != imported.assetID)
        #expect(try await store.imageData(copyID)?.data == store.imageData(imported.assetID)?.data)
        let copy = try #require(try assets().first { $0.id == copyID })
        #expect(copy.pixelWidth == 6 && copy.pixelHeight == 3)
        #expect(try await store.duplicateAsset(UUID()) == nil)
    }

    @Test func orphansAreRemovedAfterThirtyDays() async throws {
        let page = try await store.createPage(title: "Bilder")
        let linked = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let fresh = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let old = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png))
        let block = imageBlock(linked.assetID)
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))

        let now = Date.now
        let context = ModelContext(container)
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            asset.updatedAt = asset.id == fresh.assetID ? now.addingTimeInterval(-29 * 24 * 3600) : now.addingTimeInterval(-31 * 24 * 3600)
        }
        try context.save()

        let removed = try await store.removeOrphanedAssets(now: now)
        #expect(removed == 1)
        #expect(Set(try assets().map(\.id)) == [linked.assetID, fresh.assetID])
        #expect(try await store.imageData(old.assetID) == nil)
    }
}
