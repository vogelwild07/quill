import Foundation
import QuillEditorCore
import QuillModel
import QuillSync

/// Meldet dem `HistoryRecorder` jede Speicherung im Editor (ADR-031). Nur Speicherungen
/// einer `EditorPersistenceBridge` zählen; das Neuladen nach einem Abgleich (ohne
/// Absender) ist keine Änderung des Nutzers, die übernimmt der Abgleich selbst.
/// Auf dem Main Thread passiert nur das Weiterreichen, der Reihe nach.
@MainActor
public final class HistoryObserver {
    public let recorder: HistoryRecorder
    private var observation: NotificationObservation?
    private var forwarding: Task<Void, Never>?
    /// Meldungen, die noch nicht beim `HistoryRecorder` angekommen sind.
    private var unforwarded = 0

    public init(recorder: HistoryRecorder) {
        self.recorder = recorder
    }

    /// Mehrfach aufrufen schadet nicht.
    public func start() {
        guard observation == nil else { return }
        observation = NotificationObservation(EditorPersistenceBridge.didSave, object: nil) { [weak self] note in
            let pageID = note.userInfo?["pageID"] as? UUID
            let fromEditor = note.object is EditorPersistenceBridge
            let store = note.userInfo?["store"] as? PageStore
            MainActor.assumeIsolated {
                // Nur Speicherungen im eigenen Store (in Tests laufen mehrere nebeneinander).
                guard let pageID, fromEditor, let self, store === self.recorder.store else { return }
                self.pageSaved(pageID)
            }
        }
    }

    private func pageSaved(_ pageID: UUID) {
        let previous = forwarding
        let recorder = recorder
        unforwarded += 1
        forwarding = Task {
            await previous?.value
            await recorder.pageSaved(pageID)
            unforwarded -= 1
        }
    }

    /// Ob noch etwas auf die Aufzeichnung wartet. Sofort, ohne zu warten: Beim Beenden
    /// darf die App ohne offene Arbeit nicht erst einen Task brauchen, denn wer
    /// `NSApp.terminate` aus einem Task auf dem Main Actor ruft, blockiert ihn.
    public var hasUnrecordedSaves: Bool { unforwarded > 0 || recorder.hasWaitingPages }

    /// Zeichnet alles Gemeldete sofort auf, z. B. vor dem Beenden nach dem Speichern der Editoren.
    public func flush() async {
        await forwarding?.value
        await recorder.flush()
    }
}
