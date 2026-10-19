import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import QuillModel

@Suite("Export-Snapshot")
struct PageStoreExportTests {
    let container: ModelContainer
    let store: PageStore

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
    }

    @Test func snapshotHasBlocksImagesAndActiveSubpagesInOrder() async throws {
        let root = try await store.createPage(title: "Projekte")
        let second = try await store.createPage(title: "Zwei", in: root)
        let first = try await store.createPage(title: "Eins", in: root, at: .before(second))
        let trashed = try await store.createPage(title: "Weg", in: root)
        let grandchild = try await store.createPage(title: "Enkel", in: first)
        try await store.trash(trashed)

        let image = try await store.importImage(TestImages.make(width: 4, height: 4, type: .png, alpha: true))
        let text = BlockSnapshot(id: UUID(), text: "Hallo")
        let picture = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: image.assetID))
        try await store.applyEdits(root, BlockEdits(upserts: [picture, text], order: [text.id, picture.id]))

        let snapshot = try await store.exportSnapshot(of: root, includeSubpages: true)
        #expect(snapshot.title == "Projekte")
        #expect(snapshot.blocks.map(\.id) == [text.id, picture.id])
        #expect(snapshot.imageTypes == [image.assetID: "public.png"])
        #expect(snapshot.children.map(\.title) == ["Eins", "Zwei"])
        #expect(snapshot.children[0].children.map(\.id) == [grandchild])

        let single = try await store.exportSnapshot(of: root, includeSubpages: false)
        #expect(single.children.isEmpty)
        #expect(single.blocks.count == 2)
    }

    @Test func pageInTrashIsNotExported() async throws {
        let root = try await store.createPage(title: "Projekte")
        let child = try await store.createPage(title: "Kind", in: root)
        try await store.trash(root)
        await #expect(throws: PageStoreError.pageNotFound(child)) {
            try await store.exportSnapshot(of: child, includeSubpages: true)
        }
    }
}
