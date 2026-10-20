import Foundation
import QuillEditorCore
import QuillModel
import QuillSync
import Testing

/// Tippen im selben Block ohne Pause, während ein Abgleich läuft (Review Phase 11,
/// Befund 1): Auf Gerät A tippt der Nutzer, während der Sync die Änderung von Gerät B
/// in denselben Block schreibt. Danach haben beide Geräte beide Eingaben.
@MainActor
@Suite("Sync: Tippen während eines Abgleichs", .serialized)
struct SyncTypingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "QuillSyncTypingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func device(_ name: String) async throws -> (store: PageStore, engine: SyncEngine) {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await store.setSyncDeviceID(UUID())
        return (store, SyncEngine(store: store, folder: folder, gate: SyncGate(), deviceName: name))
    }

    @Test func typingWhileTheSyncWritesTheSameBlockKeepsBoth() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = try await device("A"), b = try await device("B")
        let page = try await a.store.createPage(title: "Notiz")
        let block = EditorBlock(text: "Mitte")
        let bridge = EditorPersistenceBridge(pageID: page, store: a.store, delay: .seconds(60))
        bridge.onExternalChange = { _ in true }
        _ = try await bridge.load()
        bridge.documentDidChange(EditorDocument(blocks: [block]))
        await bridge.flush()
        let folderID = try await a.engine.sync(connectedFolderID: nil).folderID
        _ = try await b.engine.sync(connectedFolderID: folderID)

        // A tippt (noch nicht gespeichert), B ändert denselben Block, A gleicht ab.
        var typed = block
        typed.text = "Mitte BBB"
        bridge.documentDidChange(EditorDocument(blocks: [typed]))
        var fromB = block
        fromB.text = "AAA Mitte"
        try await b.store.applyEdits(page, BlockEdits(upserts: [fromB.snapshot]))
        _ = try await b.engine.sync(connectedFolderID: folderID)
        _ = try await a.engine.sync(connectedFolderID: folderID)
        #expect(try await a.store.blocks(of: page).map(\.text) == ["AAA Mitte"])

        // Jetzt speichert A: zusammengeführt, nicht überschrieben.
        #expect(await bridge.flush())
        for _ in 0..<2 {
            _ = try await a.engine.sync(connectedFolderID: folderID)
            _ = try await b.engine.sync(connectedFolderID: folderID)
        }
        for (name, store) in [("A", a.store), ("B", b.store)] {
            #expect(try await store.blocks(of: page).map(\.text) == ["AAA Mitte BBB"], "\(name)")
        }
    }
}
