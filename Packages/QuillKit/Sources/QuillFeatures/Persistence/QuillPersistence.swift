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
    #if DEBUG
    /// Startargument `-QuillInMemoryStore YES`: Daten nur im Arbeitsspeicher, keine
    /// Backups. Für UI-Tests, damit sie nie die echten Daten berühren. Nur in Debug,
    /// damit Release den Namen nicht enthält (`check-release-binary.sh`).
    public static let inMemoryArgument = "QuillInMemoryStore"
    /// Startargument `-QuillStoreDirectory <Name>`: Store und Backups in diesem
    /// Unterordner des temporären Ordners der App. Für UI-Tests, die Backups und
    /// Wiederherstellen über Neustarts brauchen (ADR-019); nie der echte Store.
    public static let storeDirectoryArgument = "QuillStoreDirectory"
    /// Startargument `-QuillSeedSchemaV1 YES`, nur mit `-QuillStoreDirectory`: legt dort
    /// vor dem Öffnen einen Store im alten Format V1 an, falls noch keiner liegt (Phase 11.2).
    public static let seedSchemaV1Argument = "QuillSeedSchemaV1"
    /// Startargument `-QuillAskBeforeMigration YES`, nur mit `-QuillStoreDirectory`: fragt
    /// auch beim Test-Store vor einer Migration, wie beim echten Store.
    public static let askBeforeMigrationArgument = "QuillAskBeforeMigration"
    #endif

    public enum OpenError: Error, Equatable {
        /// Der Nutzer hat die Umstellung auf ein neues Schema abgelehnt; nichts wurde
        /// verändert, auch kein Backup angelegt. Die App beendet sich.
        case migrationDeclined
        /// Eine Umstellung steht an, gefragt wird später (`MigrationAnswer.later`);
        /// nichts wurde verändert.
        case migrationDeferred
    }

    /// Antwort auf die Rückfrage vor einer Migration.
    public enum MigrationAnswer: Sendable {
        case migrate
        case quit
        /// Jetzt nicht fragen, z. B. weil die App noch startet und kein Dialog
        /// bedienbar wäre; `open` wirft `OpenError.migrationDeferred`.
        case later
    }

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

    /// Ob vor einer Migration gefragt wird: beim echten Store immer, bei Test-Stores
    /// nur mit `-QuillAskBeforeMigration YES` (sonst liefen UI-Tests in den Dialog).
    static func asksBeforeMigration(_ testStore: TestStore?, arguments: [String]) -> Bool {
        guard let testStore else { return true }
        #if DEBUG
        if case .directory = testStore, flag(askBeforeMigrationArgument, in: arguments) { return true }
        #endif
        return false
    }

    #if DEBUG
    private static func flag(_ name: String, in arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return false }
        return ["YES", "1", "true"].contains(arguments[index + 1])
    }
    #endif

    public let container: ModelContainer
    public let store: PageStore
    public let isInMemory: Bool
    private let backup: StoreBackup?
    /// Was beim Start vorbereitet wurde (Wiederherstellen, Beiseitelegen), bis es
    /// angezeigt wurde.
    private var preparation: StorePreparation?

    private nonisolated static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "persistence")

    /// Seiten liegen so lange im Papierkorb, dann löscht Quill sie endgültig.
    public nonisolated static let trashRetentionDays = 30
    public nonisolated static let trashRetention = TimeInterval(trashRetentionDays * 24 * 60 * 60)

    init(container: ModelContainer, backup: StoreBackup?, preparation: StorePreparation? = nil) {
        self.container = container
        self.store = PageStore(modelContainer: container)
        self.backup = backup
        self.isInMemory = backup == nil
        self.preparation = preparation
    }

    /// Öffnet den Store. Steht eine Migration an, fragt zuerst `confirmMigration`
    /// (bisherige Version oder `nil`, neue Version); lehnt der Nutzer ab oder kommt die
    /// Antwort später, wirft `OpenError`, ohne etwas zu verändern. Vor einer Migration muss
    /// das Backup gelingen, sonst wird nicht geöffnet; andere Backup-Fehler werden nur
    /// protokolliert.
    public static func open(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        confirmMigration: @MainActor (_ from: String?, _ to: String) -> MigrationAnswer
    ) throws -> QuillPersistence {
        let testStore = testStore(arguments: arguments)
        #if DEBUG
        if testStore == .inMemory {
            logger.notice("Store nur im Arbeitsspeicher (\(inMemoryArgument, privacy: .public))")
            return QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        }
        #endif

        let backup = makeBackup(testStore)
        #if DEBUG
        if case .directory = testStore, flag(seedSchemaV1Argument, in: arguments) {
            try SchemaV1Seed.write(storeURL: backup.storeURL, backupsURL: backup.backupsURL)
        }
        #endif
        // Vor allem anderen: unter Sperre umziehen und ein vorgemerktes Backup
        // einspielen (ADR-019). Scheitert das, wird nicht geöffnet.
        let preparation = try backup.prepareStore()
        if preparation != StorePreparation() {
            logger.notice("Vorbereitet: \(String(describing: preparation), privacy: .private)")
        }
        // Erst nach dem Einspielen fragen: Ein eingespieltes V1-Backup ist wieder V1,
        // und „Beenden“ lässt es so, damit eine ältere Version es öffnen kann (ADR-029).
        if backup.isMigrationPending, asksBeforeMigration(testStore, arguments: arguments) {
            switch confirmMigration(backup.lastOpenedSchemaVersion, QuillStore.schemaVersion) {
            case .migrate:
                break
            case .quit:
                logger.notice("Migration abgelehnt, nichts verändert")
                throw OpenError.migrationDeclined
            case .later:
                throw OpenError.migrationDeferred
            }
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
        let persistence = QuillPersistence(container: container, backup: backup, preparation: preparation)
        persistence.removeOrphanedAssets()
        persistence.scheduleTrashAutoEmpty()
        return persistence
    }

    /// Echter Store, oder für UI-Tests einer im temporären Ordner der App.
    private static func makeBackup(_ testStore: TestStore?) -> StoreBackup {
        #if DEBUG
        if case .directory(let name) = testStore {
            let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
            logger.notice("Store im temporären Ordner (\(storeDirectoryArgument, privacy: .public))")
            return StoreBackup(
                storeURL: directory.appending(path: "Store/Quill.store", directoryHint: .notDirectory),
                backupsURL: directory.appending(path: "Backups", directoryHint: .isDirectory)
            )
        }
        #endif
        return StoreBackup()
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

    /// Das Beenden wurde abgebrochen (Rückfrage bei ungespeicherten Änderungen): Ein
    /// vorgemerktes Backup würde sonst beim nächsten Start unbemerkt eingespielt.
    /// Nimmt die Vormerkung zurück und meldet es über `notify` (Titel, Text).
    public func quitWasCancelled(notify: @MainActor (String, String) -> Void = QuillPersistence.showAlert) {
        guard let backup else { return }
        do {
            guard try backup.withdrawRestoreRequest() else { return }
            notify(
                String(localized: "Wiederherstellen abgebrochen", bundle: .module),
                String(localized: "Quill wurde nicht beendet. Das Backup ist nicht mehr vorgemerkt, der aktuelle Stand bleibt. Wähle es bei Bedarf erneut über Ablage › Backup wiederherstellen …", bundle: .module)
            )
        } catch {
            Self.logger.error("Vormerkung nicht zurückgenommen: \(error, privacy: .public)")
            notify(
                String(localized: "Backup bleibt vorgemerkt", bundle: .module),
                String(localized: "Die Vormerkung ließ sich nicht zurücknehmen. Beim nächsten Start wird das gewählte Backup eingespielt; der aktuelle Stand bleibt dann als Backup „Vor dem Wiederherstellen“.", bundle: .module)
            )
        }
    }

    public static func showAlert(title: String, message: String) {
        #if canImport(AppKit)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
        #endif
    }

    /// Was beim Start vorbereitet wurde, einmal: Das erste Fenster zeigt es.
    public func takePreparation() -> StorePreparation? {
        defer { preparation = nil }
        return preparation == StorePreparation() ? nil : preparation
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

    // MARK: Sync (ADR-029)

    /// Backup vor dem Einschalten des Sync, der Rückweg; `nil` bei einem Store nur im
    /// Arbeitsspeicher. Scheitert es, bleibt der Sync aus.
    public func backupBeforeSync() async throws -> URL? {
        guard let backup else { return nil }
        let folder = try await Task.detached(priority: .userInitiated) { try backup.backupBeforeSync() }.value
        if let folder { Self.logger.notice("Backup vor dem Sync: \(folder.lastPathComponent, privacy: .public)") }
        return folder
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
