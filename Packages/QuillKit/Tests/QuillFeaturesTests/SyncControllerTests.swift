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
        settings = SyncSettings(defaults: try #require(UserDefaults(suiteName: suite)))
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
    func folderFiles() -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: syncFolder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let base = syncFolder.resolvingSymlinksInPath().path(percentEncoded: false)
        var result: Set<String> = []
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            result.insert("/" + String(url.resolvingSymlinksInPath().path(percentEncoded: false).dropFirst(base.count)).trimmingPrefix("/"))
        }
        return result
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
}
