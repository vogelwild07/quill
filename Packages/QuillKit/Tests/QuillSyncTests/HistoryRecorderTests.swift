import Foundation
import QuillModel
@testable import QuillSync
import Testing

/// Geschichte aufzeichnen (12.1, ADR-031): mit und ohne Sync, zusammen mit dem Abgleich.
/// Nur Stores im Arbeitsspeicher und Wegwerf-Ordner.
@Suite("Geschichte aufzeichnen")
struct HistoryRecorderTests {
    private func document(_ store: PageStore, _ page: UUID) async throws -> PageDocument {
        try PageDocument(bytes: #require(try await store.syncPage(page)?.document))
    }


    private func setText(_ store: PageStore, _ page: UUID, _ block: UUID, _ text: String) async throws {
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: text)]))
    }

    // MARK: Ohne Sync

    @Test func recordsEachSavedStateWithoutSync() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let recorder = HistoryRecorder(store: store)
        let page = try await store.createPage(title: "Notiz")
        let block = UUID()
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: "Eins")], order: [block]))
        #expect(try await recorder.record(page))
        try await setText(store, page, block, "Eins zwei")
        #expect(try await recorder.record(page))
        // Nichts Neues: keine Änderung.
        #expect(try await recorder.record(page) == false)

        let document = try await document(store, page)
        #expect(try document.blocks().map(\.text) == ["Eins zwei"])
        let authors = document.changeAuthors
        #expect(authors.count == 2)
        // Eine Sitzung je Seite, ohne Gerät (Sync nie eingeschaltet).
        #expect(Set(authors.map(\.actor)).count == 1)
        #expect(authors.allSatisfy { $0.device == nil })
        // Blöcke und `updatedAt` bleiben.
        #expect(try await store.blocks(of: page).map(\.text) == ["Eins zwei"])
    }

    @Test func sameSessionKeepsCountingAfterReloading() throws {
        let session = UUID(), device = UUID()
        let first = PageDocument()
        first.write(as: device, session: session)
        try first.update(to: [BlockSnapshot(id: UUID(), text: "A")])
        let second = try PageDocument(bytes: first.save())
        second.write(as: device, session: session)
        let block = try #require(try second.blocks().first)
        try second.update(to: [BlockSnapshot(id: block.id, text: "AB")])
        // Ein anderes Gerät übernimmt beides, ohne dass eine Änderung verloren geht.
        let other = PageDocument()
        try other.apply(changes: second.save())
        #expect(try other.blocks().map(\.text) == ["AB"])
        let authors = try PageDocument(bytes: other.save()).changeAuthors
        #expect(authors.count == 2 && Set(authors.map(\.actor)).count == 1)
        #expect(authors.allSatisfy { $0.device == device })
    }

    @Test func historyRecordedBeforeEnablingSyncReachesOtherDevices() async throws {
        let folder = try TestFolder()
        let b = try await TestDevice("B", folder: folder.url)
        // A noch ohne Sync: keine Geräte-ID.
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let recorder = HistoryRecorder(store: store)
        let page = try await store.createPage(title: "Notiz")
        let block = UUID()
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: "Offline")], order: [block]))
        #expect(try await recorder.record(page))
        try await setText(store, page, block, "Offline zwei")
        #expect(try await recorder.record(page))

        try await store.setSyncDeviceID(UUID())
        let engine = SyncEngine(store: store, folder: folder.url, gate: SyncGate(), deviceName: "A", files: TestFileAccess())
        let report = try await engine.sync(connectedFolderID: nil)
        b.files.connected = report.folderID
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Offline zwei"])
        // Auch die aufgezeichneten Stände, nicht nur der letzte.
        let onB = try await document(b.store, try await b.page(titled: "Notiz").id)
        let first = DocumentVersion(heads: [try await document(store, page).document.getHistory()[1]])
        #expect(try onB.blocks(at: first).map(\.text) == ["Offline"])
        #expect(onB.changeAuthors.prefix(2).allSatisfy { $0.device == nil })
    }

    // MARK: Mit Sync

    @Test func recordedHistoryGoesOutWithTheNextSync() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let recorder = HistoryRecorder(store: a.store)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Eins"])
        try await a.sync()
        try await b.sync()

        try await setText(a.store, page, blocks[0], "Eins zwei")
        #expect(try await recorder.record(page))
        try await a.sync()
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Eins zwei"])

        // Aufgezeichnet, danach noch einmal gespeichert: beides geht hinaus, nichts doppelt.
        try await setText(a.store, page, blocks[0], "Eins zwei drei")
        #expect(try await recorder.record(page))
        let added = BlockSnapshot(id: UUID(), text: "Neu")
        try await a.store.applyEdits(page, BlockEdits(upserts: [added], order: [blocks[0], added.id]))
        #expect(try await recorder.record(page))
        try await setText(a.store, page, added.id, "Neu vier")
        try await a.sync()
        let report = try await b.sync()
        #expect(report.conflicts[page] == nil)
        #expect(try await b.texts(of: "Notiz") == ["Eins zwei drei", "Neu vier"])
        #expect(try await a.sync().conflicts[page] == nil)
        #expect(try await a.texts(of: "Notiz") == ["Eins zwei drei", "Neu vier"])
    }

    @Test func recordingOnlyBetweenSyncsLeavesTheFolderComplete() async throws {
        // Aufgezeichnet, aber seit dem letzten Abgleich nichts mehr gespeichert: Der nächste
        // Abgleich hat keine Änderung gegenüber dem Store, schreibt die Aufzeichnung aber
        // trotzdem hinaus.
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let recorder = HistoryRecorder(store: a.store)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Eins"])
        try await a.sync()
        try await b.sync()
        try await setText(a.store, page, blocks[0], "Eins zwei")
        #expect(try await recorder.record(page))
        let before = try folder.files()
        try await a.sync()
        #expect(try folder.files().count == before.count + 1)
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Eins zwei"])
        // Danach nichts mehr offen: kein weiterer Abgleich schreibt.
        let after = try folder.fingerprint()
        try await a.sync()
        #expect(try folder.fingerprint() == after)
    }

    /// Abgleich schreibt die eigene Datei und bricht vor dem Store ab (z. B. Absturz).
    private func abortAfterOwnFile(_ device: TestDevice) async throws {
        device.files.state.withLock { state in
            state.onCreate = { url in
                guard url.path().contains("/pages/") else { return }
                device.files.state.withLock { $0.onContents = { _ in throw CocoaError(.fileReadUnknown) } }
            }
        }
        await #expect(throws: CocoaError.self) { try await device.sync() }
        device.files.state.withLock {
            $0.onCreate = nil
            $0.onContents = nil
        }
    }

    @Test func recorderWaitsWhileTheStoreIsBehindTheFolder() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let recorder = HistoryRecorder(store: a.store)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Anfang"])
        try await a.sync()
        try await b.sync()
        let stored = try #require(try await a.store.syncPage(page)?.document)

        let added = BlockSnapshot(id: UUID(), text: "Neu")
        try await a.store.applyEdits(page, BlockEdits(upserts: [added], order: [blocks[0], added.id]))
        try await abortAfterOwnFile(a)
        #expect(SyncCursors(data: try await a.store.syncState().cursors).pending == [page.uuidString])
        // Die Aufzeichnung enthielte den neuen Block ein zweites Mal.
        #expect(try await recorder.record(page) == false)
        #expect(try await a.store.syncPage(page)?.document == stored)

        let report = try await a.sync()
        #expect(report.conflicts[page] == nil)
        #expect(SyncCursors(data: try await a.store.syncState().cursors).pending.isEmpty)
        try await setText(a.store, page, added.id, "Neu danach")
        #expect(try await recorder.record(page))
        try await a.sync()
        #expect(try await b.sync().conflicts[page] == nil)
        #expect(try await b.texts(of: "Notiz") == ["Anfang", "Neu danach"])
    }

    @Test func pageInTheFolderWithoutKnownStateIsNotRecordedUntilTheNextSync() async throws {
        // Seiten, die vor 12.1 abgeglichen wurden, haben noch keinen Stand in
        // `SyncCursors.exported`.
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let b = try await TestDevice("B", folder: folder.url)
        let recorder = HistoryRecorder(store: a.store)
        let (page, blocks) = try await a.createPage("Notiz", texts: ["Eins"])
        try await a.sync()
        try await b.sync()
        var cursors = SyncCursors(data: try await a.store.syncState().cursors)
        cursors.exported = [:]
        try await a.store.saveSyncCursors(cursors.encoded())

        try await setText(a.store, page, blocks[0], "Eins zwei")
        #expect(try await recorder.record(page) == false)
        try await a.sync()
        try await setText(a.store, page, blocks[0], "Eins zwei drei")
        #expect(try await recorder.record(page))
        try await a.sync()
        try await b.sync()
        #expect(try await b.texts(of: "Notiz") == ["Eins zwei drei"])
    }

    @Test func recorderWaitsForARunningSyncOfThePage() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let recorder = HistoryRecorder(store: store)
        let page = try await store.createPage(title: "Notiz")
        let block = UUID()
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: "Eins")], order: [block]))
        // Wie ein laufender Abgleich der Seite.
        await DocumentLocks.shared.lock(page)
        let recording = Task { try await recorder.record(page) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await store.syncPage(page)?.document == nil)
        await DocumentLocks.shared.unlock(page)
        #expect(try await recording.value)
        #expect(try await store.syncPage(page)?.document != nil)
    }

    @Test func syncWaitsForARunningRecordingOfThePage() async throws {
        let folder = try TestFolder()
        let a = try await TestDevice("A", folder: folder.url)
        let (page, _) = try await a.createPage("Notiz", texts: ["Eins"])
        await DocumentLocks.shared.lock(page)
        let syncing = Task { try await a.sync() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(try folder.files().filter { $0.hasPrefix("pages/") }.isEmpty)
        await DocumentLocks.shared.unlock(page)
        _ = try await syncing.value
        #expect(try folder.files().filter { $0.hasPrefix("pages/") }.count == 1)
    }

    // MARK: Zeitpunkte

    @Test func recordsAfterAQuietPeriodAndOnFlush() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let recorder = HistoryRecorder(store: store, quietPeriod: .milliseconds(300), maxDelay: .seconds(30))
        let page = try await store.createPage(title: "Notiz")
        let block = UUID()
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: "Eins")], order: [block]))
        await recorder.pageSaved(page)
        #expect(recorder.hasWaitingPages)
        #expect(try await store.syncPage(page)?.document == nil)
        try await Task.sleep(for: .seconds(1.5))
        #expect(recorder.hasWaitingPages == false)
        #expect(try await document(store, page).blocks().map(\.text) == ["Eins"])

        try await setText(store, page, block, "Eins zwei")
        await recorder.pageSaved(page)
        await recorder.flush()
        #expect(recorder.hasWaitingPages == false)
        #expect(try await document(store, page).blocks().map(\.text) == ["Eins zwei"])
    }

    @Test func savingWithoutPauseStillRecordsAfterTheMaximumDelay() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let recorder = HistoryRecorder(store: store, quietPeriod: .seconds(1), maxDelay: .milliseconds(600))
        let page = try await store.createPage(title: "Notiz")
        let block = UUID()
        try await store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: block, text: "Eins")], order: [block]))
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(2.5) {
            await recorder.pageSaved(page)
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try await store.syncPage(page)?.document != nil)
    }
}
