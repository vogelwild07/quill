import Foundation
@testable import QuillEditor
@testable import QuillEditorCore
import QuillModel
import SwiftData
import Testing

@MainActor
@Suite("Persistenz: EditorPersistenceBridge", .serialized)
struct EditorPersistenceBridgeTests {
    let container: ModelContainer
    let store: PageStore
    let pageID: UUID

    init() async throws {
        container = try QuillStore.makeInMemoryContainer()
        store = PageStore(modelContainer: container)
        pageID = try await store.createPage(title: "Test")
    }

    private func bridge(delay: Duration = .seconds(60)) -> EditorPersistenceBridge {
        EditorPersistenceBridge(pageID: pageID, store: store, delay: delay)
    }

    private func storedBlocks() throws -> [Block] {
        try ModelContext(container).fetch(FetchDescriptor<Block>()).sorted { $0.sortKey < $1.sortKey }
    }

    @Test func emptyPageIsNotWrittenUntilTyping() async throws {
        let bridge = bridge()
        var document = try await bridge.load()
        #expect(document.count == 1)
        bridge.documentDidChange(document)
        await bridge.flush()
        #expect(try storedBlocks().isEmpty)

        document[0].text = "Hallo"
        bridge.documentDidChange(document)
        await bridge.flush()
        #expect(try storedBlocks().map(\.text) == ["Hallo"])
        #expect(!bridge.hasUnsavedChanges)
    }

    @Test func formattingIsStoredAsRichTextOnlyWhenPresent() async throws {
        let bridge = bridge()
        _ = try await bridge.load()
        let document = EditorDocument(blocks: [
            EditorBlock(text: "fett", spans: [InlineSpan(0..<4, marks: [.bold])]),
            EditorBlock(kind: .heading1, text: "schlicht"),
        ])
        bridge.documentDidChange(document)
        await bridge.flush()
        let blocks = try storedBlocks()
        #expect(blocks.map(\.kindRaw) == ["paragraph", "heading1"])
        #expect(blocks[1].richText == nil)
        let rich = try #require(blocks[0].richText.flatMap(RichText.decode))
        #expect(rich.runs == [RichText.Run(text: "fett", marks: ["bold"])])

        let reloaded = try await self.bridge().load()
        #expect(reloaded == document)
    }

