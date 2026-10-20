import Foundation
import Observation
import OSLog
import QuillEditorCore
import QuillModel
import QuillSync

/// Ein- und Ausschalten, Pausieren und Abgleichen des Ordner-Sync (ADR-029). Der Sync
/// ist aus, bis der Nutzer ihn einschaltet; vor dem Einschalten legt Quill ein Backup
/// an, und scheitert es, bleibt er aus. Der Abgleich läuft im Hintergrund und blockiert
/// die App nicht.
@MainActor
@Observable
public final class SyncController {
    public enum Status: Equatable, Sendable {
        case off
        case idle
        case syncing(SyncProgress)
        case paused
        /// Der Ordner enthält Quill-Daten mit dieser Ordner-ID; zusammengeführt wird erst
        /// nach `confirmFolder(_:)`.
        case needsConfirmation(UUID)
        /// Letzter Abgleich gescheitert; Beschreibung fürs Protokoll und die Anzeige in 11.4.
        case failed(String)
    }

    public private(set) var status: Status
    public private(set) var lastReport: SyncReport?

    private let store: PageStore
    private let settings: SyncSettings
    private let backupBeforeSync: @MainActor () async throws -> URL?
    private let deviceName: String
    private let files: any SyncFileAccess
    private let onPagesChanged: @MainActor (Set<UUID>) -> Void
    private let gate: SyncGate
    private var engine: (folder: URL, engine: SyncEngine)?

    private nonisolated static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "sync")

    public init(
        store: PageStore,
        settings: SyncSettings,
        backupBeforeSync: @escaping @MainActor () async throws -> URL?,
        deviceName: String = SyncController.defaultDeviceName,
        files: any SyncFileAccess = CoordinatedFileAccess(),
        onPagesChanged: @escaping @MainActor (Set<UUID>) -> Void = SyncController.reloadOpenEditors
    ) {
        self.store = store
        self.settings = settings
        self.backupBeforeSync = backupBeforeSync
        self.deviceName = deviceName
        self.files = files
        self.onPagesChanged = onPagesChanged
        let connection = settings.connection
        gate = SyncGate(paused: connection?.isPaused ?? false)
        status = connection == nil ? .off : (connection?.isPaused == true ? .paused : .idle)
    }

    public var isEnabled: Bool { settings.connection != nil }

    // MARK: Ein und aus

    /// Schaltet den Sync mit `folder` ein: zuerst das Backup (der Rückweg), dann eine
    /// neue Geräte-ID und die Verbindung. Den Ordner beschreibt erst `syncNow()`.
    /// Gibt den Ordner des Backups zurück (`nil` bei einem Store nur im Arbeitsspeicher).
    @discardableResult
    public func enable(folder: URL) async throws -> URL? {
        let backup = try await backupBeforeSync()
        let bookmark = try SyncFolderBookmark.make(for: folder)
        try await store.setSyncDeviceID(UUID())
        settings.connection = SyncConnection(bookmark: bookmark)
        settings.askAfterRestore = false
        engine = nil
        gate.resume()
        status = .idle
        return backup
    }

    /// Schaltet den Sync aus. Store und Ordner bleiben, wie sie sind.
    public func disable() {
        gate.pause()
        settings.connection = nil
        engine = nil
        status = .off
    }

    /// Vor dem Einspielen eines Backups (ADR-029): Sync aus und nach dem Neustart
    /// fragen, sonst führte der Abgleich den alten Stand gleich wieder mit dem Ordner
    /// zusammen. `true`, wenn er an war.
    @discardableResult
    public func turnOffForRestore() -> Bool {
        guard isEnabled else { return false }
        disable()
        settings.askAfterRestore = true
        return true
    }

    /// Stoppt sofort jedes Schreiben in den Ordner, auch mitten im Abgleich.
    public func pause() {
        guard var connection = settings.connection else { return }
        gate.pause()
        connection.isPaused = true
        settings.connection = connection
        status = .paused
    }

    public func resume() {
        guard var connection = settings.connection else { return }
        connection.isPaused = false
        settings.connection = connection
        gate.resume()
        status = .idle
    }

    /// Nach Rückfrage: Den Ordner mit dieser ID zusammenführen.
    public func confirmFolder(_ folderID: UUID) async {
        guard var connection = settings.connection else { return }
        connection.folderID = folderID
        settings.connection = connection
        await syncNow()
    }

    // MARK: Abgleich

    /// Gleicht einmal ab, wenn der Sync an und nicht pausiert ist.
    public func syncNow() async {
        guard let connection = settings.connection, !connection.isPaused, !gate.isPaused else { return }
        let folder: URL
        do {
            folder = try SyncFolderBookmark.resolve(connection.bookmark).folder
        } catch {
            fail(error)
            return
        }
        let engine = engine(for: folder)
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        status = .syncing(SyncProgress(done: 0, total: 0))
        do {
            let report = try await engine.sync(connectedFolderID: connection.folderID) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .syncing = self.status else { return }
                    self.status = .syncing(progress)
                }
            }
            if var current = settings.connection, current.folderID == nil {
                current.folderID = report.folderID
                settings.connection = current
            }
            lastReport = report
            status = gate.isPaused ? .paused : .idle
            if !report.changedPages.isEmpty { onPagesChanged(report.changedPages) }
        } catch SyncFailure.paused {
            status = isEnabled ? .paused : .off
        } catch SyncFailure.unknownFolder(let id) {
            status = .needsConfirmation(id)
        } catch {
            fail(error)
        }
    }

    private func engine(for folder: URL) -> SyncEngine {
        if let engine, engine.folder == folder { return engine.engine }
        let created = SyncEngine(store: store, folder: folder, gate: gate, deviceName: deviceName, files: files)
        engine = (folder, created)
        return created
    }

    private func fail(_ error: any Error) {
        Self.logger.error("Abgleich gescheitert: \(error, privacy: .public)")
        status = .failed(String(describing: error))
    }

    // MARK: Standardwerte

    public static var defaultDeviceName: String {
        #if canImport(AppKit)
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }

    /// Offene Editoren laden geänderte Seiten neu, wie bei Änderungen aus einem anderen
    /// Fenster (ADR-012), außer sie haben ungespeicherte Eingaben.
    public static func reloadOpenEditors(_ pages: Set<UUID>) {
        for page in pages {
            NotificationCenter.default.post(name: EditorPersistenceBridge.didSave, object: nil, userInfo: ["pageID": page])
        }
    }
}
