import CoreData
import Foundation
import SwiftData

/// Gründe, aus denen ein Backup nicht eingespielt wird (ADR-019).
public enum RestoreError: Error, Equatable, Sendable {
    /// Den Backup-Ordner gibt es nicht (mehr).
    case backupMissing
    /// Im Backup fehlt `Quill.store`.
    case storeMissing
    /// Das Backup passt zu keiner Schema-Version dieser Quill-Version, stammt also
    /// von einer neueren (oder ist keine Quill-Datenbank).
    case unsupportedSchema
    /// Die Datenbank im Backup ist beschädigt.
    case damaged(String)
    /// Auf dem Volume ist zu wenig Platz (Bytes).
    case insufficientSpace(needed: Int64, available: Int64)
    /// Ein Dateischritt ist gescheitert; der alte Stand ist zurück.
    case fileOperation(String)
}

/// Was beim Start mit einer angefragten Wiederherstellung geschah, zur Anzeige.
public enum RestoreOutcome: Equatable, Sendable {
    /// Eingespielt; der vorherige Stand liegt im Backup `safetyName`.
    case restored(backup: String, safetyName: String)
    /// Nicht eingespielt; der Stand ist unverändert.
    case failed(backup: String, RestoreError)
    /// Ein früherer Austausch wurde unterbrochen (z. B. Absturz) und zurückgerollt.
    case interruptedAndRolledBack
}

/// Wiederherstellen eines Backups (ADR-019).
///
/// Ablauf: `requestRestore` prüft das Backup und legt einen Merker ab, danach
/// beendet sich die App. Beim nächsten Start tauscht `applyPendingRestore` die
/// Dateien, **bevor** der Container öffnet:
///
/// 1. Merker löschen (kein Wiederherstellungs-Loop), erneut prüfen.
/// 2. Journal schreiben, dann Store mit `-wal`/`-shm`, `.Quill_SUPPORT` und
///    Versionsdatei unverändert in `Backups/<Zeit>_vor-wiederherstellen/` verschieben.
/// 3. Backup hineinkopieren (Store immer mit `-wal`/`-shm`), prüfen, Version setzen.
/// 4. Journal löschen.
///
/// Scheitert ein Schritt, kommt der alte Stand zurück. Bricht die App mitten im
/// Austausch ab, findet der nächste Start das Journal und rollt zurück.
extension StoreBackup {
    struct RestoreRequest: Codable {
        var backup: String
    }

    struct RestoreJournal: Codable {
        var backup: String
        var safety: String
    }

    var restoreRequestURL: URL {
        storeURL.deletingLastPathComponent().appending(path: "\(storeURL.lastPathComponent).restore")
    }

    var restoreJournalURL: URL {
        storeURL.deletingLastPathComponent().appending(path: "\(storeURL.lastPathComponent).restore-journal")
    }

    /// Store mit WAL und Shared Memory: Diese drei Dateien gehören immer zusammen.
    var databaseFileNames: [String] {
        let name = storeURL.lastPathComponent
        return [name, name + "-wal", name + "-shm"]
    }

    /// Alles, was zum aktuellen Stand gehört, in der Reihenfolge des Verschiebens.
    var storeItemNames: [String] {
        databaseFileNames + [supportURL.lastPathComponent, versionFileURL.lastPathComponent]
    }

    // MARK: - Vor dem Beenden

    /// Prüft ein Backup und merkt es für den nächsten Start vor. Wirft, wenn es
    /// nicht eingespielt werden kann; dann beendet sich die App nicht.
    public func requestRestore(_ entry: Entry) throws {
        _ = try validateForRestore(entry)
        let data = try JSONEncoder().encode(RestoreRequest(backup: entry.url.lastPathComponent))
        try data.write(to: restoreRequestURL, options: .atomic)
    }

    /// Ordnername des vorgemerkten Backups; die Rotation lässt es stehen.
    var pendingRestoreBackupName: String? {
        guard let data = try? Data(contentsOf: restoreRequestURL) else { return nil }
        return try? JSONDecoder().decode(RestoreRequest.self, from: data).backup
    }

    /// Ob ein Backup für den nächsten Start vorgemerkt ist.
    public var isRestorePending: Bool {
        FileManager.default.fileExists(atPath: restoreRequestURL.path(percentEncoded: false))
    }

