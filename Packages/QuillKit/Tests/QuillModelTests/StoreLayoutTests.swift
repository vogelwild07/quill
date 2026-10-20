import Foundation
import SQLite3
import SwiftData
import Testing
@testable import QuillModel

extension DiskStoreSuites {
    /// Umzug der Store-Dateien nach `Store/` und Sperre (ADR-019).
    @Suite(.serialized) struct StoreLayoutTests {
        let directory: URL
        let storeURL: URL
        let backupsURL: URL

        init() {
            directory = URL.temporaryDirectory.appending(path: "QuillLayoutTests-\(UUID().uuidString)")
            storeURL = directory.appending(path: "Store/Quill.store")
            backupsURL = directory.appending(path: "Backups")
        }

        private func backup() -> StoreBackup {
            StoreBackup(storeURL: storeURL, backupsURL: backupsURL, schemaVersion: "1.0.0")
        }

        private func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }

        private var legacyNames: [String] {
            ["Quill.store", "Quill.store-wal", "Quill.store-shm", ".Quill_SUPPORT", "Quill.store.version"]
        }

        /// Store im alten Ort mit allen fünf Teilen: Die letzte Änderung steht nur im
        /// WAL, ein Bild in `.Quill_SUPPORT`, dazu die Versionsdatei.
        private func makeLegacyStore() throws {
            let fileManager = FileManager.default
            let work = directory.appending(path: "work")
            let source = work.appending(path: "Quelle/Quill.store")
            do {
                let context = ModelContext(try QuillStore.makeContainer(storeURL: source))
                let page = Page(title: "Alt")
                context.insert(page)
                let block = Block(kind: .image)
                block.page = page
                block.asset = Asset(data: Data(repeating: 7, count: 300_000))
                try context.save()
            }
            // Schnappschuss per VACUUM: eine Datei, die nur diesem Test gehört.
            let snapshot = try StoreBackup(
                storeURL: source, backupsURL: work.appending(path: "Backups"), schemaVersion: "1.0.0"
            ).createBackup(reason: .quit)

            var db: OpaquePointer?
            #expect(sqlite3_open_v2(snapshot.appending(path: "Quill.store").path(percentEncoded: false), &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
            for sql in ["PRAGMA journal_mode=WAL", "PRAGMA wal_autocheckpoint=0", "UPDATE ZPAGE SET ZTITLE='Nur im WAL'"] {
                #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(sql)")
            }
            // Kopie bei offener Verbindung: Beim Schließen würde SQLite den WAL zurückschreiben.
            for name in try fileManager.contentsOfDirectory(atPath: snapshot.path(percentEncoded: false)) {
                try fileManager.copyItem(at: snapshot.appending(path: name), to: directory.appending(path: name))
            }
            sqlite3_close_v2(db)
            try fileManager.removeItem(at: work)
            try Data("1.0.0".utf8).write(to: directory.appending(path: "Quill.store.version"))
            for name in legacyNames {
                #expect(exists(directory.appending(path: name)), "\(name) fehlt in der Testdatei")
            }
        }

        /// Titel und Bildbytes des Stores in `Store/`.
        private func contents() throws -> (titles: [String], images: [UInt8]) {
            let context = ModelContext(try QuillStore.makeContainer(storeURL: storeURL))
            return (
                try context.fetch(FetchDescriptor<Page>()).map(\.title),
                try context.fetch(FetchDescriptor<Asset>()).compactMap { $0.data?.first }
            )
        }

        private func moveBackups(_ backup: StoreBackup) throws -> [StoreBackup.Entry] {
            try backup.entries().filter { $0.kind == .beforeMove }
        }

        // MARK: - Umzug

        @Test func movesAllStoreFilesAfterBackup() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            try makeLegacyStore()
            let backup = backup()

            let created = try #require(try backup.moveLegacyStoreIfNeeded())
            #expect(created.lastPathComponent.hasSuffix("_vor-umzug"))
            #expect(exists(created.appending(path: "Quill.store")))
            #expect(exists(created.appending(path: ".Quill_SUPPORT")))

