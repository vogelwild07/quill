import Foundation
import SQLite3
import SwiftData

/// Automatische Backups der Quill-Datenbank (ADR-010).
///
/// Ein Backup ist ein Ordner `Backups/<Zeitpunkt>_<Anlass>/` mit `Quill.store`
/// und, falls vorhanden, `.Quill_SUPPORT/` (Daten mit `.externalStorage`).
/// Die Datenbank wird per `VACUUM INTO` kopiert: konsistent auch bei offenem
/// Store und WAL. Wiederherstellen von Hand siehe `docs/data-model.md`.
public struct StoreBackup: Sendable {
    public enum Reason: Sendable, Equatable {
        /// Beim Start, wenn das letzte Backup älter als 24 h ist.
        case launch
        /// Beim Beenden, wenn sich seit dem letzten Backup etwas geändert hat.
        case quit
        /// Vor dem Öffnen mit einer anderen Schema-Version. Wird nie automatisch gelöscht.
        case beforeMigration(from: String, to: String)
        /// Vor endgültigem Löschen aus dem Papierkorb (ADR-017).
        case beforeEmptyingTrash
        /// Der Stand vor dem Einspielen eines Backups (ADR-019): die Dateien selbst,
        /// verschoben statt kopiert. 30 Tage geschützt.
        case beforeRestore
        /// Vor dem einmaligen Umzug der Store-Dateien nach `Store/` (ADR-019). Wird
        /// nie automatisch gelöscht.
        case beforeMove
        /// Store-Dateien im alten Ort, obwohl es `Store/` schon gab: verschoben statt
        /// verwendet (ADR-019). Wird nie automatisch gelöscht.
        case setAside

        var kind: Kind {
            switch self {
            case .launch: .launch
            case .quit: .quit
            case .beforeMigration: .beforeMigration
            case .beforeEmptyingTrash: .beforeEmptyingTrash
            case .beforeRestore: .beforeRestore
            case .beforeMove: .beforeMove
            case .setAside: .setAside
            }
        }

        /// Anlass im Ordnernamen; vor einer Migration mit beiden Versionen.
        var slug: String {
            let base = kind.slug ?? ""
            return switch self {
            case .beforeMigration(let from, let to): "\(base)\(from)-\(to)"
            case .launch, .quit, .beforeEmptyingTrash, .beforeRestore, .beforeMove, .setAside: base
            }
        }
    }

    public enum Error: Swift.Error, Equatable {
        case sqlite(code: Int32, message: String)
        case integrityCheckFailed(String)
    }

    /// Anlass eines vorhandenen Backups, aus dem Ordnernamen gelesen.
    public enum Kind: Sendable, Equatable, CaseIterable {
        case launch, quit, beforeMigration, beforeEmptyingTrash, beforeRestore, beforeMove, setAside
        /// Unbekannter Anlass (z. B. von einer späteren Version).
        case other

        /// Anfang des Anlasses im Ordnernamen. Die einzige Stelle dieser Zuordnung;
        /// die Texte stehen so in vorhandenen Backups und dürfen sich nicht ändern.
        /// Keiner ist Anfang eines anderen, die Reihenfolge beim Lesen ist also egal.
        var slug: String? {
            switch self {
            case .launch: "start"
            case .quit: "beenden"
            case .beforeMigration: "vor-migration-"
            case .beforeEmptyingTrash: "vor-papierkorb-leeren"
            case .beforeRestore: "vor-wiederherstellen"
            case .beforeMove: "vor-umzug"
            case .setAside: "beiseitegelegt"
            case .other: nil
            }
        }

        /// Liest den Anlass; Anhänge (Versionen, Zähler für doppelte Namen) zählen nicht.
        init(slug: Substring) {
            self = Self.allCases.first { kind in kind.slug.map { slug.hasPrefix($0) } ?? false } ?? .other
        }
    }

    /// Ein vorhandenes Backup.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let url: URL
        public let date: Date
        public let kind: Kind

