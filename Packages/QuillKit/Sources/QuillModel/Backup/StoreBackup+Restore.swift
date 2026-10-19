import CoreData
import Darwin
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
    /// Eingespielt. `previous`: wo der vorherige Stand liegt, relativ zu `Quill/`
    /// (meist `Backups/<Zeit>_vor-wiederherstellen`); `nil`, wenn es keinen gab.
    case restored(backup: String, previous: String?)
    /// Nicht eingespielt; der Stand in `Store/` ist unverändert.
    case failed(backup: String, RestoreError)
    /// Ein früherer Versuch brach vor dem Tausch ab (z. B. Absturz); `Store/` ist
    /// unverändert, die halbe Kopie ist weg.
    case interrupted
}

/// Wiederherstellen eines Backups (ADR-019).
///
/// Ablauf: `requestRestore` prüft das Backup und legt einen Merker ab, danach
/// beendet sich die App. Beim nächsten Start (unter Sperre, `prepareStore`):
///
/// 1. Merker löschen (kein Wiederherstellungs-Loop), erneut prüfen.
/// 2. Backup nach `Quill/.restore-staging/` kopieren (Store immer mit `-wal`/`-shm`,
///    dazu `.Quill_SUPPORT`), prüfen, Version und Markierung `.quill-restore` hinein.
/// 3. `Store/` und `.restore-staging/` in **einem** Schritt tauschen (`RENAME_SWAP`).
/// 4. Den alten Stand (jetzt in `.restore-staging/`) nach
///    `Backups/<Zeit>_vor-wiederherstellen/` umbenennen, Markierung entfernen.
///
/// `Store/` enthält so zu jedem Zeitpunkt einen vollständigen Stand, den alten
/// oder den neuen. Bricht die App ab, erkennt der nächste Start an der Markierung
/// in `Store/`, ob schon getauscht wurde: Wenn ja, schließt er ab; wenn nein,
/// verwirft er die Kopie.
extension StoreBackup {
    struct RestoreRequest: Codable {
        var backup: String
    }

    /// Liegt im vorbereiteten Ordner und wandert beim Tausch mit nach `Store/`.
    struct RestoreTag: Codable {
        var backup: String
        var safety: String
    }

    static let restoreTagName = ".quill-restore"

    /// Merker in `Quill/`, nicht in `Store/`: Er wandert beim Tausch nicht mit.
    var restoreRequestURL: URL {
        rootURL.appending(path: "\(storeURL.lastPathComponent).restore")
    }

    var stagingURL: URL {
        rootURL.appending(path: ".restore-staging", directoryHint: .isDirectory)
    }

    /// Store mit WAL und Shared Memory: Diese drei Dateien gehören immer zusammen.
    var databaseFileNames: [String] {
        let name = storeURL.lastPathComponent
        return [name, name + "-wal", name + "-shm"]
    }