            for name in legacyNames {
                #expect(!exists(directory.appending(path: name)), "\(name) liegt noch im alten Ort")
                #expect(exists(directory.appending(path: "Store/\(name)")), "\(name) fehlt in Store/")
            }
            #expect(!exists(backup.moveURL))
            #expect(backup.lastOpenedSchemaVersion == "1.0.0", "Versionsdatei zieht mit, sonst Backup vor Migration")
            let (titles, images) = try contents()
            #expect(titles == ["Nur im WAL"], "WAL zieht mit")
            DiskStoreSuites.expectImageBytes(images, [7], store: storeURL, "Bilder ziehen mit")

            // Zweiter Start: nichts mehr zu tun.
            #expect(try backup.moveLegacyStoreIfNeeded() == nil)
            #expect(try moveBackups(backup).count == 1)
        }

        /// Bricht der Umzug nach irgendeinem Schritt ab, ist nichts verloren, und der
        /// nächste Start macht weiter.
        @Test(arguments: [StoreBackup.MoveStep.backedUp] + ["Quill.store", "Quill.store-wal", "Quill.store-shm", ".Quill_SUPPORT", "Quill.store.version"].map { StoreBackup.MoveStep.moved($0) })
        func interruptedMoveContinuesOnNextLaunch(_ step: StoreBackup.MoveStep) throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            try makeLegacyStore()
            let backup = backup()

            try backup.moveLegacyStoreIfNeeded(stoppingAfter: step)
            for name in legacyNames {
                let places = [directory.appending(path: name), backup.moveURL.appending(path: name)].filter(exists)
                #expect(places.count == 1, "\(name) nach \(step): \(places)")
            }
            #expect(!exists(backup.storeDirectoryURL))

            try backup.moveLegacyStoreIfNeeded()
            for name in legacyNames {
                #expect(exists(directory.appending(path: "Store/\(name)")), "\(name) fehlt nach \(step)")
                #expect(!exists(directory.appending(path: name)))
            }
            #expect(!exists(backup.moveURL))
            let (titles, images) = try contents()
            #expect(titles == ["Nur im WAL"])
            DiskStoreSuites.expectImageBytes(images, [7], store: storeURL)
            #expect(try moveBackups(backup).count >= 1)
        }

        /// Ohne Backup kein Umzug: Die Dateien bleiben, wo sie sind.
        @Test func noMoveWithoutBackup() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            try makeLegacyStore()
            // `Backups` als Datei: Das Backup scheitert.
            try Data().write(to: backupsURL)

            #expect(throws: (any Error).self) { try backup().moveLegacyStoreIfNeeded() }
            for name in legacyNames {
                #expect(exists(directory.appending(path: name)), "\(name) verschoben")
            }
            #expect(!exists(storeURL.deletingLastPathComponent()))
        }

        /// Store in `Store/` mit einer Seite „Aktuell“ und ohne Bild.
        private func makeCurrentStore() throws {
            let context = ModelContext(try QuillStore.makeContainer(storeURL: storeURL))
            context.insert(Page(title: "Aktuell"))
            try context.save()
        }

        /// Gibt es `Store/` schon, werden flache Dateien im alten Ort weder verwendet
        /// noch überschrieben noch gemischt: Sie kommen unverändert in ein Backup
        /// „beiseitegelegt“, das sich einspielen lässt, und werden gemeldet.
        @Test func legacyFilesBesideStoreDirectoryAreSetAside() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            try makeLegacyStore()
            try makeCurrentStore()
            let backup = backup()

            let preparation = try backup.prepareStore()
            let setAside = try #require(preparation.setAside)
            #expect(setAside.hasPrefix("Backups/") && setAside.hasSuffix("_beiseitegelegt"))
            #expect(preparation.restore == nil)

            let folder = directory.appending(path: setAside)
            for name in legacyNames {
                #expect(!exists(directory.appending(path: name)), "\(name) liegt noch im alten Ort")
                #expect(exists(folder.appending(path: name)), "\(name) fehlt in \(setAside)")
            }
            #expect(try contents().titles == ["Aktuell"], "Store/ unverändert")
            #expect(try moveBackups(backup).isEmpty, "Kein Umzug")

            // Zweiter Start: nichts mehr zu tun.
            #expect(try backup.prepareStore() == StorePreparation())

            // Die beiseitegelegten Dateien lassen sich einspielen, samt WAL und Bild.
            let entry = try #require(try backup.entries().first { $0.url.lastPathComponent == folder.lastPathComponent })
            #expect(entry.kind == .setAside)
            try backup.requestRestore(entry)
            guard case .restored = try backup.prepareStore().restore else {
                Issue.record("Beiseitegelegtes nicht eingespielt")
                return
            }
            let (titles, images) = try contents()
            #expect(titles == ["Nur im WAL"])
            DiskStoreSuites.expectImageBytes(images, [7], store: storeURL)
        }

        /// Auch ein angefangener Umzug (`.Store-umzug/`) neben einem vorhandenen
        /// `Store/` wird beiseitegelegt, statt das Öffnen zu verhindern.
        @Test func interruptedMoveBesideStoreDirectoryIsSetAside() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            try makeLegacyStore()
            let backup = backup()
            try backup.moveLegacyStoreIfNeeded(stoppingAfter: .moved("Quill.store-wal"))
            try makeCurrentStore()

            let setAside = try #require(try backup.prepareStore().setAside)
            let folder = directory.appending(path: setAside)
            for name in legacyNames {
                #expect(exists(folder.appending(path: name)), "\(name) fehlt in \(setAside)")
                #expect(!exists(directory.appending(path: name)))
            }
            #expect(!exists(backup.moveURL))
            #expect(try contents().titles == ["Aktuell"])
        }

        /// Ein neuer Mac ohne Store: kein Umzug, kein Backup.
        @Test func freshInstallNeedsNoMove() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            let backup = backup()
            #expect(try backup.prepareStore() == StorePreparation())
            #expect(try backup.entries().isEmpty)
        }

        // MARK: - Sperre

        /// Solange eine andere Instanz die Sperre hält, zieht diese nicht um und
        /// spielt nichts ein.
        @Test func lockKeepsSecondInstanceOut() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            try makeLegacyStore()
            let backup = backup()
            let other = try StoreLock(at: backup.lockURL, timeout: 0)

            #expect(throws: StoreLayoutError.locked) { try backup.prepareStore(lockTimeout: 0.2) }
            for name in legacyNames {
                #expect(exists(directory.appending(path: name)), "\(name) trotz Sperre verschoben")
            }

            other.release()
            _ = try backup.prepareStore(lockTimeout: 0.2)
            #expect(exists(storeURL))
        }

        /// Die Sperre fällt mit dem Ende der Vorbereitung; der nächste Start bekommt sie.
        @Test func lockIsReleasedAfterPreparing() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            let backup = backup()
            _ = try backup.prepareStore(lockTimeout: 0)
            let lock = try StoreLock(at: backup.lockURL, timeout: 0)
            lock.release()
        }

        // MARK: - Rotation

        @Test func pruneKeepsMoveSetAsideAndSyncBackupsForever() throws {
            defer { try? FileManager.default.removeItem(at: directory) }
            let now = Date(timeIntervalSince1970: 1_792_400_000)
            let backup = StoreBackup(storeURL: storeURL, backupsURL: backupsURL, schemaVersion: "1.0.0", now: { now })
            try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            func folder(daysAgo: Double, _ slug: String) throws -> URL {
                let name = "\(StoreBackup.formatter.string(from: now.addingTimeInterval(-daysAgo * 86_400)))_\(slug)"
                let url = backupsURL.appending(path: name)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url
            }
            let moved = try folder(daysAgo: 400, "vor-umzug")
            let setAside = try folder(daysAgo: 400, "beiseitegelegt")
            let beforeSync = try folder(daysAgo: 400, "vor-sync")
            for day in 0..<60 { _ = try folder(daysAgo: Double(day), "start") }

            try backup.prune()
            #expect(exists(moved))
            #expect(exists(setAside))
            #expect(exists(beforeSync))
        }
    }
}