    @Test func debounceCoalescesChanges() async throws {
        let bridge = bridge(delay: .milliseconds(50))
        var document = try await bridge.load()
        for text in ["a", "ab", "abc"] {
            document[0].text = text
            bridge.documentDidChange(document)
        }
        #expect(try storedBlocks().isEmpty)
        // Mit Frist statt fester Pause: Unter Last braucht das Speichern länger
        // (einmal rot bei 300 ms, Phase 7.2).
        let deadline = ContinuousClock.now + .seconds(5)
        while bridge.hasUnsavedChanges, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try storedBlocks().map(\.text) == ["abc"])
        #expect(!bridge.hasUnsavedChanges)
    }

    @Test func onlyChangedBlocksAreWritten() async throws {
        let bridge = bridge()
        _ = try await bridge.load()
        var document = EditorDocument(blocks: [EditorBlock(text: "a"), EditorBlock(text: "b"), EditorBlock(text: "c")])
        bridge.documentDidChange(document)
        await bridge.flush()
        let before = Dictionary(uniqueKeysWithValues: try storedBlocks().map { ($0.text, $0.updatedAt) })
        try await Task.sleep(for: .milliseconds(5))

        document[1].text = "B"
        #expect(bridge.edits(for: document).upserts.map(\.text) == ["B"])
        #expect(bridge.edits(for: document).order == nil)
        bridge.documentDidChange(document)
        await bridge.flush()
        let after = try storedBlocks()
        #expect(after.map(\.text) == ["a", "B", "c"])
        #expect(after[0].updatedAt == before["a"])
        #expect(after[2].updatedAt == before["c"])
    }

    @Test func deletingAndReorderingIsStored() async throws {
        let bridge = bridge()
        _ = try await bridge.load()
        var document = EditorDocument(blocks: [EditorBlock(text: "a"), EditorBlock(text: "b"), EditorBlock(text: "c")])
        bridge.documentDidChange(document)
        await bridge.flush()

        document.moveBlocks(IndexSet(integer: 2), to: 0)
        document.deleteBlock(at: 2)
        let edits = bridge.edits(for: document)
        #expect(edits.upserts.isEmpty)
        #expect(edits.deletions.count == 1)
        bridge.documentDidChange(document)
        await bridge.flush()
        #expect(try storedBlocks().map(\.text) == ["c", "a"])
    }

    @Test func unknownBlockKindIsNotOverwrittenUnlessEdited() async throws {
        let context = ModelContext(container)
        let page = try #require(try context.fetch(FetchDescriptor<Page>()).first)
        let future = Block(text: "aus der Zukunft", sortKey: "V")
        future.kindRaw = "toggle"
        context.insert(future)
        future.page = page
        try context.save()

        let bridge = bridge()
        var document = try await bridge.load()
        #expect(document[0].kind == .paragraph)
        document.insertBlock(EditorBlock(text: "neu"), at: 1)
        bridge.documentDidChange(document)
        await bridge.flush()
        #expect(try storedBlocks().map(\.kindRaw) == ["toggle", "paragraph"])
    }

    @Test func failedSaveKeepsChangesForRetry() async throws {
        let missing = EditorPersistenceBridge(pageID: UUID(), store: store, delay: .seconds(60))
        missing.documentDidChange(EditorDocument(blocks: [EditorBlock(text: "nicht verlieren")]))
        await missing.flush()
        #expect(missing.lastError != nil)
        #expect(missing.hasUnsavedChanges)
    }

    @Test func otherWindowReloadsOnlyWithoutOwnChanges() async throws {
        let writer = bridge()
        let reader = bridge()
        let busy = bridge()
        _ = try await writer.load()
        _ = try await reader.load()
        var busyDocument = try await busy.load()

        var received: EditorDocument?
        reader.onExternalChange = { received = $0; return true }
        var busyReceived = false
        busy.onExternalChange = { _ in busyReceived = true; return true }
        busyDocument[0].text = "eigene Änderung"
        busy.documentDidChange(busyDocument)

        writer.documentDidChange(EditorDocument(blocks: [EditorBlock(text: "aus Fenster A")]))
        await writer.flush()
        try await Task.sleep(for: .milliseconds(100))

        #expect(received?.blocks.map(\.text) == ["aus Fenster A"])
        #expect(!busyReceived)
    }

    // MARK: Review-Fehler

    private func deletePage() throws {
        let context = ModelContext(container)
        for page in try context.fetch(FetchDescriptor<Page>()) { context.delete(page) }
        try context.save()
    }

    private func recreatePage() throws {
        let context = ModelContext(container)
        let page = Page(title: "Test")
        page.id = pageID
        context.insert(page)
        try context.save()
    }

    /// Fehler 2: Nach einem Fehler versucht die Bridge es selbst erneut, mit Backoff.
    @Test func failedSaveIsRetriedAutomatically() async throws {
        let bridge = EditorPersistenceBridge(
            pageID: pageID, store: store, delay: .seconds(60),
            retryDelay: .milliseconds(20), maxRetryDelay: .milliseconds(80)
        )
        _ = try await bridge.load()
        try deletePage()

        bridge.documentDidChange(EditorDocument(blocks: [EditorBlock(text: "nicht verlieren")]))
        #expect(await bridge.flush() == false)
        #expect(bridge.lastError != nil)
        #expect(bridge.hasUnsavedChanges)

        try recreatePage()
        try await Task.sleep(for: .milliseconds(600))
        #expect(bridge.lastError == nil)
        #expect(!bridge.hasUnsavedChanges)
        #expect(try storedBlocks().map(\.text) == ["nicht verlieren"])
    }

    /// Fehler 1 (Teil): `flushAll` meldet, wenn etwas nicht gespeichert werden konnte.
    @Test func flushAllReportsFailure() async throws {
        let bridge = bridge()
        _ = try await bridge.load()
        try deletePage()
        bridge.documentDidChange(EditorDocument(blocks: [EditorBlock(text: "x")]))
        #expect(await EditorPersistenceBridge.flushAll() != nil)

        try recreatePage()
        #expect(await EditorPersistenceBridge.flushAll() == nil)
    }

    /// Fehler 5: Eine geschlossene Bridge speichert evtl. noch; die neue lädt erst danach.
    @Test func loadWaitsForPendingChangesOfSamePage() async throws {
        var closed: EditorPersistenceBridge? = bridge()
        _ = try await closed?.load()
        closed?.documentDidChange(EditorDocument(blocks: [EditorBlock(text: "vor dem Schließen")]))
        let flushing = closed.map { bridge in Task { await bridge.flush() } }
        closed = nil

        let reopened = try await bridge().load()
        #expect(reopened.blocks.map(\.text) == ["vor dem Schließen"])
        _ = await flushing?.value
    }

    /// Markierter Text: Lehnt der Editor das Neuladen ab, bleiben fremde Änderungen
    /// erhalten und werden nach dem eigenen Speichern nachgeladen.
    @Test func rejectedReloadKeepsForeignChanges() async throws {
        let writer = bridge()
        let reader = bridge()
        let first = EditorBlock(text: "eins")
        let second = EditorBlock(text: "zwei")
        _ = try await writer.load()
        writer.documentDidChange(EditorDocument(blocks: [first, second]))
        await writer.flush()
        var readerDocument = try await reader.load()

        var accepts = false
        var received: EditorDocument?
        reader.onExternalChange = { document in
            if accepts { received = document }
            return accepts
        }
        var writerDocument = EditorDocument(blocks: [first, second])
        writerDocument[0].text = "eins aus A"
        writer.documentDidChange(writerDocument)
        await writer.flush()
        try await Task.sleep(for: .milliseconds(100))
        #expect(received == nil)

        accepts = true
        readerDocument[1].text = "zwei aus B"
        reader.documentDidChange(readerDocument)
        await reader.flush()
        #expect(try storedBlocks().map(\.text) == ["eins aus A", "zwei aus B"])
        #expect(received?.blocks.map(\.text) == ["eins aus A", "zwei aus B"])
    }
}

@MainActor
@Suite("Persistenz: gleichzeitiges Speichern", .serialized, .timeLimit(.minutes(1)))
struct EditorPersistenceBridgeConcurrencyTests {
    /// Seitenwechsel und Beenden gleichzeitig: beide `flush()` müssen enden.
    @Test func concurrentFlushesBothFinish() async throws {
        let container = try QuillStore.makeInMemoryContainer()
        let store = PageStore(modelContainer: container)
        let pageID = try await store.createPage()
        let bridge = EditorPersistenceBridge(pageID: pageID, store: store, delay: .seconds(60))
        _ = try await bridge.load()
        bridge.documentDidChange(EditorDocument(blocks: [EditorBlock(text: "x")]))

        async let first: Bool = bridge.flush()
        async let second: Bool = bridge.flush()
        _ = await (first, second)
        #expect(!bridge.hasUnsavedChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Block>()).map(\.text) == ["x"])
    }
}