    /// Alles, was zum aktuellen Stand gehört.
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
        guard exists(entry.url) else { throw RestoreError.backupMissing }
        let store = entry.url.appending(path: storeURL.lastPathComponent)
        guard exists(store) else { throw RestoreError.storeMissing }
        guard let version = Self.schemaVersion(ofStoreAt: store, knownSchemas: knownSchemas) else {
            throw RestoreError.unsupportedSchema
        }
        do {
            try Self.quickCheck(store, readOnly: true)
        } catch {
            throw RestoreError.damaged(String(describing: error))
        }
        // Der aktuelle Stand wird nur umbenannt; Platz braucht die Kopie des Backups.
        let needed = Self.size(of: entry.url) + Self.spaceReserve
        if let available = availableCapacity(rootURL), available < needed {
            throw RestoreError.insufficientSpace(needed: needed, available: available)
        }
        return version
    }

    /// Puffer über der Größe des Backups beim Prüfen des freien Platzes.
    static let spaceReserve: Int64 = 100 * 1024 * 1024

    // MARK: - Beim Start

    /// Spielt ein vorgemerktes Backup ein oder schließt einen unterbrochenen Tausch
    /// ab. `nil`, wenn nichts anstand. In der App über `prepareStore` (unter Sperre).
    public func applyPendingRestore() -> RestoreOutcome? {
        applyPendingRestore(stoppingAfter: nil)
    }

    /// Schritte des Austauschs, für den Test eines Abbruchs nach jedem einzelnen.
    enum RestoreStep: Hashable, Sendable {
        /// Eine Datei des Backups liegt im vorbereiteten Ordner.
        case copied(String)
        /// Geprüft, Version und Markierung geschrieben.
        case staged
        /// `Store/` getauscht.
        case swapped
        /// Alter Stand nach `Backups/` umbenannt, Markierung noch da.
        case previousMoved
    }

    /// `stoppingAfter` hält nach einem Schritt an, als bräche die App ab (Tests).
    func applyPendingRestore(stoppingAfter stop: RestoreStep?) -> RestoreOutcome? {
        if let resumed = resumeInterruptedRestore(stoppingAfter: stop) { return resumed }
        let fileManager = FileManager.default
        guard let data = try? Data(contentsOf: restoreRequestURL) else { return nil }
        // Merker zuerst weg: Was auch passiert, der nächste Start versucht es nicht erneut.
        try? fileManager.removeItem(at: restoreRequestURL)
        guard let request = try? JSONDecoder().decode(RestoreRequest.self, from: data) else { return nil }

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
        // Eine Markierung, die sich beim letzten Abschluss nicht entfernen ließ,
        // hielte den nächsten Start für „schon getauscht“.
        guard !exists(storeDirectoryURL.appending(path: Self.restoreTagName)) else {
            return .failed(backup: request.backup, .fileOperation("Alte Markierung in Store/"))
        }

        let tag = RestoreTag(
            backup: request.backup,
            safety: uniqueBackupName("\(Self.formatter.string(from: now()))_\(Reason.beforeRestore.slug)")
        )
        do {
            try prepareStaging(from: entry.url, version: version, tag: tag, stoppingAfter: stop)
        } catch StagingStopped.stopped {
            return nil
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            return .failed(backup: request.backup, .fileOperation(String(describing: error)))
        }
        if stop == .staged { return nil }

        do {
            if exists(storeDirectoryURL) {
                try Self.swapDirectories(stagingURL, storeDirectoryURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: storeDirectoryURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            return .failed(backup: request.backup, .fileOperation(String(describing: error)))
        }
        if stop == .swapped { return nil }
        return finishRestore(tag, stoppingAfter: stop)
    }

    private enum StagingStopped: Swift.Error {
        case stopped
    }

    /// Kopiert das Backup nach `.restore-staging/`, prüft es und schreibt Version
    /// und Markierung zuletzt.
    private func prepareStaging(from backup: URL, version: String, tag: RestoreTag, stoppingAfter stop: RestoreStep?) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: stagingURL)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        for name in databaseFileNames + [supportURL.lastPathComponent] {
            let source = backup.appending(path: name)
            guard exists(source) else { continue }
            try fileManager.copyItem(at: source, to: stagingURL.appending(path: name))
            if stop == .copied(name) { throw StagingStopped.stopped }
        }
        try Self.quickCheck(stagingURL.appending(path: storeURL.lastPathComponent))
        try Data(version.utf8).write(to: stagingURL.appending(path: versionFileURL.lastPathComponent), options: .atomic)
        try JSONEncoder().encode(tag).write(to: stagingURL.appending(path: Self.restoreTagName), options: .atomic)
    }

    /// Nach dem Tausch: alten Stand nach `Backups/` umbenennen, Markierung entfernen.
    /// Scheitert das Umbenennen, bleibt er in `.restore-staging/`, und der nächste
    /// Start versucht es wieder.
    private func finishRestore(_ tag: RestoreTag, stoppingAfter stop: RestoreStep?) -> RestoreOutcome? {
        let fileManager = FileManager.default
        let safety = backupsURL.appending(path: tag.safety, directoryHint: .isDirectory)
        if exists(stagingURL) {
            do {
                try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
                try fileManager.moveItem(at: stagingURL, to: safety)
            } catch {
                return .restored(backup: tag.backup, previous: stagingURL.lastPathComponent)
            }
            if stop == .previousMoved { return nil }
        }
        try? fileManager.removeItem(at: storeDirectoryURL.appending(path: Self.restoreTagName))
        return .restored(backup: tag.backup, previous: exists(safety) ? "\(backupsURL.lastPathComponent)/\(tag.safety)" : nil)
    }

    /// Reste eines abgebrochenen Starts: Mit Markierung in `Store/` wurde schon
    /// getauscht, dann abschließen. Sonst ist `.restore-staging/` nur eine (halbe)
    /// Kopie eines Backups, das unverändert in `Backups/` liegt; sie wird verworfen.
    private func resumeInterruptedRestore(stoppingAfter stop: RestoreStep?) -> RestoreOutcome? {
        let tagURL = storeDirectoryURL.appending(path: Self.restoreTagName)
        if exists(tagURL) {
            let tag = (try? JSONDecoder().decode(RestoreTag.self, from: Data(contentsOf: tagURL)))
                ?? RestoreTag(backup: "", safety: uniqueBackupName("\(Self.formatter.string(from: now()))_\(Reason.beforeRestore.slug)"))
            return finishRestore(tag, stoppingAfter: stop)
        }
        guard exists(stagingURL) else { return nil }
        try? FileManager.default.removeItem(at: stagingURL)
        return .interrupted
    }

    /// Tauscht zwei Ordner auf demselben Volume in einem Schritt (APFS). Ohne
    /// Unterstützung wird nicht getauscht, statt in zwei Schritten umzubenennen.
    static func swapDirectories(_ first: URL, _ second: URL) throws {
        guard renamex_np(first.path(percentEncoded: false), second.path(percentEncoded: false), UInt32(RENAME_SWAP)) == 0 else {
            throw RestoreError.fileOperation("Tausch nicht möglich: \(String(cString: strerror(errno)))")
        }
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
