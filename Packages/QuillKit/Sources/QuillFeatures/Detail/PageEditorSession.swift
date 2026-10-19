#if canImport(AppKit)
import OSLog
import QuillDesign
import QuillEditor
import QuillModel
import SwiftData
import SwiftUI

/// Editor einer Seite in einem Fenster: Block-Editor, Kopf und Persistenz.
///
/// Lebt so lange wie die Seite im Fenster angezeigt wird. `close()` speichert
/// offene Änderungen (Seitenwechsel, Fenster schließen).
@MainActor
final class PageEditorSession {
    let controller = BlockEditorController(document: EditorDocument())
    let headerFocus = HeaderFocus()
    /// Beobachtbar: `lastError` zeigt den Hinweis „nicht gespeichert“.
    let bridge: EditorPersistenceBridge

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "editor")

    init(
        pageID: UUID,
        title: String,
        icon: String?,
        store: PageStore,
        context: ModelContext,
        rename: @escaping @MainActor (UUID, String) -> Void,
        setIcon: @escaping @MainActor (UUID, String?) -> Void
    ) {
        bridge = EditorPersistenceBridge(pageID: pageID, store: store)
        controller.imageStore = store
        controller.topPadding = QuillDesign.EditorLayout.pageTopPadding
        controller.isEditable = false
        let header = PageHeaderView(
            pageID: pageID,
            title: title,
            icon: icon,
            focus: headerFocus,
            rename: rename,
            setIcon: setIcon,
            submitTitle: { [weak controller] in controller?.focusStart() }
        )
        let headerView = EditorHeaderView(rootView: header.modelContext(context))
        headerView.setAccessibilityLabel(String(localized: "Seitenkopf", bundle: .module))
        controller.header = headerView
        controller.onExitTop = { [headerFocus] in headerFocus.requestTitle() }
        controller.onExitForward = { [weak controller] in WindowFocus.sidebar(in: controller?.scrollView.window) }
    }

    func load() async {
        do {
            let document = try await bridge.load()
            controller.load(document)
            controller.isEditable = true
            controller.onChange = { [bridge] in bridge.documentDidChange($0) }
            bridge.onExternalChange = { [weak controller] in controller?.reload($0) ?? false }
        } catch {
            // Ohne geladene Blöcke bleibt der Editor schreibgeschützt; so wird nichts überschrieben.
            Self.logger.error("Seite konnte nicht geladen werden: \(error, privacy: .public)")
        }
    }

    func close() {
        controller.onChange = nil
        let bridge = bridge
        Task { await bridge.flush() }
    }
}

#endif
