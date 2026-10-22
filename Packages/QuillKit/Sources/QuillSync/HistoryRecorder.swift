import Foundation
import QuillModel
import Synchronization
import os

/// Zeichnet die Geschichte jeder Seite in ihrem Sync-Dokument auf, auch ohne Sync
/// (Zeitreise, ADR-031). Nach dem Speichern im Editor (`pageSaved(_:)`) und einer
/// Pause von `quietPeriod` (spätestens nach `maxDelay`) übernimmt es die Blöcke aus
/// dem Store als Änderung ins Dokument, wie es sonst erst der nächste Abgleich täte.
/// Der Abgleich schreibt diese Änderungen dann mit in den Ordner
/// (`SyncCursors.exported`).
///
/// Läuft nicht auf dem Main Thread; dort kommt nur die Meldung an. Seiten, deren
/// lokale Änderungen schon im Ordner stehen, aber noch nicht im Store
/// (`SyncCursors.pending`), überspringt es bis zum nächsten erfolgreichen Abgleich.
public actor HistoryRecorder {
    public static let quietPeriod: Duration = .seconds(2)
    public static let maxDelay: Duration = .seconds(30)

    /// Store, dessen Seiten aufgezeichnet werden (`HistoryObserver` nimmt nur dessen Speicherungen).
    public nonisolated let store: PageStore
    private let quietPeriod: Duration
    private let maxDelay: Duration
    /// Seite → seit wann eine Speicherung auf die Aufzeichnung wartet.
    private var waitingSince: [UUID: ContinuousClock.Instant] = [:] {
        didSet { waitingPages.withLock { $0 = waitingSince.count } }
    }
    /// Anzahl in `waitingSince` für `hasWaitingPages`.
    private nonisolated let waitingPages = Mutex(0)
    private var timers: [UUID: Task<Void, Never>] = [:]
    /// Sitzung je Seite (`SyncDocument.write(as:session:)`), bis das Schreiben einmal scheitert.
    private var sessions: [UUID: UUID] = [:]

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "history")

    public init(store: PageStore, quietPeriod: Duration = HistoryRecorder.quietPeriod, maxDelay: Duration = HistoryRecorder.maxDelay) {
        self.store = store
        self.quietPeriod = quietPeriod
        self.maxDelay = maxDelay
    }

    /// Der Editor hat die Seite gespeichert.
    public func pageSaved(_ pageID: UUID) {
        let now = ContinuousClock.now
        let since = waitingSince[pageID] ?? now
        waitingSince[pageID] = since
        let deadline = min(now + quietPeriod, since + maxDelay)
        timers[pageID]?.cancel()
        timers[pageID] = Task { [weak self] in
            try? await Task.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            await self?.recordWaiting(pageID)
        }
    }

    /// Zeichnet sofort auf, was noch wartet, z. B. vor dem Beenden.
    public func flush() async {
        for pageID in waitingSince.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            await recordWaiting(pageID)
        }
    }

    /// Ob noch eine Speicherung auf die Aufzeichnung wartet; sofort, ohne auf den Actor
    /// zu warten, z. B. beim Beenden auf dem Main Thread.
    public nonisolated var hasWaitingPages: Bool { waitingPages.withLock { $0 > 0 } }

    private func recordWaiting(_ pageID: UUID) async {
        guard waitingSince.removeValue(forKey: pageID) != nil else { return }
        timers.removeValue(forKey: pageID)?.cancel()
        do {
            try await record(pageID)
        } catch {
            // Nicht wiederholen: Die nächste Speicherung zeichnet den Stand mit auf.
            Self.logger.error("Geschichte nicht aufgezeichnet: \(error, privacy: .public)")
        }
    }

    /// Übernimmt die Blöcke der Seite ins Dokument und speichert es. `true`, wenn eine
    /// Änderung dazukam.
    @discardableResult
    func record(_ pageID: UUID) async throws -> Bool {
        try await DocumentLocks.withLock(pageID) { try await recordLocked(pageID) }
    }

    private func recordLocked(_ pageID: UUID) async throws -> Bool {
        let state = try await store.syncState()
        guard SyncCursors(data: state.cursors).allowsRecording(pageID.uuidString),
              let page = try await store.syncPage(pageID)
        else { return false }
        let document = try page.document.map { try PageDocument(bytes: $0) } ?? PageDocument()
        let session = sessions[pageID] ?? UUID()
        sessions[pageID] = session
        document.write(as: state.deviceID, session: session)
        // Bilder ohne Datei im Ordner bekommen ihren Namen beim nächsten Abgleich.
        guard try document.update(to: page.blocks, assetFiles: document.assetFiles()) else { return false }
        do {
            return try await store.saveHistory(pageID, document: document.save())
        } catch {
            // Vielleicht doch gespeichert: Mit derselben Sitzung entstünde sonst eine
            // zweite, andere Änderung mit derselben Nummer.
            sessions[pageID] = nil
            throw error
        }
    }
}