        public var id: String { url.lastPathComponent }
        public var name: BackupName { BackupName(url.lastPathComponent) }
        public var isBeforeMigration: Bool { kind == .beforeMigration }
        public var isBeforeEmptyingTrash: Bool { kind == .beforeEmptyingTrash }
    }

    public let storeURL: URL
    public let backupsURL: URL
    public let schemaVersion: String
    public var calendar: Calendar
    public var now: @Sendable () -> Date
    /// Schema-Versionen, deren Backups sich einspielen lassen (ADR-019).
    public var knownSchemas: [any VersionedSchema.Type]
    /// Freier Platz auf dem Volume eines Ordners; im Test ersetzbar.
    public var availableCapacity: @Sendable (URL) -> Int64?

    public static let dailyBackupsToKeep = 7
    public static let weeklyBackupsToKeep = 4
    public static let launchInterval: TimeInterval = 24 * 60 * 60
    /// Backups vor dem Leeren des Papierkorbs: so lange und höchstens so viele,
    /// zusätzlich zu den regulären (ADR-017).
    public static let trashBackupRetention: TimeInterval = 30 * 24 * 60 * 60
    public static let trashBackupsToKeep = 10
    /// Der Stand vor dem Wiederherstellen bleibt so lange, egal wie viele Backups
    /// danach entstehen (ADR-019).
    public static let restoreBackupRetention: TimeInterval = 30 * 24 * 60 * 60

    public init(
        storeURL: URL = QuillStore.defaultStoreURL,
        backupsURL: URL = QuillStore.directoryURL.appending(path: "Backups", directoryHint: .isDirectory),
        schemaVersion: String = QuillStore.schemaVersion,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date.now },
        knownSchemas: [any VersionedSchema.Type] = QuillMigrationPlan.schemas,
        availableCapacity: @escaping @Sendable (URL) -> Int64? = StoreBackup.availableCapacity(at:)
    ) {
        self.storeURL = storeURL
        self.backupsURL = backupsURL
        self.schemaVersion = schemaVersion
        self.calendar = calendar
        self.now = now
        self.knownSchemas = knownSchemas
        self.availableCapacity = availableCapacity
    }

    // MARK: - Abläufe der App

    /// Beim Start aufrufen, **bevor** der `ModelContainer` geöffnet wird.
    ///
    /// Weicht die zuletzt geöffnete Schema-Version ab (oder fehlt sie bei einem
    /// vorhandenen Store), entsteht ein Backup vor der Migration; sonst eines,
    /// wenn das letzte älter als 24 h ist. Danach wird aufgeräumt.
    @discardableResult
    public func backupBeforeOpening() throws -> URL? {
        guard storeExists else { return nil }
        let created: URL?
        let lastVersion = lastOpenedSchemaVersion
        if lastVersion != schemaVersion {
            created = try createBackup(reason: .beforeMigration(from: lastVersion ?? "unbekannt", to: schemaVersion))
        } else if let latest = try entries().first, now().timeIntervalSince(latest.date) < Self.launchInterval {
            created = nil
        } else {
            created = try createBackup(reason: .launch)
        }
        try prune()
        return created
    }

    /// Ob beim Öffnen eine Migration ansteht (Store vorhanden, Version abweichend oder unbekannt).
    public var isMigrationPending: Bool {
        storeExists && lastOpenedSchemaVersion != schemaVersion
    }

    /// Nach erfolgreichem Öffnen des Containers aufrufen: merkt sich die Schema-Version.
    public func markOpened() throws {
        try Data(schemaVersion.utf8).write(to: versionFileURL, options: .atomic)
    }

    /// Beim Beenden aufrufen. Legt nur ein Backup an, wenn sich der Store seit
    /// dem letzten Backup geändert hat.
    @discardableResult
    public func backupOnQuitIfChanged() throws -> URL? {
        guard storeExists else { return nil }
        if let latest = try entries().first, let modified = storeModificationDate, modified <= latest.date {
            return nil
        }
        let created = try createBackup(reason: .quit)
        try prune()
        return created
    }

    /// Vor endgültigem Löschen: Backup, außer der Store ist seit dem letzten Backup
    /// (gleich welcher Art) unverändert (ADR-017). So liegt jede gelöschte Seite in
    /// einem Backup, und mehrfaches Löschen ohne Änderung dazwischen kostet keins.
    @discardableResult
    public func backupBeforeEmptyingTrash() throws -> URL? {
        guard storeExists else { return nil }
        if let latest = try entries().first, let modified = storeModificationDate, modified <= latest.date {
            return nil
        }
        let created = try createBackup(reason: .beforeEmptyingTrash)
        try prune()
        return created
    }

    // MARK: - Bausteine

    /// Legt sofort ein Backup an und gibt seinen Ordner zurück.
    @discardableResult
    public func createBackup(reason: Reason) throws -> URL {
        try createBackup(reason: reason, of: storeURL)
    }

    /// Backup eines Stores an `store` (beim Umzug der Store im alten Ort).
    func createBackup(reason: Reason, of store: URL) throws -> URL {
        let fileManager = FileManager.default
        let supportURL = Self.supportURL(for: store)
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        let date = now()
        let name = backupName(reason, at: date)
        let partial = backupsURL.appending(path: ".\(name.rawValue).partial", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: partial)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)

        do {
            let target = partial.appending(path: store.lastPathComponent)
            try Self.vacuum(store, into: target)
            try Self.quickCheck(target)
            if fileManager.fileExists(atPath: supportURL.path(percentEncoded: false)) {
                try fileManager.copyItem(at: supportURL, to: partial.appending(path: supportURL.lastPathComponent))
            }
            let final = backupsURL.appending(path: uniqueBackupName(name).rawValue, directoryHint: .isDirectory)
            try fileManager.moveItem(at: partial, to: final)
            return final
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }

    /// Vorhandene Backups, neuestes zuerst.
    public func entries() throws -> [Entry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls.compactMap(Self.entry(at:)).sorted { $0.date > $1.date }
    }

    /// Liest Zeitpunkt und Anlass aus dem Ordnernamen `<Zeitpunkt>_<Anlass>`.
    public static func entry(at url: URL) -> Entry? {
        let name = url.lastPathComponent
        guard let separator = name.firstIndex(of: "_"),
              let date = formatter.date(from: String(name[..<separator]))
        else { return nil }
        return Entry(url: url, date: date, kind: Kind(slug: name[name.index(after: separator)...]))
    }

    /// Behält je das neueste Backup der letzten 7 Tage mit Backup (Tages-Backups)
    /// und davor der 4 nächstälteren Wochen mit Backup (Wochen-Backups); Backups
    /// vor einer Migration, vor dem Umzug und beiseitegelegte immer. Backups vor dem Leeren des Papierkorbs zählen
    /// 30 Tage lang nicht mit (höchstens 10), der Stand vor dem Wiederherstellen
    /// 30 Tage lang gar nicht. Ein zum Wiederherstellen vorgemerktes Backup bleibt
    /// immer: Das Backup beim Beenden direkt danach verdrängt sonst ein Backup vom
    /// selben Tag. Entfernt Reste abgebrochener Backups.
    public func prune() throws {
        let fileManager = FileManager.default
        let pending = pendingRestoreBackupName
        var keep = Set<URL>()
        var days = Set<DateComponents>()
        var weeksWithDaily = Set<DateComponents>()
        var weeks = Set<DateComponents>()
        var trashBackups = 0
        // Neueste zuerst: Das erste Backup eines Tages oder einer Woche ist das neueste.
        for entry in try entries() {
            if entry.isBeforeMigration || entry.kind == .beforeMove || entry.kind == .setAside || entry.name == pending {
                keep.insert(entry.url)
                continue
            }
            if entry.kind == .beforeRestore, now().timeIntervalSince(entry.date) < Self.restoreBackupRetention {
                keep.insert(entry.url)
                continue
            }
            if entry.isBeforeEmptyingTrash, trashBackups < Self.trashBackupsToKeep,
               now().timeIntervalSince(entry.date) < Self.trashBackupRetention {
                trashBackups += 1
                keep.insert(entry.url)
                continue
            }
            let day = calendar.dateComponents([.year, .month, .day], from: entry.date)
            let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
            if days.count < Self.dailyBackupsToKeep || days.contains(day) {
                if days.insert(day).inserted {
                    weeksWithDaily.insert(week)
                    keep.insert(entry.url)
                }
            } else if weeks.count < Self.weeklyBackupsToKeep, !weeksWithDaily.contains(week),
                      weeks.insert(week).inserted {
                keep.insert(entry.url)
            }
        }
        for entry in try entries() where !keep.contains(entry.url) {
            try fileManager.removeItem(at: entry.url)
        }
        let leftovers = (try? fileManager.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? []
        for url in leftovers where url.lastPathComponent.hasSuffix(".partial") {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Dateien

    /// `.Quill_SUPPORT` neben `Quill.store` (so legt SwiftData externe Daten ab).
    var supportURL: URL {
        Self.supportURL(for: storeURL)
    }

    static func supportURL(for store: URL) -> URL {
        store.deletingLastPathComponent()
            .appending(path: ".\(store.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory)
    }

    var versionFileURL: URL {
        storeDirectoryURL.appending(path: "\(storeURL.lastPathComponent).version")
    }

    /// `<Zeitpunkt>_<Anlass>`.
    func backupName(_ reason: Reason, at date: Date) -> BackupName {
        BackupName("\(Self.formatter.string(from: date))_\(reason.slug)")
    }

    /// `name`, oder bei einem schon vorhandenen Backup gleichen Namens `name-2`, `name-3` …
    func uniqueBackupName(_ name: BackupName) -> BackupName {
        var candidate = name.rawValue
        var counter = 2
        while FileManager.default.fileExists(atPath: backupsURL.appending(path: candidate).path(percentEncoded: false)) {
            candidate = "\(name.rawValue)-\(counter)"
            counter += 1
        }
        return BackupName(candidate)
    }

    /// Zuletzt geöffnete Schema-Version, `nil` ohne Vermerk (z. B. von Hand eingespielt).
    public var lastOpenedSchemaVersion: String? {
        (try? Data(contentsOf: versionFileURL)).map { String(decoding: $0, as: UTF8.self) }
    }

    var storeExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false))
    }

    /// Jüngste Änderung an Store oder WAL.
    private var storeModificationDate: Date? {
        [storeURL, URL(filePath: storeURL.path(percentEncoded: false) + "-wal")]
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    /// UTC, ohne Doppelpunkte (Finder-tauglich), sekundengenau.
    static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter
    }

    // MARK: - SQLite

    static func vacuum(_ source: URL, into target: URL) throws {
        try withDatabase(source) { db in
            let escaped = target.path(percentEncoded: false).replacingOccurrences(of: "'", with: "''")
            try execute(db, "VACUUM INTO '\(escaped)'")
        }
    }

    /// `readOnly`: für Backups, die unverändert bleiben sollen. Eine schreibende
    /// Verbindung schriebe beim Schließen einen vorhandenen WAL in den Store zurück.
    static func quickCheck(_ database: URL, readOnly: Bool = false) throws {
        try withDatabase(database, readOnly: readOnly) { db in
            var statement: OpaquePointer?
            try check(sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil), db)
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_step(statement), db, accepting: SQLITE_ROW)
            let result = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            guard result == "ok" else { throw Error.integrityCheckFailed(result) }
        }
    }

    /// Öffnet ohne `CREATE`; `VACUUM INTO` liest die Quelle nur.
    private static func withDatabase(_ url: URL, readOnly: Bool = false, _ body: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(url.path(percentEncoded: false), &db, readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close_v2(db) }
        guard status == SQLITE_OK, let db else {
            throw Error.sqlite(code: status, message: String(cString: sqlite3_errstr(status)))
        }
        sqlite3_busy_timeout(db, 5_000)
        try body(db)
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil), db)
    }

    private static func check(_ status: Int32, _ db: OpaquePointer, accepting accepted: Int32 = SQLITE_OK) throws {
        guard status == accepted || status == SQLITE_DONE && accepted == SQLITE_OK else {
            throw Error.sqlite(code: status, message: String(cString: sqlite3_errmsg(db)))
        }
    }
}
