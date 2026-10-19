import Foundation
import SQLite3
import SwiftData
import Testing
@testable import QuillModel

/// Backup wiederherstellen (ADR-019): Anfrage, Austausch beim Start, Rückweg.
@Suite(.serialized) struct StoreRestoreTests {
    let directory: URL
    let storeURL: URL
    let backupsURL: URL

    init() {
        directory = URL.temporaryDirectory.appending(path: "QuillRestoreTests-\(UUID().uuidString)")
        storeURL = directory.appending(path: "Store/Quill.store")
        backupsURL = directory.appending(path: "Backups")
    }

    private func backup(
        knownSchemas: [any VersionedSchema.Type] = QuillMigrationPlan.schemas,
        capacity: Int64? = nil,
        at date: Date = .now
    ) -> StoreBackup {
        StoreBackup(
            storeURL: storeURL, backupsURL: backupsURL, schemaVersion: "1.0.0",
            now: { date }, knownSchemas: knownSchemas, availableCapacity: { _ in capacity }
        )
    }

    // MARK: - Testdaten

    /// Legt Seiten an (eine mit extern gespeichertem Bild) und schließt den Container.
    private func addPages(_ titles: [String], imageBytes: UInt8? = nil) throws {
        let container = try QuillStore.makeContainer(storeURL: storeURL)
        let context = ModelContext(container)
        for title in titles {
            let page = Page(title: title)
            context.insert(page)
            if let imageBytes {
                let block = Block(kind: .image)
                block.page = page
                block.asset = Asset(data: Data(repeating: imageBytes, count: 300_000))
            }
        }
        try context.save()
    }

    private func titles() throws -> [String] {
        let container = try QuillStore.makeContainer(storeURL: storeURL)
        return try ModelContext(container).fetch(FetchDescriptor<Page>()).map(\.title).sorted()
    }

    private func imageBytes() throws -> [UInt8] {
        let container = try QuillStore.makeContainer(storeURL: storeURL)
        return try ModelContext(container).fetch(FetchDescriptor<Asset>()).compactMap { $0.data?.first }.sorted()
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func entry(_ url: URL, in backup: StoreBackup) throws -> StoreBackup.Entry {
        try #require(try backup.entries().first { $0.url.lastPathComponent == url.lastPathComponent })
    }

    /// Ändert einen Titel nur im WAL: Die Änderung steht danach nicht in `Quill.store`,
    /// sondern nur in `-wal`, und wird mit beiden Dateien und `-shm` nach `target` kopiert.
    private func copyWithChangeOnlyInWAL(from folder: URL, to target: URL, rename old: String, to new: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        // Auf einer Arbeitskopie: Beim Schließen schreibt SQLite den WAL zurück, die
        // Quelle bliebe sonst nicht unverändert.
        let work = directory.appending(path: "work-\(UUID().uuidString)")
        try fileManager.copyItem(at: folder, to: work)
        var db: OpaquePointer?
        let store = work.appending(path: "Quill.store")
        #expect(sqlite3_open_v2(store.path(percentEncoded: false), &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        for sql in ["PRAGMA journal_mode=WAL", "PRAGMA wal_autocheckpoint=0", "UPDATE ZPAGE SET ZTITLE='\(new)' WHERE ZTITLE='\(old)'"] {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
        }
        // Kopie bei offener Verbindung: Beim Schließen würde SQLite den WAL zurückschreiben.
        for name in try fileManager.contentsOfDirectory(atPath: work.path(percentEncoded: false)) {
            try fileManager.copyItem(at: work.appending(path: name), to: target.appending(path: name))
        }
    }

    // MARK: - Tests

    @Test func restoresBackupWithAssetsAndKeepsCurrentStateAsBackup() throws {
        try addPages(["Eins"], imageBytes: 1)
        let backup = backup()
        let saved = try backup.createBackup(reason: .quit)
        try addPages(["Zwei"], imageBytes: 2)
        #expect(try titles() == ["Eins", "Zwei"])

        try backup.requestRestore(try entry(saved, in: backup))
        #expect(backup.isRestorePending)

        guard case .restored(let name, let safetyName) = backup.applyPendingRestore() else {
            Issue.record("Nicht wiederhergestellt")
            return
        }
        #expect(name == saved.lastPathComponent)
        #expect(!backup.isRestorePending)
        #expect(!exists(backup.restoreJournalURL))
        #expect(try titles() == ["Eins"])
        #expect(try imageBytes() == [1], "Bilder aus .Quill_SUPPORT des Backups")
        #expect(backup.lastOpenedSchemaVersion == "1.0.0")

        // Der vorherige Stand erscheint in der Liste und lässt sich zurückholen.
        let safety = try #require(try backup.entries().first { $0.url.lastPathComponent == safetyName })
        #expect(safety.kind == .beforeRestore)
        try backup.requestRestore(safety)
        guard case .restored = backup.applyPendingRestore() else {
            Issue.record("Rückweg nicht wiederhergestellt")
            return
        }
        #expect(try titles() == ["Eins", "Zwei"])
        #expect(try imageBytes() == [1, 2])
    }

