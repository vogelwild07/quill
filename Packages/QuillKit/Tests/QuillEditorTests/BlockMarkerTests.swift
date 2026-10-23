#if canImport(AppKit)
import AppKit
@testable import QuillEditor
@testable import QuillEditorCore
import QuillModel
import QuillTestFixtures
import Testing

/// Zeichen am rechten Rand (11.6, 15.4): Konflikt aus dem Abgleich, „wiederhergestellt“ und Erinnerung,
/// gezeichnet, klickbar, für VoiceOver ein Knopf; „Markierung entfernen“ mit Undo.
@MainActor
@Suite("Editor: Zeichen für Konflikt und wiederhergestellt", .serialized, .renderingLock)
struct BlockMarkerTests {
    private let window: NSWindow
    private let editor: BlockEditorController
    private let restored = EditorBlock(text: "Behalten", properties: BlockProperties(isRestored: true))
    private let plain = EditorBlock(kind: .todo, text: "Umstritten")
    private let other = EditorBlock(text: "Ohne Zeichen")
    private var textView: BlockTextView { editor.textView }

    init() {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        editor = BlockEditorController(document: EditorDocument(blocks: [restored, plain, other]))
        window.contentView = editor.scrollView
        editor.textView.layoutSubtreeIfNeeded()
    }

    private var markers: [MarkerAccessibilityElement] {
        (textView.accessibilityChildren() ?? []).compactMap { $0 as? MarkerAccessibilityElement }
    }

    @Test func markersAreButtonsInDocumentOrder() {
        #expect(markers.map(\.blockID) == [restored.id])
        #expect(markers.map { $0.accessibilityIdentifier() } == ["editor.marker.restored"])
        editor.conflictBlocks = [plain.id]
        let elements = markers
        #expect(elements.map(\.blockID) == [restored.id, plain.id])
        #expect(elements.map { $0.accessibilityIdentifier() } == ["editor.marker.restored", "editor.marker.conflict"])
        #expect(elements.allSatisfy { $0.accessibilityRole() == .button && $0.isAccessibilityEnabled() })
        #expect(elements.last?.accessibilityLabel() == "Zwei Fassungen nach dem Abgleich, zum Wählen klicken: Umstritten")
        #expect(zip(elements, markers).allSatisfy { $0 === $1 })
        // Ein Konflikt geht vor „wiederhergestellt“.
        editor.conflictBlocks = [restored.id]
        #expect(markers.map { $0.accessibilityIdentifier() } == ["editor.marker.conflict"])
    }

    /// Erinnerung (15.4) nach Konflikt und „wiederhergestellt“.
    @Test func reminderMarkerComesLast() throws {
        editor.reminderBlocks = [restored.id, plain.id]
        #expect(markers.map { $0.accessibilityIdentifier() } == ["editor.marker.restored", "editor.marker.reminder"])
        #expect(markers.last?.accessibilityLabel() == "Erinnerung geplant, zum Ansehen klicken: Umstritten")
        #expect(try drawnMarkers() == [.restored, .reminder, nil])
        editor.conflictBlocks = [plain.id]
        #expect(markers.map { $0.accessibilityIdentifier() } == ["editor.marker.restored", "editor.marker.conflict"])
        #expect(try drawnMarkers() == [.restored, .conflict, nil])
    }

    /// Was das Fragment jedes Blocks zeichnet.
    private func drawnMarkers() throws -> [BlockMarker?] {
        try [restored, plain, other].map { block in
            let frame = try #require(textView.markerViewFrame(ofBlock: block.id))
            return textView.fragment(atViewPoint: CGPoint(x: textView.textContainerOrigin.x + 1, y: frame.midY))?.marker
        }
    }

    @Test func pressAndClickAskForThePopoverOfThatBlock() throws {
        editor.conflictBlocks = [plain.id]
        var asked: [(UUID, BlockMarker)] = []
        editor.markerPopoverContent = { id, marker in
            asked.append((id, marker))
            return nil
        }
        _ = try #require(markers.last).accessibilityPerformPress()
        let frame = try #require(textView.markerViewFrame(ofBlock: restored.id))
        // Rechts neben der Textspalte, nicht im Text.
        #expect(frame.minX > textView.bounds.width - textView.textContainerInset.width)
        _ = textView.handleMarkerClick(at: CGPoint(x: frame.midX, y: frame.midY))
        // Ein Klick in den Text trifft kein Zeichen.
        #expect(!textView.handleMarkerClick(at: CGPoint(x: textView.textContainerOrigin.x + 20, y: frame.midY)))
        #expect(asked.map(\.0) == [plain.id, restored.id])
        #expect(asked.map(\.1) == [.conflict, .restored])
    }

    @Test func clearingTheRestoredMarkIsOneUndoStep() {
        editor.focus()
        editor.clearRestored(blockID: restored.id)
        #expect(editor.document[0].isRestored == false)
        #expect(markers.isEmpty)
        #expect(textView.undoManager?.undoActionName == "Markierung entfernen")
        textView.undoManager?.undo()
        #expect(editor.document[0].isRestored == true)
        #expect(editor.document[0].text == "Behalten")
        // Ohne Marke ändert sich nichts.
        let before = editor.document
        editor.clearRestored(blockID: other.id)
        #expect(editor.document == before)
    }

    @Test(arguments: [(NSAppearance.Name.aqua, false), (.darkAqua, false), (.aqua, true), (.darkAqua, true)])
    func markersAreDrawnInBothAppearances(_ appearance: NSAppearance.Name, reminder: Bool) throws {
        window.appearance = NSAppearance(named: appearance)
        if reminder {
            editor.reminderBlocks = [plain.id]
        } else {
            editor.conflictBlocks = [plain.id]
        }
        textView.layoutSubtreeIfNeeded()
        let image = try Bitmap(textView, scale: 1)
        try image.writePNG(named: "markers-\(reminder ? "reminder-" : "")\(appearance.rawValue)")
        let background = image.luminance(atX: image.width - 4, y: image.height - 4)
        for block in [restored.id, plain.id, other.id] {
            let rect = try #require(textView.markerViewFrame(ofBlock: block)).integral
            var strongest = 0.0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    strongest = max(strongest, abs(image.luminance(atX: x, y: y) - background))
                }
            }
            if block == other.id {
                #expect(strongest < 0.02, "Zeichen ohne Grund")
            } else {
                #expect(strongest > 0.2, "Zeichen fehlt oder zu blass: \(strongest)")
            }
        }
    }
}
#endif
