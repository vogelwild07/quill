import Foundation
import QuillModel
@testable import QuillSync
import Testing

/// Store hinter dem Ordner (Roadmap „Später“, vor v0.4.0 zu klären): Der Abgleich hat
/// eine eigene Datei in den Ordner geschrieben und bricht ab, bevor Dokument und gelesene
/// Dateien im Store stehen. Die Blöcke im Store sind die des Nutzers, also schon neuer.
/// Nur Stores im Arbeitsspeicher und Wegwerf-Ordner.
@Suite("Abgleich: Store hinter dem Ordner")
struct SyncStoreBehindFolderTests {
    /// Neuer Block, Abgleich schreibt Datei 2, Abbruch vor dem Store; danach steht der
    /// Store auf Dokument und gelesenen Dateien von vorher, mit dem neuen Block.
    func abortAfterNewBlock(_ a: TestDevice) async throws -> (page: UUID, added: UUID) {
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        let document = try #require(try await a.store.syncPage(page)?.document)
        let cursors = try #require(try await a.store.syncState().cursors)
        let added = BlockSnapshot(id: UUID(), text: "Neu")
        try await a.store.applyEdits(page, BlockEdits(upserts: [added], order: [blocks[0], added.id]))
        try await a.sync()
        let current = try await a.store.blocks(of: page)
        #expect(try await a.store.applySyncPage(page, expected: current, edits: BlockEdits(), document: document, cursors: cursors) != nil)
        return (page, added.id)
    }

    @Test func ownFileReadableAfterTheAbortGivesNoDuplicate() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, _) = try await abortAfterNewBlock(a)
        let report = try await a.sync()
        #expect(report.conflicts[page] == nil)
        #expect(try await a.texts(of: "Notiz") == ["Anfang", "Neu"])
        #expect(try await b.sync().conflicts[page] == nil)
        #expect(try await b.texts(of: "Notiz") == ["Anfang", "Neu"])
    }

    /// Wie oben, aber die eigene Datei ist beim nächsten Abgleich noch nicht geladen.
    @Test func ownFileNotYetDownloadedAfterTheAbortGivesNoDuplicate() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let (page, added) = try await abortAfterNewBlock(a)
        a.files.state.withLock { $0.notDownloaded = ["000000000002.changes"] }
        let before = try folder.fingerprint()
        // Die Seite wartet: angefordert und gemeldet, nichts geschrieben, Blöcke bleiben.
        let waiting = try await a.sync()
        #expect(waiting.waitingForDownload == ["pages/\(page.uuidString)/\(a.deviceID.uuidString)/000000000002.changes"])
        #expect(try folder.fingerprint() == before)
        #expect(try await a.texts(of: "Notiz") == ["Anfang", "Neu"])
        a.files.state.withLock { $0.notDownloaded = [] }
        let report = try await a.sync()
        #expect(report.conflicts[page] == nil, "\(report.conflicts[page] ?? [])")
        #expect(try await a.texts(of: "Notiz") == ["Anfang", "Neu"])
        let document = try PageDocument(bytes: #require(try await a.store.syncPage(page)?.document))
        #expect(try document.blocks().filter { $0.id == added }.count == 1)
        #expect(try await b.sync().conflicts[page] == nil)
        #expect(try await b.texts(of: "Notiz") == ["Anfang", "Neu"])
    }

    /// Dasselbe mit getipptem Text statt eines neuen Blocks.
    @Test func typedTextIsNotDoubledWhenTheOwnFileComesLate() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Hallo"])
        try await a.sync()
        let document = try #require(try await a.store.syncPage(page)?.document)
        let cursors = try #require(try await a.store.syncState().cursors)
        try await a.edit(page, blocks[0]) { $0.text = "Hallo Welt" }
        try await a.sync()
        let current = try await a.store.blocks(of: page)
        #expect(try await a.store.applySyncPage(page, expected: current, edits: BlockEdits(), document: document, cursors: cursors) != nil)
        a.files.state.withLock { $0.notDownloaded = ["000000000002.changes"] }
        try await a.sync()
        a.files.state.withLock { $0.notDownloaded = [] }
        try await a.sync()
        #expect(try await a.texts(of: "Notiz") == ["Hallo Welt"])
    }

    /// Konflikt auf einer Seite, die erst dieser Abgleich anlegt: Er steht schon im
    /// Bericht dieses Abgleichs, nicht erst im nächsten.
    @Test func conflictOnAPageNewToThisDeviceIsReportedAtOnce() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let c = try await TestDevice("C", folder: folder.url)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Punkt"])
        try await a.sync()
        try await c.sync()
        try await a.edit(page, blocks[0]) { $0.kindRaw = BlockKind.todo.rawValue }
        try await c.edit(page, blocks[0]) { $0.kindRaw = BlockKind.heading2.rawValue }
        try await a.sync()
        try await c.sync()
        let b = try await TestDevice("B", folder: folder.url)
        let first = try await b.sync()
        #expect(first.conflicts[page] != nil)
        #expect(try await b.sync().conflicts[page] == first.conflicts[page])
    }

    /// Dasselbe im Seitenbaum: neue Seite, Abbruch vor dem Store, eigene Datei des
    /// Seitenbaums beim nächsten Abgleich noch nicht geladen.
    @Test func newPageIsNotDoubledInTheTreeWhenTheOwnFileComesLate() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        _ = try await a.createPage("Erste", texts: ["Eins"])
        try await a.sync()
        let state = try await a.store.syncState()
        let tree = try #require(state.tree), cursors = try #require(state.cursors)
        _ = try await a.createPage("Zweite", texts: ["Zwei"])
        try await a.sync()
        #expect(try await a.store.applySyncTree([], tree: tree, cursors: cursors))
        a.files.state.withLock { $0.notDownloaded = ["000000000002.changes"] }
        try await a.sync()
        a.files.state.withLock { $0.notDownloaded = [] }
        let report = try await a.sync()
        #expect(report.conflicts[SyncReport.treeID] == nil, "\(report.conflicts[SyncReport.treeID] ?? [])")
        let b = try await TestDevice("B", folder: folder.url)
        try await b.sync()
        #expect(try await b.store.pageSnapshots().map(\.title).sorted() == ["Erste", "Zweite"])
    }
}
