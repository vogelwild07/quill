#if canImport(AppKit)
import OSLog
import QuillDesign
import QuillEditor
import QuillEditorCore
import QuillModel
import SwiftUI

/// Eine Präsentation (18.2, ADR-035): Folien aus dem Stand beim Start, gezeigt im
/// Lesemodus ohne Schreibmarke. Schreibt nichts.
@MainActor
@Observable
final class PresentationModel {
    enum Phase: Equatable {
        case loading, ready, failed
    }

    private(set) var phase = Phase.loading
    private(set) var slides: [[EditorBlock]] = []
    private(set) var index = 0

    @ObservationIgnored let controller = BlockEditorController(document: EditorDocument())
    @ObservationIgnored private let pageID: UUID
    @ObservationIgnored private let store: PageStore

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "presentation")

    init(pageID: UUID, store: PageStore) {
        self.pageID = pageID
        self.store = store
        controller.imageStore = store
        controller.topPadding = QuillDesign.EditorLayout.pageTopPadding
        controller.isEditable = false
        controller.isSelectable = false
    }

    /// Speichert offene Änderungen der Seite und liest sie einmal.
    func load(title: String) async {
        await EditorPersistenceBridge.flushAll(pageID: pageID)
        do {
            let blocks = try await store.blocks(of: pageID).map(EditorBlock.init(snapshot:))
            slides = SlideDeck.slides(title: title, blocks: blocks)
            phase = .ready
            display(0)
        } catch {
            Self.logger.error("Seite für die Präsentation nicht lesbar: \(error, privacy: .public)")
            phase = .failed
        }
    }

    /// Bleibt an den Enden stehen.
    func show(_ newIndex: Int) {
        guard !slides.isEmpty else { return }
        let clamped = min(max(newIndex, 0), slides.count - 1)
        guard clamped != index else { return }
        display(clamped)
    }

    func next() { show(index + 1) }
    func previous() { show(index - 1) }
    func first() { show(0) }
    func last() { show(slides.count - 1) }

    /// Blättert; Esc behandelt die Ansicht (sie schließt das Fenster).
    func handle(_ key: PresentationKeys.Key) {
        switch key {
        case .next: next()
        case .previous: previous()
        case .first: first()
        case .last: last()
        case .close: break
        }
    }

    /// Jede Folie beginnt oben, auch wenn die vorige heruntergescrollt war.
    private func display(_ newIndex: Int) {
        index = newIndex
        controller.load(EditorDocument(blocks: slides[newIndex]))
        controller.scrollView.contentView.scroll(to: .zero)
        controller.scrollView.reflectScrolledClipView(controller.scrollView.contentView)
    }

    /// Vergrößert den Editor passend zur Breite des Fensters.
    func fit(width: CGFloat) {
        controller.scrollView.magnification = Self.magnification(forWidth: width)
    }

    /// Füllt die Breite, ohne über `maxMagnification` hinaus zu wachsen.
    nonisolated static func magnification(forWidth width: CGFloat) -> CGFloat {
        min(max(width / QuillDesign.Presentation.columnWidth, 1), QuillDesign.Presentation.maxMagnification)
    }
}
#endif