    /// Store, `-wal` und `-shm` reisen immer zusammen: beim Verschieben des aktuellen
    /// Stands und beim Kopieren aus dem Backup.
    @Test func storeMovesTogetherWithWALAndSHM() throws {
        try addPages(["Eins"])
        let backup = backup()
        let saved = try backup.createBackup(reason: .quit)

        // Backup, dessen letzte Änderung nur im WAL steht.
        let walBackup = backupsURL.appending(path: "2026-10-19T08-00-00Z_beenden")
        try copyWithChangeOnlyInWAL(from: saved, to: walBackup, rename: "Eins", to: "Nur im WAL")
        #expect(exists(walBackup.appending(path: "Quill.store-wal")))
        #expect(exists(walBackup.appending(path: "Quill.store-shm")))

        try backup.requestRestore(try entry(walBackup, in: backup))
        guard case .restored(_, let safetyName) = backup.applyPendingRestore() else {
            Issue.record("Nicht wiederhergestellt")
            return
        }
        #expect(try titles() == ["Nur im WAL"], "WAL nicht mitkopiert")

        // Jetzt ist der aktuelle Stand einer mit WAL; er muss vollständig in die Sicherung.
        let current = storeURL.deletingLastPathComponent()
        let walState = directory.appending(path: "walState")
        try copyWithChangeOnlyInWAL(from: current, to: walState, rename: "Nur im WAL", to: "Aktuell im WAL")
        for name in backup.databaseFileNames {
            try? FileManager.default.removeItem(at: current.appending(path: name))
            try FileManager.default.copyItem(at: walState.appending(path: name), to: current.appending(path: name))
        }
        try backup.requestRestore(try entry(saved, in: backup))
        guard case .restored(_, let secondSafety) = backup.applyPendingRestore() else {
            Issue.record("Nicht wiederhergestellt")
            return
        }
        #expect(secondSafety != safetyName)
        let safety = backupsURL.appending(path: secondSafety)
        for name in backup.databaseFileNames {
            #expect(exists(safety.appending(path: name)), "\(name) fehlt in der Sicherung")
        }
        #expect(try titles() == ["Eins"])

        // Zurück: Die Änderung aus dem WAL ist wieder da.
        try backup.requestRestore(try entry(safety, in: backup))
        _ = backup.applyPendingRestore()
        #expect(try titles() == ["Aktuell im WAL"])
    }

    /// Prüfen liest nur: Ein WAL im Backup wird dabei nicht in den Store zurückgeschrieben.
    @Test func validationLeavesBackupUnchanged() throws {
        try addPages(["Eins"])
        let backup = backup()
        let saved = try backup.createBackup(reason: .quit)
        let walBackup = backupsURL.appending(path: "2026-10-19T08-00-00Z_beenden")
        try copyWithChangeOnlyInWAL(from: saved, to: walBackup, rename: "Eins", to: "Nur im WAL")
        func contents() throws -> [String: Data] {
            var result: [String: Data] = [:]
            for name in backup.databaseFileNames {
                result[name] = try Data(contentsOf: walBackup.appending(path: name))
            }
            return result
        }
        let before = try contents()
        try backup.requestRestore(try entry(walBackup, in: backup))
        let after = try contents()
        // `-shm` ist nur der Index des WAL; jeder Leser schreibt ihn neu, ohne Daten.
        for name in backup.databaseFileNames.dropLast() {
            #expect(after[name] == before[name], "\(name) verändert")
        }
    }

