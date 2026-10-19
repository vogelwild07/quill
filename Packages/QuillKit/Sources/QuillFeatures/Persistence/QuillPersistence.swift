import Foundation
import OSLog
import QuillModel
import SwiftData
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Öffnet die Datenbank der App samt Backups (ADR-010) und hält Container und Store.
@MainActor
public final class QuillPersistence {
    /// Startargument `-QuillInMemoryStore YES`: Daten nur im Arbeitsspeicher, keine
    /// Backups. Für UI-Tests, damit sie nie die echten Daten berühren.
    public static let inMemoryArgument = "QuillInMemoryStore"
    /// Startargument `-QuillStoreDirectory <Name>`: Store und Backups in diesem
    /// Unterordner des temporären Ordners der App. Für UI-Tests, die Backups und
    /// Wiederherstellen über Neustarts brauchen (ADR-019); nie der echte Store.
    public static let storeDirectoryArgument = "QuillStoreDirectory"

    /// Speicher für UI-Tests statt des echten Stores.
    enum TestStore: Equatable {
        case inMemory
        case directory(String)
    }

    /// Liest die Startargumente für UI-Tests nur aus der Kommandozeile, nie aus
    /// gespeicherten Einstellungen: Ein `defaults write` darf den echten Store nicht
    /// still durch einen leeren ersetzen. In Release-Builds immer `nil`.
    static func testStore(arguments: [String]) -> TestStore? {
        #if DEBUG
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let flag = value(inMemoryArgument), ["YES", "1", "true"].contains(flag) {
            return .inMemory
        }
        if let name = value(storeDirectoryArgument), !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") {
            return .directory(name)
        }
        #endif
        return nil
    }

    public let container: ModelContainer
    public let store: PageStore
    public let isInMemory: Bool
    private let backup: StoreBackup?
    /// Ergebnis einer beim Start eingespielten Wiederherstellung, bis es angezeigt wurde.
    private var restoreOutcome: RestoreOutcome?

    private nonisolated static let logger = Logger(subsystem: "de.vogel.quill", category: "persistence")

    /// Seiten liegen so lange im Papierkorb, dann löscht Quill sie endgültig.
    public nonisolated static let trashRetentionDays = 30
    public nonisolated static let trashRetention = TimeInterval(trashRetentionDays * 24 * 60 * 60)

    init(container: ModelContainer, backup: StoreBackup?, restoreOutcome: RestoreOutcome? = nil) {
        self.container = container
        self.store = PageStore(modelContainer: container)
        self.backup = backup
        self.isInMemory = backup == nil
        self.restoreOutcome = restoreOutcome
    }

    /// Öffnet den Store. Vor einer Migration muss das Backup gelingen, sonst wird
    /// nicht geöffnet; andere Backup-Fehler werden nur protokolliert.
    public static func open(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> QuillPersistence {
        let testStore = testStore(arguments: arguments)
        if testStore == .inMemory {
            logger.notice("Store nur im Arbeitsspeicher (\(inMemoryArgument, privacy: .public))")
            return QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        }

        let backup = makeBackup(testStore)
        // Vor allem anderen: unter Sperre umziehen und ein vorgemerktes Backup
        // einspielen (ADR-019). Scheitert das, wird nicht geöffnet.
        let restoreOutcome = try backup.prepareStore()
        if let restoreOutcome {
            logger.notice("Wiederherstellen: \(String(describing: restoreOutcome), privacy: .private)")
        }
        do {
            if let folder = try backup.backupBeforeOpening() {
                logger.notice("Backup angelegt: \(folder.lastPathComponent, privacy: .public)")
            }
        } catch {
            logger.error("Backup beim Start fehlgeschlagen: \(error, privacy: .public)")
            if backup.isMigrationPending { throw error }
        }
        let container = try QuillStore.makeContainer(storeURL: backup.storeURL)
        do {
            try backup.markOpened()
        } catch {
            logger.error("Schema-Version nicht gespeichert: \(error, privacy: .public)")
        }
        let persistence = QuillPersistence(container: container, backup: backup, restoreOutcome: restoreOutcome)
        persistence.removeOrphanedAssets()
        persistence.scheduleTrashAutoEmpty()
        return persistence
    }

    /// Echter Store, oder für UI-Tests einer im temporären Ordner der App.
    private static func makeBackup(_ testStore: TestStore?) -> StoreBackup {
        guard case .directory(let name) = testStore else { return StoreBackup() }
        let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        logger.notice("Store im temporären Ordner (\(storeDirectoryArgument, privacy: .public))")
        return StoreBackup(
            storeURL: directory.appending(path: "Store/Quill.store", directoryHint: .notDirectory),
            backupsURL: directory.appending(path: "Backups", directoryHint: .isDirectory)
        )
    }

    // MARK: Wiederherstellen (ADR-019)

    /// Ob Backups wiederhergestellt werden können (nicht bei einem Store nur im Arbeitsspeicher).
    public var canRestoreBackups: Bool { backup != nil }

    /// Vorhandene Backups, neuestes zuerst, mit Größe.
    public func backupEntries() async throws -> [BackupListEntry] {
        guard let backup else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            try backup.entries().map { BackupListEntry(entry: $0, size: StoreBackup.size(of: $0.url)) }
        }.value
    }

    /// Prüft das Backup und merkt es für den nächsten Start vor; danach beendet
    /// sich die App. Wirft, wenn es nicht eingespielt werden kann.
    public func requestRestore(_ entry: StoreBackup.Entry) async throws {
        guard let backup else { return }
        try await Task.detached(priority: .userInitiated) { try backup.requestRestore(entry) }.value
    }

    /// Ergebnis der Wiederherstellung beim Start, einmal: Das erste Fenster zeigt es.
    public func takeRestoreOutcome() -> RestoreOutcome? {
        defer { restoreOutcome = nil }
        return restoreOutcome
    }

    /// Bilder, die seit 30 Tagen keinem Block mehr gehören (ADR-015). Läuft nach dem
    /// Backup beim Start, damit ein versehentlich gelöschtes Bild dort noch liegt.
    private func removeOrphanedAssets() {
        let store = store
        Task.detached(priority: .utility) {
            do {
                let count = try await store.removeOrphanedAssets()
                if count > 0 { Self.logger.notice("Verwaiste Bilder gelöscht: \(count)") }
            } catch {
                Self.logger.error("Aufräumen der Bilder fehlgeschlagen: \(error, privacy: .public)")
            }
        }
    }

    // MARK: Papierkorb (ADR-017)

    /// Löscht Seiten aus dem Papierkorb endgültig, in einem Schritt. Vorher ein Backup, außer der
    /// Store ist seit dem letzten unverändert; scheitert es, wird nichts gelöscht.
    public func deletePermanently(_ pageIDs: [UUID]) async throws {
        try await backupBeforeEmptyingTrash()
        try await store.deletePermanently(pageIDs)
    }

    /// Leert den Papierkorb ganz; vorher ein Backup wie bei `deletePermanently`.
    @discardableResult
    public func emptyTrash() async throws -> Int {
        try await backupBeforeEmptyingTrash()
        return try await store.emptyTrash()
    }

    /// Löscht Seiten, die länger als 30 Tage im Papierkorb liegen. Ohne Backup
    /// wird nichts gelöscht; dann beim nächsten Mal wieder.
    func emptyExpiredTrash(now: Date = .now) async {
        do {
            guard try await store.trashCount(olderThan: Self.trashRetention, now: now) > 0 else { return }
            try await backupBeforeEmptyingTrash()
            let count = try await store.emptyTrash(olderThan: Self.trashRetention, now: now)
            if count > 0 { Self.logger.notice("Papierkorb: \(count) alte Seiten gelöscht") }
        } catch {
            Self.logger.error("Auto-Leeren des Papierkorbs fehlgeschlagen: \(error, privacy: .public)")
        }
    }

    /// Beim Start (nach dem Start-Backup) und danach einmal täglich.
    private func scheduleTrashAutoEmpty() {
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.emptyExpiredTrash()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    private func backupBeforeEmptyingTrash() async throws {
        guard let backup else { return }
        if let folder = try await Task.detached(priority: .userInitiated, operation: { try backup.backupBeforeEmptyingTrash() }).value {
            Self.logger.notice("Backup vor dem Leeren: \(folder.lastPathComponent, privacy: .public)")
        }
    }

    /// Beim Beenden: Backup, falls sich seit dem letzten etwas geändert hat.
    public func backupOnQuit() {
        guard let backup else { return }
        do {
            if let folder = try backup.backupOnQuitIfChanged() {
                Self.logger.notice("Backup beim Beenden: \(folder.lastPathComponent, privacy: .public)")
            }
        } catch {
            Self.logger.error("Backup beim Beenden fehlgeschlagen: \(error, privacy: .public)")
        }
    }

    #if canImport(AppKit)
    /// Öffnet den Backup-Ordner im Finder (legt ihn bei Bedarf an).
    public func revealBackups() {
        guard let backup else { return }
        try? FileManager.default.createDirectory(at: backup.backupsURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backup.backupsURL)
    }
    #endif
}

/// Ein Backup in der Liste „Backup wiederherstellen“.
public struct BackupListEntry: Identifiable, Equatable, Sendable {
    public let entry: StoreBackup.Entry
    /// Belegter Platz in Bytes.
    public let size: Int64

    public var id: String { entry.id }
}

extension EnvironmentValues {
    /// Schreibzugriff auf Seiten; `nil` nur in Previews ohne Store.
    @Entry public var pageStore: PageStore?
    /// Für endgültiges Löschen mit Backup; `nil` nur in Previews ohne Store.
    @Entry public var quillPersistence: QuillPersistence?
}
