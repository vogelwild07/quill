import Foundation
import SwiftData
import Testing
@testable import QuillModel

@Suite struct PageStoreTests {
    let container: ModelContainer
    let store: PageStore

    init() throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
    }

    /// Frischer Kontext, damit der Test sieht, was der Store gespeichert hat.
    private func pages() throws -> [Page] {
        try ModelContext(container).fetch(FetchDescriptor<Page>())
    }

    private func page(_ id: UUID) throws -> Page {
        try #require(try pages().first { $0.id == id })
    }

    /// Titel der Kinder von `parentID` (`nil` = oberste Ebene) in sortKey-Reihenfolge.
    private func titles(under parentID: UUID?) throws -> [String] {
        try pages()
            .filter { $0.parent?.id == parentID }
            .sorted { $0.sortKey < $1.sortKey }
            .map(\.title)
    }

    @Test func ensureWorkspaceCreatesExactlyOne() async throws {
        let first = try await store.ensureWorkspace()
        let second = try await store.ensureWorkspace()
        #expect(first == second)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Workspace>()) == 1)
    }

    @Test func ensureWorkspaceMergesDuplicatesAndOrphans() async throws {
        let context = ModelContext(container)
        let older = Workspace(name: "Alt")
        older.createdAt = .distantPast
        let newer = Workspace(name: "Neu")
        let pageInNewer = Page(title: "In Neu")
        let orphan = Page(title: "Ohne Workspace")
        context.insert(older)
        context.insert(newer)
        context.insert(orphan)
        pageInNewer.workspace = newer
        try context.save()

        let id = try await store.ensureWorkspace()

        #expect(id == older.id)
        let workspaces = try ModelContext(container).fetch(FetchDescriptor<Workspace>())
        #expect(workspaces.map(\.name) == ["Alt"])
        #expect(try pages().allSatisfy { $0.workspace?.id == older.id })
        #expect(try pages().count == 2)
    }

    @Test func createPagesInOrder() async throws {
        let a = try await store.createPage(title: "A")
        try await store.createPage(title: "C")
        try await store.createPage(title: "B", at: .after(a))
        try await store.createPage(title: "0", at: .first)
        try await store.createPage(title: "Z", at: .last)

        #expect(try titles(under: nil) == ["0", "A", "B", "C", "Z"])
        #expect(try pages().allSatisfy { $0.workspace != nil })
    }

    @Test func createNestedPages() async throws {
        let parent = try await store.createPage(title: "Eltern")
        let child = try await store.createPage(title: "Kind", in: parent)
        try await store.createPage(title: "Vor Kind", in: parent, at: .before(child))

        #expect(try titles(under: parent) == ["Vor Kind", "Kind"])
        #expect(try titles(under: nil) == ["Eltern"])
    }

    @Test func renameAndIconUpdateTimestamp() async throws {
        let id = try await store.createPage(title: "Alt")
        let before = try page(id).updatedAt

        try await store.rename(id, to: "Neu")
        try await store.setIcon(id, to: "📓")

        let page = try page(id)
        #expect(page.title == "Neu")
        #expect(page.icon == "📓")
        #expect(page.updatedAt >= before)

        try await store.setIcon(id, to: nil)
        #expect(try self.page(id).icon == nil)
    }

    @Test func moveChangesOnlyTheMovedPage() async throws {
        let a = try await store.createPage(title: "A")
        let b = try await store.createPage(title: "B")
        let c = try await store.createPage(title: "C")
        let keysBefore = try Dictionary(uniqueKeysWithValues: pages().map { ($0.id, $0.sortKey) })

        try await store.move(c, to: nil, at: .before(a))

        #expect(try titles(under: nil) == ["C", "A", "B"])
        let keysAfter = try Dictionary(uniqueKeysWithValues: pages().map { ($0.id, $0.sortKey) })
        #expect(keysAfter[a] == keysBefore[a])
        #expect(keysAfter[b] == keysBefore[b])
        #expect(keysAfter[c] != keysBefore[c])
    }

    @Test func moveIntoAndOutOfParent() async throws {
        let parent = try await store.createPage(title: "Eltern")
        let page = try await store.createPage(title: "Seite")

        try await store.move(page, to: parent, at: .last)
        #expect(try titles(under: parent) == ["Seite"])
        #expect(try titles(under: nil) == ["Eltern"])

        try await store.move(page, to: nil, at: .first)
        #expect(try titles(under: nil) == ["Seite", "Eltern"])
        #expect(try titles(under: parent).isEmpty)
    }

    @Test func moveRejectsCycles() async throws {
        let parent = try await store.createPage(title: "Eltern")
        let child = try await store.createPage(title: "Kind", in: parent)
        let grandchild = try await store.createPage(title: "Enkel", in: child)

        await #expect(throws: PageStoreError.cycle) {
            try await store.move(parent, to: grandchild, at: .last)
        }
        await #expect(throws: PageStoreError.cycle) {
            try await store.move(parent, to: parent, at: .last)
        }
    }

    @Test func unknownIDsThrow() async throws {
        let missing = UUID()
        await #expect(throws: PageStoreError.pageNotFound(missing)) {
            try await store.rename(missing, to: "x")
        }
        let page = try await store.createPage(title: "A")
        await #expect(throws: PageStoreError.siblingNotFound(missing)) {
            try await store.move(page, to: nil, at: .after(missing))
        }
    }

    @Test func brokenSiblingKeysAreRepaired() async throws {
        let context = ModelContext(container)
        for title in ["A", "B", "C"] {
            context.insert(Page(title: title, sortKey: ""))
        }
        try context.save()
        let a = try #require(try pages().first { $0.title == "A" })

        try await store.createPage(title: "Neu", at: .after(a.id))

        let roots = try pages().sorted { $0.sortKey < $1.sortKey }
        #expect(roots.allSatisfy { FractionalIndex.isValid($0.sortKey) })
        #expect(Set(roots.map(\.sortKey)).count == 4)
        #expect(roots.firstIndex { $0.title == "Neu" } == roots.firstIndex { $0.title == "A" }! + 1)
    }

    @Test func trashAndRestoreKeepPosition() async throws {
        try await store.createPage(title: "A")
        let b = try await store.createPage(title: "B")
        try await store.createPage(title: "C")
        let key = try page(b).sortKey

        try await store.trash(b)
        #expect(try page(b).trashedAt != nil)

        try await store.restore(b)
        #expect(try page(b).trashedAt == nil)
        #expect(try page(b).sortKey == key)
        #expect(try titles(under: nil) == ["A", "B", "C"])
    }

    @Test func restoreUnderTrashedParentMovesToTop() async throws {
        let parent = try await store.createPage(title: "Eltern")
        let child = try await store.createPage(title: "Kind", in: parent)
        try await store.trash(child)
        try await store.trash(parent)

        try await store.restore(child)

        #expect(try page(child).parent == nil)
        #expect(try titles(under: nil) == ["Eltern", "Kind"])
    }
}