    /// Ein Backup einer neueren (unbekannten) Schema-Version wird abgelehnt, bevor
    /// Quill sich beendet: kein Merker.
    @Test func rejectsUnknownSchemaBeforeQuitting() throws {
        try addPages(["Eins"])
        let saved = try backup().createBackup(reason: .quit)
        let newerApp = backup(knownSchemas: [])
        #expect(throws: RestoreError.unsupportedSchema) {
            try newerApp.requestRestore(try entry(saved, in: newerApp))
        }
        #expect(!newerApp.isRestorePending)
    }

    @Test func rejectsWhenSpaceIsShort() throws {
        try addPages(["Eins"])
        let tight = backup(capacity: 1_000)
        let saved = try tight.createBackup(reason: .quit)
        #expect(throws: RestoreError.self) {
            try tight.requestRestore(try entry(saved, in: tight))
        }
        #expect(!tight.isRestorePending)

        // Wird der Platz erst bis zum Start knapp, bleibt der Stand unverändert.
        try backup().requestRestore(try entry(saved, in: tight))
        try addPages(["Zwei"])
        guard case .failed(_, .insufficientSpace) = tight.applyPendingRestore() else {
            Issue.record("Platzmangel nicht erkannt")
            return
        }
        #expect(try titles() == ["Eins", "Zwei"])
    }

    @Test func rejectsDamagedBackup() throws {
        try addPages((1...200).map { "Seite \($0)" })
        let backup = backup()
        let saved = try backup.createBackup(reason: .quit)
        let store = saved.appending(path: "Quill.store")
        let handle = try FileHandle(forWritingTo: store)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size / 2)
        try handle.write(contentsOf: Data(repeating: 0xAB, count: 8192))
        try handle.close()

        #expect(throws: RestoreError.self) {
            try backup.requestRestore(try entry(saved, in: backup))
        }
        #expect(!backup.isRestorePending)
    }

    /// Der Merker wird vor dem Austausch gelöscht: Scheitert es, versucht der nächste
    /// Start es nicht erneut.
    @Test func requestIsConsumedEvenWhenRestoreFails() throws {
        try addPages(["Eins"])
        let backup = backup()
        let saved = try backup.createBackup(reason: .quit)
        try backup.requestRestore(try entry(saved, in: backup))
        try FileManager.default.removeItem(at: saved)

        #expect(backup.applyPendingRestore() == .failed(backup: saved.lastPathComponent, .backupMissing))
        #expect(!backup.isRestorePending)
        #expect(backup.applyPendingRestore() == nil)
        #expect(try titles() == ["Eins"])
    }

    /// Bricht die App mitten im Austausch ab, rollt der nächste Start zurück.
    @Test(arguments: [StoreBackup.RestoreStep.movedCurrentStore, .copiedBackupStore])
    func interruptedRestoreIsRolledBack(_ step: StoreBackup.RestoreStep) throws {
        try addPages(["Eins"], imageBytes: 1)
        let backup = backup()
        let saved = try backup.createBackup(reason: .quit)
        try addPages(["Zwei"], imageBytes: 2)

        try backup.requestRestore(try entry(saved, in: backup))
        #expect(backup.applyPendingRestore(stoppingAfter: step) == nil)
        #expect(exists(backup.restoreJournalURL))

        #expect(backup.applyPendingRestore() == .interruptedAndRolledBack)
        #expect(!exists(backup.restoreJournalURL))
        #expect(!backup.isRestorePending)
        #expect(try titles() == ["Eins", "Zwei"])
        #expect(try imageBytes() == [1, 2])
        #expect(try backup.entries().allSatisfy { $0.kind != .beforeRestore }, "Leere Sicherung bleibt liegen")
        #expect(backup.applyPendingRestore() == nil)
    }

    /// Nach dem Vormerken beendet sich Quill und legt ein Backup an. Die Rotation
    /// (ein Backup pro Tag) darf das gewählte Backup vom selben Tag nicht löschen.
    @Test func quitBackupAfterRequestKeepsRequestedBackup() throws {
        let morning = Date(timeIntervalSince1970: 1_792_400_000)
        try addPages(["Eins"])
        let saved = try backup(at: morning).createBackup(reason: .quit)
        try addPages(["Zwei"])
        let backup = backup(at: morning.addingTimeInterval(3600))
        try backup.requestRestore(try entry(saved, in: backup))

        let quit = try #require(try backup.backupOnQuitIfChanged())
        #expect(exists(saved))
        #expect(exists(quit))

        guard case .restored(let name, _) = backup.applyPendingRestore() else {
            Issue.record("Nicht wiederhergestellt")
            return
        }
        #expect(name == saved.lastPathComponent)
        #expect(try titles() == ["Eins"])
    }

    /// Der Stand vor dem Wiederherstellen bleibt 30 Tage, auch bei vielen Backups danach.
    @Test func pruneKeepsBeforeRestoreForThirtyDays() throws {
        let now = Date(timeIntervalSince1970: 1_792_400_000)
        let backup = backup(at: now)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        func folder(daysAgo: Double, _ slug: String) throws -> URL {
            let name = "\(StoreBackup.formatter.string(from: now.addingTimeInterval(-daysAgo * 86_400)))_\(slug)"
            let url = backupsURL.appending(path: name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let young = try folder(daysAgo: 29.5, "vor-wiederherstellen")
        let old = try folder(daysAgo: 70, "vor-wiederherstellen")
        for day in 0..<60 { _ = try folder(daysAgo: Double(day), "start") }

        try backup.prune()
        #expect(exists(young))
        #expect(!exists(old))
    }
}