    /// Prüft Vollständigkeit, Schema, Zustand und Platz; gibt die Schema-Version
    /// des Backups zurück.
    func validateForRestore(_ entry: Entry) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: entry.url.path(percentEncoded: false)) else { throw RestoreError.backupMissing }
        let store = entry.url.appending(path: storeURL.lastPathComponent)
        guard fileManager.fileExists(atPath: store.path(percentEncoded: false)) else { throw RestoreError.storeMissing }
        guard let version = Self.schemaVersion(ofStoreAt: store, knownSchemas: knownSchemas) else {
            throw RestoreError.unsupportedSchema
        }
        do {
            try Self.quickCheck(store, readOnly: true)
        } catch {
            throw RestoreError.damaged(String(describing: error))
        }
        // Der aktuelle Stand wird nur verschoben; Platz braucht die Kopie des Backups.
        let needed = Self.size(of: entry.url) + Self.spaceReserve
        if let available = availableCapacity(storeURL.deletingLastPathComponent()), available < needed {
            throw RestoreError.insufficientSpace(needed: needed, available: available)
        }
        return version
    }

    /// Puffer über der Größe des Backups beim Prüfen des freien Platzes.
    static let spaceReserve: Int64 = 100 * 1024 * 1024

    // MARK: - Beim Start

    /// Beim Start aufrufen, **bevor** Backups angelegt werden und der Container
    /// öffnet. `nil`, wenn nichts anstand.
    public func applyPendingRestore() -> RestoreOutcome? {
        applyPendingRestore(stoppingAfter: nil)
    }

    /// Schritte des Austauschs, für den Test eines Abbruchs mittendrin.
    enum RestoreStep {
        case movedCurrentStore
        case copiedBackupStore
    }

    /// `stoppingAfter` hält nach einem Schritt an, als bräche die App ab (Tests).
    func applyPendingRestore(stoppingAfter stop: RestoreStep?) -> RestoreOutcome? {
        let fileManager = FileManager.default
        if let journal = try? JSONDecoder().decode(RestoreJournal.self, from: Data(contentsOf: restoreJournalURL)) {
            rollBack(journal, fileManager: fileManager)
            return .interruptedAndRolledBack
        }
        guard let data = try? Data(contentsOf: restoreRequestURL) else { return nil }
        // Merker zuerst weg: Was auch passiert, der nächste Start versucht es nicht erneut.
        try? fileManager.removeItem(at: restoreRequestURL)
        guard let request = try? JSONDecoder().decode(RestoreRequest.self, from: data) else { return nil }

        let backupURL = backupsURL.appending(path: request.backup, directoryHint: .isDirectory)
        guard let entry = (try? entries())?.first(where: { $0.url.lastPathComponent == request.backup }) else {
            return .failed(backup: request.backup, .backupMissing)
        }
        let version: String
        do {
            version = try validateForRestore(entry)
        } catch let error as RestoreError {
            return .failed(backup: request.backup, error)
        } catch {
            return .failed(backup: request.backup, .fileOperation(String(describing: error)))
        }

        let safetyName = uniqueBackupName("\(Self.formatter.string(from: now()))_\(Reason.beforeRestore.slug)")
        let journal = RestoreJournal(backup: request.backup, safety: safetyName)
        do {
            try JSONEncoder().encode(journal).write(to: restoreJournalURL, options: .atomic)
            let safety = backupsURL.appending(path: safetyName, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: safety, withIntermediateDirectories: true)

            let directory = storeURL.deletingLastPathComponent()
            for name in storeItemNames {
                let current = directory.appending(path: name)
                guard fileManager.fileExists(atPath: current.path(percentEncoded: false)) else { continue }
                try fileManager.moveItem(at: current, to: safety.appending(path: name))
            }
            if stop == .movedCurrentStore { return nil }

            for name in databaseFileNames + [supportURL.lastPathComponent] {
                let source = backupURL.appending(path: name)
                guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                try fileManager.copyItem(at: source, to: directory.appending(path: name))
            }
            if stop == .copiedBackupStore { return nil }

            try Self.quickCheck(storeURL)
            try Data(version.utf8).write(to: versionFileURL, options: .atomic)
            try fileManager.removeItem(at: restoreJournalURL)
            return .restored(backup: request.backup, safetyName: safetyName)
        } catch {
            rollBack(journal, fileManager: fileManager)
            return .failed(backup: request.backup, .fileOperation(String(describing: error)))
        }
    }

    /// Stellt den Stand aus dem Sicherungsordner wieder her und entfernt Journal
    /// und leeren Sicherungsordner. Mehrfach aufrufbar.
    private func rollBack(_ journal: RestoreJournal, fileManager: FileManager) {
        let directory = storeURL.deletingLastPathComponent()
        let safety = backupsURL.appending(path: journal.safety, directoryHint: .isDirectory)
        let saved = Set((try? fileManager.contentsOfDirectory(atPath: safety.path(percentEncoded: false))) ?? [])
        // Wurde der Store schon verschoben, ist alles im Ordner halb Kopiertes aus dem Backup.
        if saved.contains(storeURL.lastPathComponent) {
            for name in storeItemNames {
                try? fileManager.removeItem(at: directory.appending(path: name))
            }
        }
        for name in storeItemNames where saved.contains(name) {
            try? fileManager.moveItem(at: safety.appending(path: name), to: directory.appending(path: name))
        }
        if ((try? fileManager.contentsOfDirectory(atPath: safety.path(percentEncoded: false))) ?? []).isEmpty {
            try? fileManager.removeItem(at: safety)
        }
        try? fileManager.removeItem(at: restoreJournalURL)
    }

    private func uniqueBackupName(_ name: String) -> String {
        var candidate = name
        var counter = 2
        while FileManager.default.fileExists(atPath: backupsURL.appending(path: candidate).path(percentEncoded: false)) {
            candidate = "\(name)-\(counter)"
            counter += 1
        }
        return candidate
    }

    // MARK: - Hilfen

    /// Schema-Version einer Datenbank: die erste bekannte Version, deren Modell zu
    /// den Metadaten des Stores passt. `nil` für neuere oder fremde Datenbanken.
    static func schemaVersion(ofStoreAt url: URL, knownSchemas: [any VersionedSchema.Type]) -> String? {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url) else { return nil }
        for schema in knownSchemas.reversed() {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: schema.models) else { continue }
            if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                let version = schema.versionIdentifier
                return "\(version.major).\(version.minor).\(version.patch)"
            }
        }
        return nil
    }

    /// Belegte Größe eines Ordners samt Unterordnern in Bytes.
    public static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Freier Platz für wichtige Daten auf dem Volume von `url`.
    public static func availableCapacity(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }
}
