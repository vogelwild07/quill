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

    private init(container: ModelContainer, backup: StoreBackup?) {
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
}
