import CryptoKit
import Foundation
@testable import QuillFeatures
import QuillModel
import QuillSync
import SwiftData
import Testing

/// Ein- und Ausschalten des Sync (ADR-029): aus, bis der Nutzer einschaltet; Backup
/// vorher, getesteter Rückweg; „Sync pausieren“; Backup einspielen bei eingeschaltetem
/// Sync. Stores und Ordner nur im temporären Ordner, Einstellungen in eigener Domain.
@MainActor
@Suite("Sync: einschalten, pausieren, Rückweg", .serialized)
final class SyncControllerTests {
    let name = "QuillSyncControllerTests-\(UUID().uuidString)"
    let suite = "QuillSyncControllerTests-\(UUID().uuidString)"
    let directory: URL
    var syncFolder: URL { directory.appending(path: "Sync", directoryHint: .isDirectory) }
    var backupsFolder: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }
    let settings: SyncSettings

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        settings = SyncSettings(storage: try #require(UserDefaults(suiteName: suite)))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func open() throws -> QuillPersistence {
        try QuillPersistence.open(arguments: ["Quill", "-QuillStoreDirectory", name]) { _, _ in .migrate }
    }

    func controller(_ persistence: QuillPersistence, changed: ((Set<UUID>) -> Void)? = nil) -> SyncController {
        SyncController(
            store: persistence.store, settings: settings, backupBeforeSync: { try await persistence.backupBeforeSync() },
            deviceName: "Test", onPagesChanged: { changed?($0) }
        )
    }

    /// Dateien im Sync-Ordner mit Pfad ab dort, z. B. `/Quill/quill.json`.
    func folderFiles(_ folder: URL? = nil) -> Set<String> {
        Set(folderContents(folder).keys)
    }

    /// Pfad → Inhalt aller Dateien im Ordner (Standard: `syncFolder`).
    func folderContents(_ folder: URL? = nil) -> [String: Data] {
        let folder = folder ?? syncFolder
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        let base = folder.resolvingSymlinksInPath().path(percentEncoded: false)
        var result: [String: Data] = [:]
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            let path = "/" + String(url.resolvingSymlinksInPath().path(percentEncoded: false).dropFirst(base.count)).trimmingPrefix("/")
            result[path] = try? Data(contentsOf: url)
        }
        return result
    }

    func makeFolder(_ name: String) throws -> URL {
        let folder = directory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Ein frisches Gerät im Ordner: Was es nach dem Abgleich hat, steht vollständig im Ordner.
    func freshDevice(in folder: URL, folderID: UUID) async throws -> PageStore {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await store.setSyncDeviceID(UUID())
        _ = try await SyncEngine(store: store, folder: folder, gate: SyncGate(), deviceName: "Frisch").sync(connectedFolderID: folderID)
        return store
    }

    /// Eine Seite mit einem Absatz.
    @discardableResult
    func createPage(_ store: PageStore, title: String, text: String) async throws -> UUID {
        let page = try await store.createPage(title: title)
        let block = BlockSnapshot(id: UUID(), text: text)
        try await store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        return page
    }

    func backups(_ kind: StoreBackup.Kind) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: backupsFolder.path(percentEncoded: false))) ?? [])
            .filter { StoreBackup.entry(at: URL(filePath: $0))?.kind == kind }
    }

    @Test func syncIsOffUntilTheUserTurnsItOn() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        #expect(!sync.isEnabled)
        #expect(sync.status == .off)
        await sync.syncNow()
        #expect(folderFiles().isEmpty)
        #expect(try await persistence.store.syncState().deviceID == nil)
    }

    @Test func enablingBacksUpFirstThenConnects() async throws {
        let persistence = try open()
        try await persistence.store.createPage(title: "Vorher")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        let backup = try #require(try await sync.enable(folder: syncFolder))
        #expect(backup.lastPathComponent.hasSuffix("_vor-sync"))
        #expect(sync.isEnabled && sync.status == .idle)
        #expect(try await persistence.store.syncState().deviceID != nil)
        // Erst der Abgleich beschreibt den Ordner.
        #expect(folderFiles().isEmpty)
        await sync.syncNow()
        #expect(sync.status == .idle)
        #expect(folderFiles().contains("/Quill/quill.json"))
        #expect(settings.connection?.folderID == sync.lastReport?.folderID)
    }

    @Test func failedBackupKeepsSyncOff() async throws {
        let persistence = try open()
        struct BackupFailed: Error {}
        let sync = SyncController(
            store: persistence.store, settings: settings, backupBeforeSync: { throw BackupFailed() }, deviceName: "Test"
        )
        await #expect(throws: BackupFailed.self) { try await sync.enable(folder: self.syncFolder) }
        #expect(!sync.isEnabled)
        #expect(settings.connection == nil)
        #expect(try await persistence.store.syncState().deviceID == nil)
    }

    @Test func wayBackTurnsOffAndRestoresTheStateBeforeSync() async throws {
        var persistence: QuillPersistence? = try open()
        let page = try await persistence!.store.createPage(title: "Vorher")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence!)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        try await persistence!.store.rename(page, to: "Mit Sync")

        // Ausschalten lässt Store und Ordner, wie sie sind.
        let folderBefore = folderFiles()
        sync.disable()
        #expect(sync.status == .off && settings.connection == nil)
        await sync.syncNow()
        #expect(folderFiles() == folderBefore)
        #expect(try await persistence!.store.pageSnapshots().map(\.title) == ["Mit Sync"])

        // Das Backup vor dem Sync einspielen: Stand von vorher, ohne Geräte-ID, Sync aus.
        let entry = try #require(try await persistence!.backupEntries().first { $0.entry.kind == .beforeSync })
        try await persistence!.requestRestore(entry.entry)
        persistence = nil
        let restored = try open()
        #expect(try await restored.store.pageSnapshots().map(\.title) == ["Vorher"])
        #expect(try await restored.store.syncState() == SyncStoreState(deviceID: nil, tree: nil, cursors: nil))
        #expect(!controller(restored).isEnabled)
    }

    @Test func pauseStopsWritingAndResumeCatchesUp() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        try await persistence.store.createPage(title: "Während der Pause")
        sync.pause()
        #expect(sync.status == .paused && settings.connection?.isPaused == true)
        let before = folderFiles()
        await sync.syncNow()
        #expect(folderFiles() == before)
        // Pausiert bleibt pausiert, auch nach einem Neustart.
        #expect(controller(persistence).status == .paused)
        sync.resume()
        await sync.syncNow()
        #expect(folderFiles().count > before.count)
        #expect(sync.status == .idle)
    }

    @Test func pausingStopsARunningSyncAtOnce() async throws {
        let persistence = try open()
        for index in 1...3 {
            let page = try await persistence.store.createPage(title: "Seite \(index)")
            let block = BlockSnapshot(id: UUID(), text: "Text")
            try await persistence.store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        }
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let files = HookedFileAccess()
        let sync = SyncController(
            store: persistence.store, settings: settings, backupBeforeSync: { nil }, deviceName: "Test", files: files
        )
        try await sync.enable(folder: syncFolder)
        // Nach der ersten Seiten-Datei pausiert der Nutzer, während der Abgleich läuft.
        files.onCreate.withLock { hook in
            hook = { url in
                guard url.path(percentEncoded: false).contains("/pages/") else { return }
                DispatchQueue.main.sync { MainActor.assumeIsolated { sync.pause() } }
            }
        }
        await sync.syncNow()
        #expect(sync.status == .paused)
        #expect(folderFiles().filter { $0.contains("/pages/") }.count == 1)
    }

    @Test func restoringABackupTurnsSyncOffAndReconnectsAsNewDevice() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        #expect(!sync.turnOffForRestore())
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let firstDevice = try #require(try await persistence.store.syncState().deviceID)
        #expect(sync.turnOffForRestore())
        #expect(!sync.isEnabled && settings.askAfterRestore)
        // Als neues Gerät wieder verbinden.
        try await sync.enable(folder: syncFolder)
        #expect(!settings.askAfterRestore)
        #expect(try await persistence.store.syncState().deviceID != firstDevice)
    }

    @Test func existingQuillFolderNeedsConfirmationAndChangesReachOpenEditors() async throws {
        // Ein anderes Gerät hat den Ordner schon eingerichtet.
        let other = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await other.setSyncDeviceID(UUID())
        let page = try await other.createPage(title: "Vom anderen Mac")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let otherReport = try await SyncEngine(store: other, folder: syncFolder, gate: SyncGate(), deviceName: "Anderer")
            .sync(connectedFolderID: nil)

        let persistence = try open()
        var changed: Set<UUID> = []
        let sync = controller(persistence) { changed.formUnion($0) }
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        #expect(sync.status == .needsConfirmation(otherReport.folderID))
        #expect(try await persistence.store.pageSnapshots().isEmpty)
        await sync.confirmFolder(otherReport.folderID)
        #expect(sync.status == .idle)
        #expect(try await persistence.store.pageSnapshots().map(\.title) == ["Vom anderen Mac"])
        #expect(changed.contains(page))
    }

    // MARK: Konflikte (11.6)

    @Test func choosingAVersionNeedsSyncOnAndResolvesEverywhere() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        let page = try await persistence.store.createPage(title: "Notiz")
        await sync.syncNow()
        let folderID = try #require(settings.connection?.folderID)
        let other = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await other.setSyncDeviceID(UUID())
        let otherEngine = SyncEngine(store: other, folder: syncFolder, gate: SyncGate(), deviceName: "Anderer")
        _ = try await otherEngine.sync(connectedFolderID: folderID)
        try await persistence.store.rename(page, to: "Notiz hier")
        try await other.rename(page, to: "Notiz dort")
        await sync.syncNow()
        _ = try await otherEngine.sync(connectedFolderID: folderID)
        await sync.syncNow()

        let conflict = try #require(sync.conflicts(onPage: page).first)
        #expect(conflict.isPageField && conflict.conflict.field == "title")
        #expect(sync.pagesWithConflicts == [page])
        let devices = Dictionary(uniqueKeysWithValues: conflict.conflict.versions.map { ($0.value, sync.deviceName($0.device)) })
        #expect(devices == ["Notiz hier": "Test", "Notiz dort": "Anderer"])
        #expect(sync.deviceName(nil) == "Unknown Device")
        let theirs = try #require(conflict.conflict.versions.first { $0.value == "Notiz dort" })

        // Pausiert: keine Wahl, nichts im Ordner.
        sync.pause()
        #expect(!sync.canChoose)
        let before = folderContents()
        await sync.choose(conflict.choice(theirs))
        #expect(folderContents() == before)
        #expect(sync.conflicts(onPage: page) == [conflict])

        sync.resume()
        #expect(sync.canChoose)
        await sync.choose(conflict.choice(theirs))
        #expect(sync.conflicts(onPage: page).isEmpty)
        #expect(sync.pagesWithConflicts.isEmpty)
        #expect(try await persistence.store.pageSnapshots().first { $0.id == page }?.title == "Notiz dort")
        let report = try await otherEngine.sync(connectedFolderID: folderID)
        #expect(report.conflicts.isEmpty)
        #expect(try await other.pageSnapshots().first { $0.id == page }?.title == "Notiz dort")
    }

    @Test func choiceDuringARunningSyncStaysHidden() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let files = HookedFileAccess()
        let sync = SyncController(
            store: persistence.store, settings: settings, backupBeforeSync: { nil }, deviceName: "Test", files: files
        )
        try await sync.enable(folder: syncFolder)
        let page = try await persistence.store.createPage(title: "Notiz")
        await sync.syncNow()
        let folderID = try #require(settings.connection?.folderID)
        let other = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await other.setSyncDeviceID(UUID())
        let otherEngine = SyncEngine(store: other, folder: syncFolder, gate: SyncGate(), deviceName: "Anderer")
        _ = try await otherEngine.sync(connectedFolderID: folderID)
        try await persistence.store.rename(page, to: "Notiz hier")
        try await other.rename(page, to: "Notiz dort")
        await sync.syncNow()
        _ = try await otherEngine.sync(connectedFolderID: folderID)
        await sync.syncNow()
        let conflict = try #require(sync.conflicts(onPage: page).first)
        let theirs = try #require(conflict.conflict.versions.first { $0.value == "Notiz dort" })

        // Der Nutzer wählt, während ein Abgleich läuft, der die Wahl noch nicht kennt.
        let block = BlockSnapshot(id: UUID(), text: "Neu")
        try await persistence.store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))
        files.onCreate.withLock { hook in
            hook = { url in
                guard url.path(percentEncoded: false).contains("/pages/") else { return }
                files.onCreate.withLock { $0 = nil }
                DispatchQueue.main.sync { MainActor.assumeIsolated { sync.remember(conflict.choice(theirs)) } }
            }
        }
        await sync.syncNow()
        #expect(sync.conflicts(onPage: page).isEmpty)
        await sync.syncNow()
        #expect(sync.conflicts(onPage: page).isEmpty)
        #expect(try await persistence.store.pageSnapshots().first { $0.id == page }?.title == "Notiz dort")
    }

    @Test func conflictsShowAfterRestartWhilePausedWithoutWriting() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        let page = try await createPage(persistence.store, title: "Notiz", text: "Text")
        await sync.syncNow()
        let folderID = try #require(settings.connection?.folderID)
        let other = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await other.setSyncDeviceID(UUID())
        let otherEngine = SyncEngine(store: other, folder: syncFolder, gate: SyncGate(), deviceName: "Anderer")
        _ = try await otherEngine.sync(connectedFolderID: folderID)
        try await persistence.store.rename(page, to: "Notiz hier")
        try await other.rename(page, to: "Notiz dort")
        await sync.syncNow()
        _ = try await otherEngine.sync(connectedFolderID: folderID)
        await sync.syncNow()
        let expected = sync.conflicts(onPage: page)
        #expect(expected.count == 1)
        sync.pause()

        // Neustart, weiter pausiert: Konflikte aus dem Store, Ordner und Store unverändert.
        let folder = folderContents()
        let state = try await persistence.store.syncState()
        let document = try await persistence.store.syncPage(page)?.document
        let pages = try await persistence.store.pageSnapshots()
        let restarted = controller(persistence)
        #expect(restarted.status == .paused && restarted.conflicts(onPage: page).isEmpty)
        restarted.start()
        for _ in 0..<100 where restarted.conflicts(onPage: page).isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(restarted.conflicts(onPage: page) == expected)
        #expect(restarted.pagesWithConflicts == [page])
        let devices = Set(expected[0].conflict.versions.map { restarted.deviceName($0.device) })
        #expect(devices == ["Test", "Anderer"])
        #expect(!restarted.canChoose)
        #expect(restarted.lastSyncDate == nil)
        #expect(folderContents() == folder)
        #expect(try await persistence.store.syncState() == state)
        #expect(try await persistence.store.syncPage(page)?.document == document)
        #expect(try await persistence.store.pageSnapshots() == pages)
    }

    // MARK: Wiederverbinden (11.4)

    @Test func sameFolderAfterTurningOffMergesWithoutAsking() async throws {
        let persistence = try open()
        let page = try await createPage(persistence.store, title: "Seite", text: "Text")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let folderID = try #require(settings.connection?.folderID)
        sync.disable()
        #expect(settings.previousConnection?.folderID == folderID)

        try await sync.enable(folder: syncFolder)
        #expect(settings.connection?.folderID == folderID)
        // Dokumente bleiben: Ihre Geschichte steht in diesem Ordner.
        #expect(try await persistence.store.syncPage(page)?.document != nil)
        await sync.syncNow()
        #expect(sync.status == .idle)
    }

    @Test func otherFolderStartsOverWithTheWholeHistory() async throws {
        let persistence = try open()
        let page = try await createPage(persistence.store, title: "Seite", text: "Vorher")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let old = try await pageVersion(persistence.store, page)
        try await persistence.store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: try #require(try await persistence.store.blocks(of: page).first?.id), text: "Nachher")]))
        await sync.syncNow()
        sync.disable()

        let other = try makeFolder("Anderer")
        try await sync.enable(folder: other)
        #expect(settings.connection?.folderID == nil)
        await sync.syncNow()
        #expect(sync.status == .idle)
        // Ein neues Gerät im neuen Ordner bekommt alles, ohne den alten Ordner.
        let fresh = try await freshDevice(in: other, folderID: try #require(settings.connection?.folderID))
        #expect(try await fresh.pageSnapshots().map(\.title) == ["Seite"])
        #expect(try await fresh.blocks(of: page).map(\.text) == ["Nachher"])
        // Mit Geschichte: Der Stand aus dem alten Ordner ist abrufbar.
        let document = try PageDocument(bytes: #require(try await fresh.syncPage(page)?.document))
        #expect(try document.blocks(at: old).map(\.text) == ["Vorher"])
    }

    @Test func reconnectAfterRestoreMergesWithoutOverwriting() async throws {
        let persistence = try open()
        let page = try await createPage(persistence.store, title: "Seite", text: "Text")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let document = try await persistence.store.syncPage(page)?.document
        #expect(sync.turnOffForRestore())
        #expect(sync.asksToReconnect)
        let before = folderContents()

        try await persistence.store.createPage(title: "Nach dem Backup")
        try await sync.reconnect(.merge)
        #expect(!sync.asksToReconnect)
        // Die Dokumente bleiben: Neue Objekte für dieselben Blöcke ergäben Konflikte.
        #expect(try await persistence.store.syncPage(page)?.document == document)
        await sync.syncNow()
        #expect(sync.status == .idle)
        // Nur angehängt: Jede Datei von vorher ist unverändert da.
        let after = folderContents()
        for (path, data) in before where !path.hasPrefix("/Quill/devices/") {
            #expect(after[path] == data, "\(path)")
        }
        #expect(after.count > before.count)
    }

    @Test func startOverNeedsAnEmptyNewFolderAndLeavesTheOldOneAlone() async throws {
        let persistence = try open()
        let page = try await createPage(persistence.store, title: "Seite", text: "Text")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let old = try await pageVersion(persistence.store, page)
        try await persistence.store.applyEdits(page, BlockEdits(upserts: [BlockSnapshot(id: try #require(try await persistence.store.blocks(of: page).first?.id), text: "Neuer")]))
        await sync.syncNow()
        sync.turnOffForRestore()
        let before = folderContents()

        await #expect(throws: SyncController.EnableError.sameAsPreviousFolder) { try await sync.reconnect(.startOver(self.syncFolder)) }
        let used = try makeFolder("Belegt")
        try FileManager.default.createDirectory(at: used.appending(path: "Quill/pages"), withIntermediateDirectories: true)
        await #expect(throws: SyncController.EnableError.folderNotEmpty) { try await sync.reconnect(.startOver(used)) }
        #expect(!sync.isEnabled && sync.asksToReconnect)

        let empty = try makeFolder("Neu")
        try await sync.reconnect(.startOver(empty))
        await sync.syncNow()
        #expect(sync.status == .idle)
        #expect(folderContents() == before)
        let fresh = try await freshDevice(in: empty, folderID: try #require(settings.connection?.folderID))
        #expect(try await fresh.blocks(of: page).map(\.text) == ["Neuer"])
        let document = try PageDocument(bytes: #require(try await fresh.syncPage(page)?.document))
        #expect(try document.blocks(at: old).map(\.text) == ["Text"])
    }

    func pageVersion(_ store: PageStore, _ page: UUID) async throws -> DocumentVersion {
        try PageDocument(bytes: #require(try await store.syncPage(page)?.document)).version
    }

    @Test func decliningKeepsSyncOffAndStopsAsking() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        sync.turnOffForRestore()
        // Ohne vorgemerktes Backup ändert Abbrechen des Beendens nichts mehr, nachdem
        // der Nutzer geantwortet hat.
        sync.declineReconnect()
        sync.cancelTurnOffForRestore()
        #expect(!sync.asksToReconnect && !sync.isEnabled && sync.status == .off)
        #expect(sync.previousFolder != nil)
    }

    // MARK: Zeitpunkte (11.4)

    @Test func changesAreSyncedSoonAfterSavingWithoutALoop() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = SyncController(
            store: persistence.store, settings: settings, backupBeforeSync: { nil }, deviceName: "Test",
            schedule: SyncSchedule(afterChange: .milliseconds(50), interval: .seconds(3600))
        )
        try await sync.enable(folder: syncFolder)
        sync.start()
        try await waitUntil { sync.completedRuns >= 1 }

        let page = try await createPage(persistence.store, title: "Neu", text: "Text")
        try await waitUntil { self.folderFiles().contains { $0.hasPrefix("/Quill/pages/\(page.uuidString)/") } }
        // Eigene Schreibvorgänge lösen keinen weiteren Abgleich aus.
        try await Task.sleep(for: .milliseconds(150))
        let runs = sync.completedRuns
        try await Task.sleep(for: .milliseconds(500))
        #expect(sync.completedRuns == runs)

        // Pausiert: Änderungen lösen nichts aus.
        sync.pause()
        try await createPage(persistence.store, title: "Pausiert", text: "Text")
        try await Task.sleep(for: .milliseconds(300))
        #expect(sync.completedRuns == runs)
    }

    @Test func secondRequestReturnsOnlyAfterTheRunningSync() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let files = HookedFileAccess()
        // Jede neue Datei dauert etwas, damit der zweite Aufruf in den ersten fällt.
        files.onCreate.withLock { $0 = { _ in Thread.sleep(forTimeInterval: 0.05) } }
        let sync = SyncController(store: persistence.store, settings: settings, backupBeforeSync: { nil }, deviceName: "Test", files: files)
        try await sync.enable(folder: syncFolder)
        for index in 1...3 { try await createPage(persistence.store, title: "Seite \(index)", text: "Text") }

        let first = Task { await sync.syncNow() }
        try await waitUntil { sync.isSyncing }
        await sync.syncNow()
        // Zurück erst, wenn der laufende Abgleich fertig ist.
        #expect(!sync.isSyncing)
        #expect(sync.status == .idle)
        #expect(folderFiles().filter { $0.hasPrefix("/Quill/pages/") }.count == 3)
        await first.value
    }

    func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Zeit abgelaufen")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Befunde aus dem Review von Phase 11

    /// Ein fremder Ordner, dem der Nutzer nicht zustimmt, verdrängt den bisherigen
    /// nicht: Wieder gewählt, führt Quill dort zusammen, ohne Rückfrage und ohne den
    /// ganzen Stand erneut zu schreiben.
    @Test func declinedForeignFolderKeepsThePreviousOne() async throws {
        let persistence = try open()
        try await createPage(persistence.store, title: "Seite", text: "Text")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let folderID = try #require(settings.connection?.folderID)
        sync.disable()
        let cursors = try await persistence.store.syncState().cursors
        // Jedes Einschalten ist ein neues Gerät (eigene Datei unter `devices/`); sonst bleibt alles.
        func withoutDevices() -> [String: Data] { folderContents().filter { !$0.key.contains("/devices/") } }
        let filesBefore = withoutDevices()

        // Ein Ordner mit Daten eines anderen Bestands: Rückfrage, dann „Sync ausschalten“.
        let foreign = try makeFolder("Fremd")
        let other = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await other.setSyncDeviceID(UUID())
        try await other.createPage(title: "Fremd")
        let foreignID = try await SyncEngine(store: other, folder: foreign, gate: SyncGate(), deviceName: "Anderer")
            .sync(connectedFolderID: nil).folderID
        try await sync.enable(folder: foreign)
        await sync.syncNow()
        #expect(sync.status == .needsConfirmation(foreignID))
        sync.disable()
        #expect(settings.previousConnection?.folderID == folderID)
        #expect(try await persistence.store.syncState().cursors == cursors)

        try await sync.enable(folder: syncFolder)
        #expect(settings.connection?.folderID == folderID)
        await sync.syncNow()
        #expect(sync.status == .idle)
        #expect(withoutDevices() == filesBefore)
    }

    /// Zustimmung zu einem Ordner mit fremden Daten, nachdem schon ein anderer verbunden
    /// war: Die gelesenen Nummern des bisherigen gelten dort nicht; jedes Dokument kommt
    /// als ganzer Stand in den Ordner, und ein neues Gerät dort bekommt alles.
    @Test func confirmedForeignFolderGetsTheWholeState() async throws {
        let persistence = try open()
        let page = try await createPage(persistence.store, title: "Seite", text: "Vorher")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = controller(persistence)
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        sync.disable()

        let foreign = try makeFolder("Fremd")
        let other = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        try await other.setSyncDeviceID(UUID())
        try await other.createPage(title: "Fremd")
        let foreignID = try await SyncEngine(store: other, folder: foreign, gate: SyncGate(), deviceName: "Anderer")
            .sync(connectedFolderID: nil).folderID
        try await sync.enable(folder: foreign)
        await sync.syncNow()
        await sync.confirmFolder(foreignID)
        #expect(sync.status == .idle)

        let fresh = try await freshDevice(in: foreign, folderID: foreignID)
        #expect(try await fresh.blocks(of: page).map(\.text) == ["Vorher"])
        #expect(Set(try await fresh.pageSnapshots().map(\.title)) == ["Seite", "Fremd"])
    }

    /// Umschalten auf einen anderen Ordner, während ein Abgleich läuft: Der alte Lauf
    /// endet vorher; er schreibt nicht weiter in den alten Ordner und überschreibt die
    /// zurückgesetzten gelesenen Dateien nicht, und der neue Ordner bekommt alles ganz.
    @Test func switchingFoldersWaitsForTheRunningSync() async throws {
        let persistence = try open()
        var pages: [UUID] = []
        for index in 1...4 { pages.append(try await createPage(persistence.store, title: "Seite \(index)", text: "Text \(index)")) }
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let files = HookedFileAccess()
        let sync = SyncController(store: persistence.store, settings: settings, backupBeforeSync: { nil }, deviceName: "Test", files: files)
        try await sync.enable(folder: syncFolder)
        // Jede Seiten-Datei im alten Ordner dauert, damit das Umschalten hineinfällt.
        files.onCreate.withLock { hook in
            hook = { url in
                if url.path(percentEncoded: false).contains("/Sync/Quill/pages/") { Thread.sleep(forTimeInterval: 0.2) }
            }
        }
        let first = Task { await sync.syncNow() }
        try await waitUntil { self.folderFiles().contains { $0.contains("/pages/") } || sync.isSyncing }
        try await Task.sleep(for: .milliseconds(50))
        sync.disable()
        let newFolder = try makeFolder("Neu")
        try await sync.enable(folder: newFolder)
        await first.value
        // Höchstens die Datei, die beim Ausschalten schon geschrieben wurde.
        #expect(folderFiles().filter { $0.contains("/pages/") }.count <= 1)

        await sync.syncNow()
        #expect(sync.status == .idle)
        let folderID = try #require(settings.connection?.folderID)
        let fresh = try await freshDevice(in: newFolder, folderID: folderID)
        for (index, page) in pages.enumerated() {
            #expect(try await fresh.blocks(of: page).map(\.text) == ["Text \(index + 1)"])
        }
    }

    /// Ausgeschaltet, während ein Abgleich gerade noch fertig wird: danach „aus“, nicht „pausiert“.
    @Test func turningOffDuringASyncEndsOff() async throws {
        let persistence = try open()
        try await createPage(persistence.store, title: "Seite", text: "Text")
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let files = HookedFileAccess()
        let sync = SyncController(store: persistence.store, settings: settings, backupBeforeSync: { nil }, deviceName: "Test", files: files)
        try await sync.enable(folder: syncFolder)
        // Die Datei des Seitenbaums ist die letzte, die der Abgleich schreibt.
        files.onCreate.withLock { hook in
            hook = { url in
                guard url.path(percentEncoded: false).contains("/tree/") else { return }
                DispatchQueue.main.sync { MainActor.assumeIsolated { sync.disable() } }
            }
        }
        await sync.syncNow()
        #expect(sync.status == .off)
        #expect(!sync.isEnabled)
    }

    /// Backup einspielen: Der Sync ist schon aus, wenn das Backup vorgemerkt wird;
    /// scheitert das Vormerken, läuft er weiter wie vorher.
    @Test func restoreRequestTurnsSyncOffFirst() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = persistence.sync
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let entry = try #require(try await persistence.backupEntries().first?.entry)

        struct RequestFailed: Error {}
        await #expect(throws: RequestFailed.self) {
            try await persistence.requestRestore(entry) { _, _ in
                #expect(!sync.isEnabled, "Sync beim Vormerken noch an")
                throw RequestFailed()
            }
        }
        #expect(sync.isEnabled && !sync.asksToReconnect && sync.status == .idle)

        var requested = false
        try await persistence.requestRestore(entry) { _, _ in
            #expect(!sync.isEnabled, "Sync beim Vormerken noch an")
            requested = true
        }
        #expect(requested && !sync.isEnabled && sync.asksToReconnect)
    }

    // MARK: Anbindung an die App (11.4)

    @Test func cancelledQuitAfterRestoreRequestKeepsSyncAsBefore() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        let sync = persistence.sync
        try await sync.enable(folder: syncFolder)
        await sync.syncNow()
        let device = try await persistence.store.syncState().deviceID

        // Wie BackupRestoreView: vormerken (schaltet den Sync aus); dann bricht das Beenden ab.
        let entry = try #require(try await persistence.backupEntries().first?.entry)
        try await persistence.requestRestore(entry)
        #expect(!sync.isEnabled && sync.asksToReconnect)
        persistence.quitWasCancelled { _, _ in }

        #expect(sync.isEnabled && !sync.asksToReconnect && sync.status == .idle)
        #expect(try await persistence.store.syncState().deviceID == device)
        await sync.syncNow()
        #expect(sync.status == .idle)
    }

    @Test func testStoresKeepSyncSettingsAwayFromTheMac() async throws {
        let persistence = try open()
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)
        try await persistence.sync.enable(folder: syncFolder)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "sync-settings.json").path(percentEncoded: false)))
        #expect(UserDefaults.standard.data(forKey: SyncSettings.connectionKey) == nil)
        // Über einen Neustart bleibt er an.
        #expect(try open().sync.isEnabled)

        let inMemory = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES"]) { _, _ in .migrate }
        #expect(!inMemory.sync.isEnabled)
        try await inMemory.sync.enable(folder: syncFolder)
        #expect(UserDefaults.standard.data(forKey: SyncSettings.connectionKey) == nil)
    }

    @Test func syncTestFolderOnlyWithATestStore() throws {
        let name = "QuillSyncTestFolder-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: name)) }
        let persistence = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillSyncTestFolder", name]) { _, _ in .migrate }
        #expect(persistence.syncTestFolder?.lastPathComponent == name)
        let unsafe = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillSyncTestFolder", "../x"]) { _, _ in .migrate }
        #expect(unsafe.syncTestFolder == nil)
    }

    /// Speichert der Store abseits des Main Threads (Abgleich, `HistoryRecorder`), während
    /// der Main Thread auf den Store wartet, darf die Meldung den Store nicht anhalten:
    /// Sonst warten beide aufeinander (ADR-031). Hier blockiert der Test den Main Thread.
    @Test func storeSavesOffTheMainThreadDoNotWaitForIt() throws {
        let persistence = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES"]) { _, _ in .migrate }
        let sync = controller(persistence)
        sync.start()
        let posted = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            NotificationCenter.default.post(name: ModelContext.didSave, object: nil)
            posted.signal()
        }
        #expect(posted.wait(timeout: .now() + 3) == .success)
    }
}
