import Foundation
import SwiftData
import Testing
@testable import QuillModel

@MainActor
@Suite struct SchemaV1Tests {
    @Test func defaultsFollowDataModel() throws {
        let page = Page()
        #expect(page.title.isEmpty)
        #expect(page.icon == nil)
        #expect(page.kind == .page)
        #expect(page.trashedAt == nil)
        #expect(!page.isFavorite)

        let block = Block()
        #expect(block.kind == .paragraph)
        #expect(block.indent == 0)
        #expect(Workspace().name == "Mein Workspace")
    }

    @Test func unknownKindRawFallsBack() {
        let page = Page()
        page.kindRaw = "database-from-the-future"
        #expect(page.kind == .page)

        let block = Block()
        block.kindRaw = "toggle"
        #expect(block.kind == .paragraph)
    }

    @Test func relationshipsHaveInverses() throws {
        let container = try QuillStore.makeInMemoryContainer()
        let context = container.mainContext
        let workspace = Workspace()
        let parent = Page(title: "Eltern")
        let child = Page(title: "Kind")
        let block = Block(kind: .image, text: "")
        let asset = Asset(data: Data([1, 2, 3]))
        context.insert(workspace)
        parent.workspace = workspace
        child.parent = parent
        block.page = child
        block.asset = asset
        try context.save()

        #expect(workspace.pages?.contains(parent) == true)
        #expect(parent.children?.contains(child) == true)
        #expect(child.blocks?.contains(block) == true)
        #expect(asset.block === block)
    }

    @Test func deletingPageCascadesToChildrenBlocksAndAssets() throws {
        let container = try QuillStore.makeInMemoryContainer()
        let context = container.mainContext
        let parent = Page(title: "Eltern")
        let child = Page(title: "Kind")
        let block = Block(text: "Hallo")
        context.insert(parent)
        child.parent = parent
        block.page = child
        block.asset = Asset()
        try context.save()

        context.delete(parent)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Block>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Asset>()) == 0)
    }

    @Test func storeOnDiskRoundTrips() throws {
        let directory = URL.temporaryDirectory.appending(path: "QuillTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Quill.store")
        let pageID: UUID

        do {
            let container = try QuillStore.makeContainer(storeURL: storeURL)
            let page = Page(title: "Gespeichert")
            pageID = page.id
            container.mainContext.insert(page)
            try container.mainContext.save()
        }

        let container = try QuillStore.makeContainer(storeURL: storeURL)
        let pages = try container.mainContext.fetch(FetchDescriptor<Page>())
        #expect(pages.map(\.id) == [pageID])
        #expect(pages.first?.title == "Gespeichert")
    }
}
