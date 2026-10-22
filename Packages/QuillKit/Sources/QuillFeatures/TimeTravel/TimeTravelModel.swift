#if canImport(AppKit)
import OSLog
import QuillDesign
import QuillEditor
import QuillEditorCore
import QuillModel
import QuillSync
import SwiftUI

/// Zeitreise einer Seite (12.3, ADR-031): Tage mit dem Stand an ihrem Ende, der gewählte
/// Tag schreibgeschützt im Block-Editor, markierte Absätze zurückholen.
@MainActor
@Observable
final class TimeTravelModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed
    }

    let pageID: UUID
    /// Neuester zuerst.
    private(set) var days: [HistoryDay] = []
    var selectedDay: HistoryDay? {
        didSet { if selectedDay != oldValue { showSelectedDay() } }
    }
    private(set) var phase = Phase.loading
    /// Im gezeigten Stand ist Text markiert.
    private(set) var canRestore = false
    /// Letztes Zurückholen ist gescheitert (Hinweis im Fenster).
    private(set) var restoreFailed = false
    /// Bild-Blöcke, die das letzte Zurückholen ausgelassen hat, weil ihr Bild nicht mehr
    /// aufbewahrt wird (Frist, 12.4): Ein leerer Bild-Block hülfe niemandem.
    private(set) var skippedImages = 0

    @ObservationIgnored let controller = BlockEditorController(document: EditorDocument())
    @ObservationIgnored private var history: PageHistory?
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let recordPending: @MainActor () async -> Void
    /// Bridge der letzten Rückholung. Bleibt am Leben, damit sie nach einem gescheiterten
    /// Speichern weiter versucht und das Beenden nachfragt (`QuitGuard`).
    @ObservationIgnored private var restoreBridge: EditorPersistenceBridge?

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "history")

    /// `recordPending` zeichnet auf, was noch wartet, damit „Heute“ den jetzigen Stand zeigt.
    init(pageID: UUID, store: PageStore, recordPending: @escaping @MainActor () async -> Void) {
        self.pageID = pageID
        self.store = store
        self.recordPending = recordPending
        controller.imageStore = store
        controller.topPadding = QuillDesign.EditorLayout.pageTopPadding
        controller.isReadOnly = true
        controller.onSelectionChange = { [weak self] in
            guard let self else { return }
            canRestore = !controller.selectedBlockIDs.isEmpty
        }
    }

    func load() async {
        await EditorPersistenceBridge.flushAll(pageID: pageID)
        await recordPending()
        do {
            let history = try await PageHistory.load(pageID, from: store)
            self.history = history
            let previous = selectedDay?.day
            days = history.days.reversed()
            selectedDay = days.first { $0.day == previous } ?? days.first
            phase = .ready
        } catch {
            Self.logger.error("Geschichte nicht lesbar: \(error, privacy: .public)")
            phase = .failed
        }
    }

    private func showSelectedDay() {
        guard let history, let selectedDay else { return }
        do {
            let blocks = try history.blocks(on: selectedDay)
            controller.load(EditorDocument(blocks: blocks.map(EditorBlock.init(snapshot:))))
        } catch {
            Self.logger.error("Tag nicht lesbar: \(error, privacy: .public)")
            controller.load(EditorDocument())
        }
    }

    /// Holt die markierten Absätze in die Seite zurück, über eine eigene
    /// `EditorPersistenceBridge` wie jede Bearbeitung: Offene Editoren der Seite laden
    /// neu oder führen zusammen (ADR-013), und die Rückholung kommt in die Geschichte.
    func restoreSelection() async {
        await restore(Set(controller.selectedBlockIDs))
    }

    /// Holt die Blöcke `chosen` des gezeigten Tages zurück.
    func restore(_ chosen: Set<UUID>) async {
        guard !chosen.isEmpty else { return }
        let old = controller.document.blocks
        var chosen = chosen
        skippedImages = 0
        for block in old where chosen.contains(block.id) {
            guard let asset = block.properties.assetID, (try? await store.imageData(asset)) == nil else { continue }
            chosen.remove(block.id)
            skippedImages += 1
        }
        guard !chosen.isEmpty else { return }
        let bridge = EditorPersistenceBridge(pageID: pageID, store: store)
        do {
            // `load()` speichert vorher eine ältere, noch offene Rückholung derselben Seite.
            var document = try await bridge.load()
            restoreBridge = bridge
            document.restore(chosen, from: old)
            bridge.documentDidChange(document)
            restoreFailed = !(await bridge.flush())
        } catch {
            Self.logger.error("Zurückholen gescheitert: \(error, privacy: .public)")
            restoreFailed = true
        }
        await load()
    }
}
#endif
