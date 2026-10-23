import Foundation
import OSLog
import QuillAI
import QuillEditorCore
import QuillModel
import QuillSync
import SwiftData
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Öffnet die Datenbank der App samt Backups (ADR-010) und hält Container und Store.
@MainActor
public final class QuillPersistence {
    #if DEBUG || QUILL_SYNCTEST
    /// Startargument `-QuillInMemoryStore YES`: Daten nur im Arbeitsspeicher, keine
    /// Backups. Für UI-Tests, damit sie nie die echten Daten berühren. Nur in Debug und
    /// in den Testvarianten Synctest A und B (`QUILL_SYNCTEST`, `Scripts/make-synctest.sh`),
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
    /// Startargument `-QuillSyncTestFolder <Name>`, nur mit einem Test-Store: „Ordner
    /// wählen“ nimmt ohne Dateiauswahl diesen Unterordner des temporären Ordners der App.
    public static let syncTestFolderArgument = "QuillSyncTestFolder"
    /// Startargument `-QuillSyncSharedFolder <Name>`, nur mit einem Test-Store: „Ordner
    /// wählen“ nimmt ohne Dateiauswahl `<Benutzerordner>/<syncSharedFolderRoot>/<Name>`.
    /// Für `SyncTwoAppsUITests`: Synctest A und B teilen sich so einen Wegwerf-Ordner im
    /// temporären Ordner des UI-Test-Runners, den nur ihre Entitlements freigeben
    /// (`App/QuillSynctest.entitlements`). Nur ein Name, nie ein Pfad.
    public static let syncSharedFolderArgument = "QuillSyncSharedFolder"
    /// Startargument `-QuillSyncHaltBeforePage <n>`, nur mit einem Test-Store: Der Abgleich
    /// hält vor dem Schreiben der n-ten Seite in den Store an (Fall 12, `SyncEngine`).
    public static let syncHaltArgument = "QuillSyncHaltBeforePage"
    /// Startargument `-QuillSaveDelay <ms>`, nur mit einem Test-Store: Editoren warten so
    /// lange vor dem Speichern (Fall 14, `EditorPersistenceBridge.testDelay`).
    public static let saveDelayArgument = "QuillSaveDelay"
    /// Startargument `-QuillSyncDeviceName <Name>`, nur mit einem Test-Store: Gerätename
    /// im Ordner statt des Mac-Namens; Synctest A und B laufen auf demselben Mac (11.6).
    public static let syncDeviceNameArgument = "QuillSyncDeviceName"
    /// Startargument `-QuillSeedTimeTravel YES`, nur Debug und nur mit einem Test-Store:
    /// legt eine Seite mit Geschichte über drei Tage an (`TimeTravelSeed`, 12.3).
    public static let seedTimeTravelArgument = "QuillSeedTimeTravel"
    /// Nur Debug, nur Test-Store: Test-Modell statt Apple Intelligence (ADR-032). Wert
    /// `available` oder ein anderer Fall von `AIAvailability`, um die Erklärung zu prüfen.
    public static let fakeAIArgument = "QuillFakeAI"
    /// Relativ zum Benutzerordner; steht genauso in `App/QuillSynctest.entitlements`.
    public static let syncSharedFolderRoot = "Library/Containers/io.github.vogelwild07.quill.UITests.xctrunner/Data/tmp/QuillSyncUITests"
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
        #if DEBUG || QUILL_SYNCTEST
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
        #if DEBUG || QUILL_SYNCTEST
        if case .directory = testStore, flag(askBeforeMigrationArgument, in: arguments) { return true }
        #endif
        return false
    }

    #if DEBUG || QUILL_SYNCTEST
    private static func flag(_ name: String, in arguments: [String]) -> Bool {
        guard let index = arguments.firstIndex(of: "-\(name)"), arguments.indices.contains(index + 1) else { return false }
        return ["YES", "1", "true"].contains(arguments[index + 1])
    }
    #endif

    public let container: ModelContainer
    public let store: PageStore
    public let isInMemory: Bool
    /// Ordner-Sync (ADR-029); aus, bis der Nutzer ihn einschaltet.
    public private(set) lazy var sync = SyncController(
        store: store, settings: SyncSettings(storage: syncStorage),
        backupBeforeSync: { [unowned self] in try await self.backupBeforeSync() },
        deviceName: syncDeviceName
    )
    /// Geschichte der Seiten für die Zeitreise (ADR-031), auch ohne Sync; zeichnet ab
    /// `history.start()` auf.
    public private(set) lazy var history = HistoryObserver(recorder: HistoryRecorder(store: store))
    /// Frist für Bilder ohne Block (12.4, ADR-031); beim echten Store in den Einstellungen
    /// des Macs, bei Test-Stores nur bis zum Beenden.
    public let imageRetention: ImageRetentionSettings
    /// KI-Funktionen (ADR-032); Wahl wie bei der Frist für Bilder nur beim echten Store
    /// in den Einstellungen des Macs. Die Verfügbarkeit prüft `AISettings` im Hintergrund.
    public private(set) lazy var ai = AISettings(defaults: settingsDefaults)
    /// Seiten in Spotlight (ADR-033); Test-Stores nur in einen Index im Speicher.
    public private(set) lazy var spotlight = SpotlightIndexing(
        store: store, index: isTestStore ? MemorySpotlightIndex() : SystemSpotlightIndex(), defaults: settingsDefaults
    )
    /// Schnellnotiz (ADR-033); Wahl wie bei Spotlight nur beim echten Store gespeichert.
    public private(set) lazy var quickNote = QuickNote(store: store, defaults: settingsDefaults)
    /// Erinnerungen an To-dos (ADR-033); Test-Stores planen nur in einen Ersatz im Speicher.
    public private(set) lazy var reminders = Reminders(
        store: store, center: isTestStore ? MemoryReminderCenter() : SystemReminderCenter()
    )
    #if DEBUG || QUILL_SYNCTEST
    /// Nur für Tests: Gerätename statt des Mac-Namens (`syncDeviceNameArgument`).
    private var testDeviceName: String?
    #endif

    private var syncDeviceName: String {
        #if DEBUG || QUILL_SYNCTEST
        testDeviceName ?? SyncController.defaultDeviceName
        #else
        SyncController.defaultDeviceName
        #endif
    }
    /// Nur für UI-Tests: Ordner statt der Dateiauswahl (`syncTestFolderArgument`).
    public let syncTestFolder: URL?
    private let syncStorage: any SyncSettingsStorage
    private let settingsDefaults: UserDefaults?
    /// Test-Stores schreiben nichts außerhalb des Stores, auch nicht an Siri oder Spotlight
    /// (ADR-033): Debug-Builds haben dieselbe Kennung wie die echte App.
    public var isTestStore: Bool { settingsDefaults == nil }
    private var syncReconnectPromptClaimed = false
    private let backup: StoreBackup?
    /// Was beim Start vorbereitet wurde (Wiederherstellen, Beiseitelegen), bis es
    /// angezeigt wurde.
    private var preparation: StorePreparation?

    private nonisolated static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "persistence")

    /// Seiten liegen so lange im Papierkorb, dann löscht Quill sie endgültig.
    public nonisolated static let trashRetentionDays = 30
    public nonisolated static let trashRetention = TimeInterval(trashRetentionDays * 24 * 60 * 60)

    init(
        container: ModelContainer, backup: StoreBackup?, preparation: StorePreparation? = nil,
        syncStorage: any SyncSettingsStorage = MemorySyncSettingsStorage(), syncTestFolder: URL? = nil,
        settingsDefaults: UserDefaults? = nil
    ) {
        self.container = container
        self.imageRetention = ImageRetentionSettings(defaults: settingsDefaults)
        self.settingsDefaults = settingsDefaults
        self.store = PageStore(modelContainer: container)
        self.syncStorage = syncStorage
        self.syncTestFolder = syncTestFolder
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
        #if DEBUG || QUILL_SYNCTEST
        if testStore == .inMemory {
            logger.notice("Store nur im Arbeitsspeicher (\(inMemoryArgument, privacy: .public))")
            let persistence = QuillPersistence(
                container: try QuillStore.makeInMemoryContainer(), backup: nil,
                syncTestFolder: syncTestFolder(arguments: arguments)
            )
            configureTestHooks(persistence, arguments: arguments)
            return persistence
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
        let persistence = QuillPersistence(
            container: container, backup: backup, preparation: preparation,
            syncStorage: syncStorage(testStore), syncTestFolder: testStore == nil ? nil : syncTestFolder(arguments: arguments),
            settingsDefaults: settingsDefaults(testStore)
        )
        #if DEBUG || QUILL_SYNCTEST
        if testStore != nil { configureTestHooks(persistence, arguments: arguments) }
        #endif
        persistence.removeOrphanedAssets()
        persistence.scheduleTrashAutoEmpty()
        return persistence
    }

    /// Nur ein Fenster fragt nach einem eingespielten Backup, wie der Sync weitergeht.
    func claimSyncReconnectPrompt() -> Bool {
        guard !syncReconnectPromptClaimed else { return false }
        syncReconnectPromptClaimed = true
        return true
    }

    /// Einstellungen des Sync: beim echten Store in den Einstellungen des Macs, bei
    /// einem Test-Store in dessen Ordner.
    private static func syncStorage(_ testStore: TestStore?) -> any SyncSettingsStorage {
        #if DEBUG || QUILL_SYNCTEST
        if case .directory(let name) = testStore {
            return FileSyncSettingsStorage(url: FileManager.default.temporaryDirectory.appending(path: "\(name)/sync-settings.json"))
        }
        #endif
        return UserDefaults.standard
    }

    /// Frist für Bilder und KI: nur der echte Store liest und speichert sie in den
    /// Einstellungen des Macs. Test-Stores nie, denn Debug-Builds teilen sie mit der echten App.
    static func settingsDefaults(_ testStore: TestStore?) -> UserDefaults? {
        testStore == nil ? .standard : nil
    }

    private static func syncTestFolder(arguments: [String]) -> URL? {
        #if DEBUG || QUILL_SYNCTEST
        func name(_ argument: String) -> String? {
            guard let index = arguments.firstIndex(of: "-\(argument)"), arguments.indices.contains(index + 1) else { return nil }
            let name = arguments[index + 1]
            return name.isEmpty || name.contains("/") || name.hasPrefix(".") ? nil : name
        }
        let folder: URL
        if let shared = name(syncSharedFolderArgument) {
            folder = syncSharedFolder(shared)
        } else if let local = name(syncTestFolderArgument) {
            folder = FileManager.default.temporaryDirectory.appending(path: local, directoryHint: .isDirectory)
        } else {
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
        #else
        return nil
        #endif
    }

    #if DEBUG || QUILL_SYNCTEST
    /// Gerätename, Haltepunkt im Abgleich und Wartezeit vor dem Speichern, nur mit einem Test-Store.
    private static func configureTestHooks(_ persistence: QuillPersistence, arguments: [String]) {
        func value(_ argument: String) -> String? {
            guard let index = arguments.firstIndex(of: "-\(argument)"), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        func number(_ argument: String) -> Int? {
            value(argument).flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        }
        // Vor dem ersten Zugriff auf `sync`, der den Namen übernimmt.
        persistence.testDeviceName = value(syncDeviceNameArgument).flatMap { $0.isEmpty ? nil : $0 }
        persistence.sync.testHaltBeforeStoringPage = number(syncHaltArgument)
        EditorPersistenceBridge.testDelay = number(saveDelayArgument).map { .milliseconds($0) }
        #if DEBUG
        if let fake = value(fakeAIArgument).flatMap(AIAvailability.init(rawValue:)) {
            persistence.ai = AISettings(defaults: nil, model: TestTextModel(), availability: { fake })
        }
        if flag(seedTimeTravelArgument, in: arguments) {
            let store = persistence.store
            Task {
                do { try await TimeTravelSeed.write(to: store) } catch { logger.error("Zeitreise-Testseite: \(error, privacy: .public)") }
            }
        }
        #endif
    }

    /// Der gemeinsame Ordner zu `-QuillSyncSharedFolder <name>`. Der Benutzerordner kommt
    /// aus der Benutzerdatenbank, nicht aus `NSHomeDirectory()`: Das ist in der Sandbox
    /// der Container der App.
    static func syncSharedFolder(_ name: String, home: URL = realHomeDirectory) -> URL {
        home.appending(path: syncSharedFolderRoot, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
    }

    private static var realHomeDirectory: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return URL(filePath: NSHomeDirectory()) }
        return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
    }
    #endif

    /// Echter Store, oder für UI-Tests einer im temporären Ordner der App.
    private static func makeBackup(_ testStore: TestStore?) -> StoreBackup {
        #if DEBUG || QUILL_SYNCTEST
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
    /// sich die App. Wirft, wenn es nicht eingespielt werden kann. Schaltet den Sync
    /// vorher aus (ADR-029): Sonst führte er den eingespielten Stand nach einem Absturz
    /// zwischen Vormerken und Ausschalten ohne Rückfrage mit dem Ordner zusammen.
    /// Scheitert das Vormerken, läuft der Sync weiter wie vorher.
    public func requestRestore(_ entry: StoreBackup.Entry) async throws {
        try await requestRestore(entry) { backup, entry in
            try await Task.detached(priority: .userInitiated) { try backup.requestRestore(entry) }.value
        }
    }

    /// `request` merkt vor; Tests prüfen damit die Reihenfolge.
    func requestRestore(
        _ entry: StoreBackup.Entry, request: (StoreBackup, StoreBackup.Entry) async throws -> Void
    ) async throws {
        guard let backup else { return }
        sync.turnOffForRestore()
        do {
            try await request(backup, entry)
        } catch {
            sync.cancelTurnOffForRestore()
            throw error
        }
    }

    /// Das Beenden wurde abgebrochen (Rückfrage bei ungespeicherten Änderungen): Ein
    /// vorgemerktes Backup würde sonst beim nächsten Start unbemerkt eingespielt.
    /// Nimmt die Vormerkung zurück und meldet es über `notify` (Titel, Text).
    public func quitWasCancelled(notify: @MainActor (String, String) -> Void = QuillPersistence.showAlert) {
        guard let backup else { return }
        do {
            guard try backup.withdrawRestoreRequest() else { return }
            sync.cancelTurnOffForRestore()
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

    /// Bilder, die seit der gewählten Frist keinem Block mehr gehören (ADR-015, 12.4),
    /// bei „Immer“ keine. Läuft nach dem Backup beim Start, damit ein versehentlich
    /// gelöschtes Bild dort noch liegt.
    @discardableResult
    func removeOrphanedAssets() -> Task<Void, Never>? {
        guard let age = imageRetention.retention.age else { return nil }
        let store = store
        return Task.detached(priority: .utility) {
            do {
                let count = try await store.removeOrphanedAssets(olderThan: age)
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
