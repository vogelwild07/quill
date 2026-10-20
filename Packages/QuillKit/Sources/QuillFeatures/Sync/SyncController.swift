#if canImport(AppKit)
import AppKit
#endif
import Foundation
import Observation
import OSLog
import QuillEditorCore
import QuillModel
import QuillSync
import SwiftData

/// Wann abgeglichen wird (ADR-029): beim Start, wenn Quill aktiv wird, kurz nach jeder
/// Änderung im Store und regelmäßig für Änderungen anderer Geräte.
public struct SyncSchedule: Sendable {
    public var afterChange: Duration
    public var interval: Duration

    public init(afterChange: Duration, interval: Duration) {
        self.afterChange = afterChange
        self.interval = interval
    }

    public static let standard = SyncSchedule(afterChange: .seconds(2), interval: .seconds(60))
}

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
        /// Letzter Abgleich gescheitert, mit Meldung für den Nutzer; der nächste Abgleich
        /// versucht es wieder.
        case failed(String)
    }

    /// Wie es nach einem eingespielten Backup weitergeht (ADR-029). Der bisherige
    /// Ordner wird in keinem Fall überschrieben: Quill hängt dort nur eigene Dateien an.
    public enum Reconnect: Equatable, Sendable {
        /// Mit dem bisherigen Ordner zusammenführen. Neuere Stände aus dem Ordner
        /// kommen dabei zurück.
        case merge
        /// Mit einem neuen, leeren Ordner neu beginnen.
        case startOver(URL)
    }

    public enum EnableError: Error, Equatable {
        /// Im Ordner liegen schon Daten; „Neu beginnen“ braucht einen leeren Ordner.
        case folderNotEmpty
        /// „Neu beginnen“ mit dem bisherigen Ordner.
        case sameAsPreviousFolder
        /// Zusammenführen, aber es gibt keinen bisherigen Ordner (mehr).
        case noPreviousFolder
    }

    public private(set) var status: Status
    public private(set) var lastReport: SyncReport?
    public private(set) var lastSyncDate: Date?
    /// Abgeschlossene Abgleiche seit dem Start, für Tests der Zeitpunkte.
    private(set) var completedRuns = 0

    private let store: PageStore
    private let settings: SyncSettings
    private let backupBeforeSync: @MainActor () async throws -> URL?
    private let deviceName: String
    private let files: any SyncFileAccess
    private let onPagesChanged: @MainActor (Set<UUID>) -> Void
    private let gate: SyncGate
    private let schedule: SyncSchedule
    private var engine: (folder: URL, engine: SyncEngine)?
    private var running: Task<Void, Never>?
    private var needsAnotherRun = false
    private var pending: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var observations: [NotificationObservation] = []

    private nonisolated static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "sync")

    public init(
        store: PageStore,
        settings: SyncSettings,
        backupBeforeSync: @escaping @MainActor () async throws -> URL?,
        deviceName: String = SyncController.defaultDeviceName,
        files: any SyncFileAccess = CoordinatedFileAccess(),
        schedule: SyncSchedule = .standard,
        onPagesChanged: @escaping @MainActor (Set<UUID>) -> Void = SyncController.reloadOpenEditors
    ) {
        self.store = store
        self.settings = settings
        self.backupBeforeSync = backupBeforeSync
        self.deviceName = deviceName
        self.files = files
        self.schedule = schedule
        self.onPagesChanged = onPagesChanged
        let connection = settings.connection
        gate = SyncGate(paused: connection?.isPaused ?? false)
        status = connection == nil ? .off : (connection?.isPaused == true ? .paused : .idle)
    }

    public var isEnabled: Bool { settings.connection != nil }

    public var isSyncing: Bool {
        if case .syncing = status { true } else { false }
    }

    /// Nach einem eingespielten Backup: fragen, wie es weitergeht (`reconnect(_:)`).
    public var asksToReconnect: Bool { settings.askAfterRestore }

    /// Der verbundene Ordner, sonst `nil`.
    public var folder: URL? { settings.connection.flatMap { try? SyncFolderBookmark.resolve($0.bookmark).folder } }

    /// Der Ordner vor dem letzten Ausschalten, sonst `nil`.
    public var previousFolder: URL? {
        settings.previousConnection.flatMap { try? SyncFolderBookmark.resolve($0.bookmark).folder }
    }

    // MARK: Ein und aus

    /// Schaltet den Sync mit `folder` ein: zuerst das Backup (der Rückweg), dann eine
    /// neue Geräte-ID und die Verbindung. Den Ordner beschreibt erst `syncNow()`.
    /// Ist es der Ordner von vor dem Ausschalten, führt Quill zusammen; mit jedem
    /// anderen Ordner beginnt es dort neu und schreibt jedes Dokument samt Geschichte
    /// hinein. Gibt den Ordner des Backups zurück (`nil` bei einem Store nur im
    /// Arbeitsspeicher).
    @discardableResult
    public func enable(folder: URL) async throws -> URL? {
        let inspection = try inspect(folder)
        let previous = settings.previousConnection
        let merging = inspection.folderID != nil && inspection.folderID == previous?.folderID
        return try await connect(folder, folderID: merging ? previous?.folderID : nil, newFolder: !merging)
    }

    /// Antwort auf die Rückfrage nach einem eingespielten Backup.
    @discardableResult
    public func reconnect(_ choice: Reconnect) async throws -> URL? {
        let previous = settings.previousConnection
        switch choice {
        case .merge:
            guard let previous, let folder = try? SyncFolderBookmark.resolve(previous.bookmark).folder else {
                throw EnableError.noPreviousFolder
            }
            return try await connect(folder, folderID: previous.folderID, newFolder: false)
        case .startOver(let folder):
            let inspection = try inspect(folder)
            if let previous, inspection.folderID == previous.folderID || isSameFolder(folder, previous) {
                throw EnableError.sameAsPreviousFolder
            }
            guard inspection.isEmpty else { throw EnableError.folderNotEmpty }
            return try await connect(folder, folderID: nil, newFolder: true)
        }
    }

    /// Nach einem eingespielten Backup: Sync bleibt aus, Quill fragt nicht mehr.
    public func declineReconnect() {
        settings.askAfterRestore = false
    }

    private func connect(_ folder: URL, folderID: UUID?, newFolder: Bool) async throws -> URL? {
        let backup = try await backupBeforeSync()
        let bookmark = try withAccess(to: folder) { try SyncFolderBookmark.make(for: folder) }
        if newFolder { try await store.resetSyncCursors() }
        try await store.setSyncDeviceID(UUID())
        settings.connection = SyncConnection(bookmark: bookmark, folderID: folderID)
        settings.askAfterRestore = false
        engine = nil
        gate.resume()
        status = .idle
        return backup
    }

    private func inspect(_ folder: URL) throws -> SyncFolderInspection {
        try withAccess(to: folder) { try SyncFolderInspection.inspect(folder, files: files) }
    }

    private func isSameFolder(_ folder: URL, _ connection: SyncConnection) -> Bool {
        guard let other = try? SyncFolderBookmark.resolve(connection.bookmark).folder else { return false }
        return folder.standardizedFileURL.resolvingSymlinksInPath() == other.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Ordner aus der Dateiauswahl sind nur innerhalb dieses Zugriffs lesbar (Sandbox).
    private func withAccess<T>(to folder: URL, _ body: () throws -> T) rethrows -> T {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Schaltet den Sync aus. Store und Ordner bleiben, wie sie sind; wird derselbe
    /// Ordner wieder gewählt, führt Quill zusammen.
    public func disable() {
        gate.pause()
        pending?.cancel()
        if let connection = settings.connection {
            settings.previousConnection = connection
        }
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

    /// Das Beenden nach `turnOffForRestore()` wurde abgebrochen, das Backup ist nicht
    /// mehr vorgemerkt: weiter wie vorher, mit demselben Gerät und Ordner.
    public func cancelTurnOffForRestore() {
        guard settings.askAfterRestore, !isEnabled, let previous = settings.previousConnection else { return }
        settings.connection = previous
        settings.askAfterRestore = false
        if previous.isPaused {
            status = .paused
        } else {
            gate.resume()
            status = .idle
        }
    }

    /// Stoppt sofort jedes Schreiben in den Ordner, auch mitten im Abgleich.
    public func pause() {
        guard var connection = settings.connection else { return }
        gate.pause()
        pending?.cancel()
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

    // MARK: Zeitpunkte

    /// Gleicht ab jetzt selbst ab (`SyncSchedule`), solange der Sync an ist. Mehrfach
    /// aufrufen schadet nicht.
    public func start() {
        guard timer == nil else { return }
        observations.append(NotificationObservation(ModelContext.didSave, object: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidChange() }
        })
        #if canImport(AppKit)
        observations.append(NotificationObservation(NSApplication.didBecomeActiveNotification, object: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestSync(after: .zero) }
        })
        #endif
        let interval = schedule.interval
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await self.syncNow()
            }
        }
        requestSync(after: .zero)
    }

    /// Eigene Schreibvorgänge des Abgleichs lösen keinen weiteren aus; was der Nutzer
    /// währenddessen speichert, nimmt spätestens der regelmäßige Abgleich mit.
    private func storeDidChange() {
        guard running == nil else { return }
        requestSync(after: schedule.afterChange)
    }

    /// Ein Abgleich nach `delay`; ein schon geplanter entfällt.
    private func requestSync(after delay: Duration) {
        guard canSync else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private var canSync: Bool {
        guard let connection = settings.connection else { return false }
        return !connection.isPaused && !gate.isPaused
    }

    // MARK: Abgleich

    /// Gleicht einmal ab, wenn der Sync an und nicht pausiert ist. Läuft schon ein
    /// Abgleich, folgt einer danach; zurück kommt es, wenn beide fertig sind.
    public func syncNow() async {
        guard canSync else { return }
        if let running {
            needsAnotherRun = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                needsAnotherRun = false
                await runOnce()
            } while needsAnotherRun && canSync
            // Im selben Schritt wie die letzte Prüfung: Wer `running` noch sah, hat
            // `needsAnotherRun` vorher gesetzt.
            running = nil
        }
        running = task
        await task.value
    }

    private func runOnce() async {
        guard let connection = settings.connection, canSync else { return }
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
            lastSyncDate = .now
            completedRuns += 1
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
        status = .failed(SyncLabel.failureMessage(for: error))
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
