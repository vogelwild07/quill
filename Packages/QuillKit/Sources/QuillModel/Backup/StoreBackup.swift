import Foundation
import SQLite3

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

        var slug: String {
            switch self {
            case .launch: "start"
            case .quit: "beenden"
            case .beforeMigration(let from, let to): "\(Self.migrationPrefix)\(from)-\(to)"
            case .beforeEmptyingTrash: "vor-papierkorb-leeren"
            }
        }

        static let migrationPrefix = "vor-migration-"
    }

    public enum Error: Swift.Error, Equatable {
        case sqlite(code: Int32, message: String)
        case integrityCheckFailed(String)
    }

    /// Ein vorhandenes Backup.
    public struct Entry: Sendable, Equatable {
        public let url: URL
        public let date: Date
        public let isBeforeMigration: Bool
        public let isBeforeEmptyingTrash: Bool
    }

    public let storeURL: URL
    public let backupsURL: URL
    public let schemaVersion: String
    public var calendar: Calendar
    public var now: @Sendable () -> Date

    public static let dailyBackupsToKeep = 7
    public static let weeklyBackupsToKeep = 4
    public static let launchInterval: TimeInterval = 24 * 60 * 60
    /// Backups vor dem Leeren des Papierkorbs: so lange und höchstens so viele,
    /// zusätzlich zu den regulären (ADR-017).
    public static let trashBackupRetention: TimeInterval = 30 * 24 * 60 * 60
    public static let trashBackupsToKeep = 10

    public init(
        storeURL: URL = QuillStore.defaultStoreURL,
        backupsURL: URL = QuillStore.directoryURL.appending(path: "Backups", directoryHint: .isDirectory),
        schemaVersion: String = QuillStore.schemaVersion,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.storeURL = storeURL
        self.backupsURL = backupsURL
        self.schemaVersion = schemaVersion
        self.calendar = calendar
        self.now = now
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
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        let date = now()
        let name = "\(Self.formatter.string(from: date))_\(reason.slug)"
        let partial = backupsURL.appending(path: ".\(name).partial", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: partial)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)

        do {
            let target = partial.appending(path: storeURL.lastPathComponent)
            try Self.vacuum(storeURL, into: target)
            try Self.quickCheck(target)
            if fileManager.fileExists(atPath: supportURL.path(percentEncoded: false)) {
                try fileManager.copyItem(at: supportURL, to: partial.appending(path: supportURL.lastPathComponent))
            }
            var final = backupsURL.appending(path: name, directoryHint: .isDirectory)
            var counter = 2
            while fileManager.fileExists(atPath: final.path(percentEncoded: false)) {
                final = backupsURL.appending(path: "\(name)-\(counter)", directoryHint: .isDirectory)
                counter += 1
            }
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
        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard let separator = name.firstIndex(of: "_"),
                  let date = Self.formatter.date(from: String(name[..<separator]))
            else { return nil }
            let reason = name[name.index(after: separator)...]
            return Entry(
                url: url, date: date, isBeforeMigration: reason.hasPrefix(Reason.migrationPrefix),
                isBeforeEmptyingTrash: reason.hasPrefix(Reason.beforeEmptyingTrash.slug)
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Behält je das neueste Backup der letzten 7 Tage mit Backup (Tages-Backups)
    /// und davor der 4 nächstälteren Wochen mit Backup (Wochen-Backups); Backups
    /// vor einer Migration immer. Backups vor dem Leeren des Papierkorbs zählen
    /// 30 Tage lang nicht mit (höchstens 10). Entfernt Reste abgebrochener Backups.
    public func prune() throws {
        let fileManager = FileManager.default
        var keep = Set<URL>()
        var days = Set<DateComponents>()
        var weeksWithDaily = Set<DateComponents>()
        var weeks = Set<DateComponents>()
        var trashBackups = 0
        // Neueste zuerst: Das erste Backup eines Tages oder einer Woche ist das neueste.
        for entry in try entries() {
            if entry.isBeforeMigration {
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
        storeURL.deletingLastPathComponent()
            .appending(path: ".\(storeURL.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory)
    }

    var versionFileURL: URL {
        storeURL.deletingLastPathComponent().appending(path: "\(storeURL.lastPathComponent).version")
    }

    var lastOpenedSchemaVersion: String? {
        (try? Data(contentsOf: versionFileURL)).map { String(decoding: $0, as: UTF8.self) }
    }

    private var storeExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false))
    }

    /// Jüngste Änderung an Store oder WAL.
    private var storeModificationDate: Date? {
        [storeURL, URL(filePath: storeURL.path(percentEncoded: false) + "-wal")]
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    /// UTC, ohne Doppelpunkte (Finder-tauglich), sekundengenau.
    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter
    }

    // MARK: - SQLite

    private static func vacuum(_ source: URL, into target: URL) throws {
        try withDatabase(source) { db in
            let escaped = target.path(percentEncoded: false).replacingOccurrences(of: "'", with: "''")
            try execute(db, "VACUUM INTO '\(escaped)'")
        }
    }

    private static func quickCheck(_ database: URL) throws {
        try withDatabase(database) { db in
            var statement: OpaquePointer?
            try check(sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil), db)
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_step(statement), db, accepting: SQLITE_ROW)
            let result = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            guard result == "ok" else { throw Error.integrityCheckFailed(result) }
        }
    }

    /// Öffnet ohne `CREATE`; `VACUUM INTO` liest die Quelle nur.
    private static func withDatabase(_ url: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(url.path(percentEncoded: false), &db, SQLITE_OPEN_READWRITE, nil)
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
