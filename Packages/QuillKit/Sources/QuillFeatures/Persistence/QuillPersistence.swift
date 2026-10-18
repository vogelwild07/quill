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

    public let container: ModelContainer
    public let store: PageStore
    public let isInMemory: Bool
    private let backup: StoreBackup?

    private nonisolated static let logger = Logger(subsystem: "de.vogel.quill", category: "persistence")

    /// Seiten liegen so lange im Papierkorb, dann löscht Quill sie endgültig.
    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    init(container: ModelContainer, backup: StoreBackup?) {
        self.container = container
        self.store = PageStore(modelContainer: container)
        self.backup = backup
        self.isInMemory = backup == nil
    }

    /// Öffnet den Store. Vor einer Migration muss das Backup gelingen, sonst wird
    /// nicht geöffnet; andere Backup-Fehler werden nur protokolliert.
    public static func open(defaults: UserDefaults = .standard) throws -> QuillPersistence {
        if defaults.bool(forKey: inMemoryArgument) {
            logger.notice("Store nur im Arbeitsspeicher (\(inMemoryArgument, privacy: .public))")
            return QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        }

        let backup = StoreBackup()
        do {
            if let folder = try backup.backupBeforeOpening() {
                logger.notice("Backup angelegt: \(folder.lastPathComponent, privacy: .public)")
            }
        } catch {
            logger.error("Backup beim Start fehlgeschlagen: \(error, privacy: .public)")
            if backup.isMigrationPending { throw error }
        }
        let container = try QuillStore.makeContainer()
        do {
            try backup.markOpened()
        } catch {
            logger.error("Schema-Version nicht gespeichert: \(error, privacy: .public)")
        }
        let persistence = QuillPersistence(container: container, backup: backup)
        persistence.removeOrphanedAssets()
        persistence.scheduleTrashAutoEmpty()
        return persistence
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

    /// Löscht eine Seite aus dem Papierkorb endgültig. Vorher ein Backup (höchstens
    /// eins pro Stunde); scheitert es, wird nichts gelöscht.
    public func deletePermanently(_ pageID: UUID) async throws {
        try await backupBeforeEmptyingTrash()
        try await store.deletePermanently(pageID)
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

extension EnvironmentValues {
    /// Schreibzugriff auf Seiten; `nil` nur in Previews ohne Store.
    @Entry public var pageStore: PageStore?
    /// Für endgültiges Löschen mit Backup; `nil` nur in Previews ohne Store.
    @Entry public var quillPersistence: QuillPersistence?
}
