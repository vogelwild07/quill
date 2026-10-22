import Foundation
import QuillEditorCore
@testable import QuillFeatures
import QuillModel
import QuillSync
import Testing

/// Speichern im Editor → Geschichte (12.1, ADR-031). Store nur im Arbeitsspeicher.
@MainActor
@Suite("Geschichte: Speichern im Editor")
struct HistoryObserverTests {
    @Test func savesFromTheEditorAreRecordedAndSyncReloadsAreNot() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let page = try await store.createPage(title: "Notiz")
        let observer = HistoryObserver(recorder: HistoryRecorder(store: store))
        observer.start()

        // Neuladen nach einem Abgleich: ohne Absender, keine Änderung des Nutzers.
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: UUID(), text: "Vom Abgleich")]))
        NotificationCenter.default.post(name: EditorPersistenceBridge.didSave, object: nil, userInfo: ["pageID": page])
        await observer.flush()
        #expect(try await store.syncPage(page)?.document == nil)

        let bridge = EditorPersistenceBridge(pageID: page, store: store)
        var document = try await bridge.load()
        document.blocks[0].text = "Getippt"
        bridge.documentDidChange(document)
        #expect(await bridge.flush())
        // Beim Beenden: Es wartet noch etwas, also erst aufzeichnen.
        #expect(observer.hasUnrecordedSaves)
        await observer.flush()
        #expect(observer.hasUnrecordedSaves == false)
        let data = try #require(try await store.syncPage(page)?.document)
        #expect(try PageDocument(bytes: data).blocks().map(\.text) == ["Getippt"])
    }
}
