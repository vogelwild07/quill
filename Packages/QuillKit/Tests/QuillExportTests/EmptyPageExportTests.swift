#if canImport(AppKit)
import AppKit
import Foundation
@testable import QuillEditor
@testable import QuillEditorCore
@testable import QuillExport
import QuillModel
import SwiftData
import Testing

/// Der Hinweis auf einer leeren Seite landet nie im Export (Phase 7.3): Editor
/// zeigt ihn, Bridge speichert, Store liefert den Stand, Exporter schreibt ihn.
@MainActor
@Suite("Export: leere Seite ohne Hinweis", .serialized)
struct EmptyPageExportTests {
    @Test func exportOfEmptyPageHasNoHint() async throws {
        let store = PageStore(modelContainer: try QuillStore.makeInMemoryContainer())
        let pageID = try await store.createPage(title: "Leer")
        let bridge = EditorPersistenceBridge(pageID: pageID, store: store, delay: .seconds(60))
        let editor = BlockEditorController(document: EditorDocument())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor.scrollView
        editor.load(try await bridge.load())
        #expect(editor.textView.showsEmptyPageHint, "Vorbedingung: Hinweis sichtbar")

        // Auch nach Tippen und Löschen (dann wird der leere Absatz gespeichert).
        editor.textView.insertText("a", replacementRange: editor.textView.selectedRange())
        editor.textView.deleteBackward(nil)
        #expect(editor.textView.showsEmptyPageHint)
        bridge.documentDidChange(editor.document)
        await bridge.flush()

        let snapshot = try await store.exportSnapshot(of: pageID, includeSubpages: false)
        #expect(!snapshot.blocks.contains { $0.text.contains(BlockTextView.emptyPageHint) })
        let plan = MarkdownExporter.plan(for: snapshot, strings: MarkdownExporterTests.strings)
        let markdown = plan.files.compactMap { file -> String? in
            if case .markdown(let text) = file.content { text } else { nil }
        }
        #expect(markdown.count == 1)
        #expect(markdown.allSatisfy { !$0.contains(BlockTextView.emptyPageHint) && !$0.contains("Blockart") })
        withExtendedLifetime(window) {}
    }
}
#endif
