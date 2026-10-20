#if canImport(AppKit)
import AppKit
@testable import QuillEditor
@testable import QuillEditorCore
@testable import QuillFeatures
import QuillModel
import SwiftData
import Testing

/// Editor einer Seite mit echtem Store im Arbeitsspeicher: Tippen, Schließen, wieder Öffnen.
@MainActor
@Suite("Seite: Editor und Persistenz", .serialized)
struct PageEditorSessionTests {
    let container: ModelContainer
    let store: PageStore
    let pageID: UUID

    init() async throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
        pageID = try await store.createPage(title: "Notizen")
    }

    private func openSession() async -> (PageEditorSession, NSWindow) {
        let session = PageEditorSession(
            pageID: pageID, title: "Notizen", icon: nil, store: store, context: container.mainContext,
            rename: { _, _ in }, setIcon: { _, _ in }
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = session.controller.scrollView
        await session.load()
        session.controller.focus()
        return (session, window)
    }

    private func type(_ text: String, in session: PageEditorSession) {
        let textView = session.controller.textView
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
    }

    @Test func typedTextAndFormattingSurviveReopening() async throws {
        let (session, _) = await openSession()
        #expect(session.controller.isEditable)
        type("# Titel", in: session)
        session.controller.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        type("fett", in: session)
        session.controller.textView.setSelectedRange(NSRange(location: 6, length: 4))
        session.controller.toggleMark(.bold)
        session.close()
        await EditorPersistenceBridge.flushAll()

        let (reopened, _) = await openSession()
        let blocks = reopened.controller.document.blocks
        #expect(blocks.map(\.text) == ["Titel", "fett"])
        #expect(blocks.map(\.kind) == [.heading1, .paragraph])
        #expect(blocks[1].spans == [InlineSpan(0..<4, marks: [.bold])])
    }

    @Test func viewingAnEmptyPageWritesNothing() async throws {
        let (session, _) = await openSession()
        session.close()
        await EditorPersistenceBridge.flushAll()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Block>()) == 0)
    }

    /// Fehler 5 aus dem Review: Schließen und sofort wieder Öffnen zeigt den neuesten Stand.
    @Test func reopeningImmediatelyShowsLatestText() async throws {
        let (session, _) = await openSession()
        type("gerade getippt", in: session)
        session.close()

        let (reopened, _) = await openSession()
        #expect(reopened.controller.document.blocks.map(\.text) == ["gerade getippt"])
    }

    /// Fehler 2 aus dem Review: Der Hinweis „Nicht gespeichert“ hängt an `lastError`.
    @Test func saveProblemIsVisibleUntilSaved() async throws {
        let (session, _) = await openSession()
        let context = ModelContext(container)
        let page = try #require(try context.fetch(FetchDescriptor<Page>()).first)
        context.delete(page)
        try context.save()

        type("x", in: session)
        #expect(await session.bridge.flush() == false)
        #expect(session.bridge.lastError != nil)

        let restored = Page(title: "Notizen")
        restored.id = pageID
        context.insert(restored)
        try context.save()
        #expect(await session.bridge.flush())
        #expect(session.bridge.lastError == nil)
    }

    @Test func headerIsAccessibleInsideTheTextView() async throws {
        let (session, _) = await openSession()
        let header = try #require(session.controller.header)
        let children = session.controller.textView.accessibilityChildren() ?? []
        #expect(children.contains { ($0 as AnyObject) === header })
        #expect(header.frame.minY == 96)
        #expect(session.controller.textView.textContainerInset.height > 96 + header.frame.height)
    }
}
#endif
