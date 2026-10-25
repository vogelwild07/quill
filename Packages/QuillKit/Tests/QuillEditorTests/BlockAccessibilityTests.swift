#if canImport(AppKit)
import AppKit
import QuillDesign
@testable import QuillEditor
@testable import QuillEditorCore
import QuillModel
import Testing

/// VoiceOver im Editor: Checkboxen als Elemente, Bilder beschriftet, Trenner
/// übergangen, Blockart im Text der
/// Bedienungshilfen, Rotor „Überschriften“ (Befunde A1, A2 aus Phase 7.3).
@MainActor
@Suite("Editor: Bedienungshilfen", .serialized)
struct BlockAccessibilityTests {
    private let window: NSWindow
    private let editor: BlockEditorController
    private var textView: BlockTextView { editor.textView }

    init() {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        editor = BlockEditorController(document: EditorDocument(blocks: [
            EditorBlock(kind: .heading1, text: "Ziele"),
            EditorBlock(kind: .todo, text: "Milch", isChecked: true),
            EditorBlock(kind: .todo, text: ""),
            EditorBlock(kind: .numbered, text: "eins"),
            EditorBlock(kind: .numbered, text: "zwei", indent: 1),
            EditorBlock(kind: .image),
            EditorBlock(kind: .divider),
            EditorBlock(kind: .heading2, text: "Später"),
            EditorBlock(text: "Ende"),
        ]))
        window.contentView = editor.scrollView
        editor.focus()
        editor.textView.layoutSubtreeIfNeeded()
    }

    private var elements: [CheckboxAccessibilityElement] {
        (textView.accessibilityChildren() ?? []).compactMap { $0 as? CheckboxAccessibilityElement }
    }

    @Test func todosAreCheckboxes() {
        let elements = elements
        #expect(elements.map { $0.accessibilityRole() } == [.checkBox, .checkBox])
        #expect(elements.map { $0.accessibilityLabel() } == ["Milch", "To-do"])
        #expect(elements.map { $0.accessibilityValue() as? NSNumber } == [1, 0])
        #expect(elements.allSatisfy { $0.isAccessibilityEnabled() })
        #expect(elements.allSatisfy { $0.accessibilityParent() as AnyObject? === textView })
        // Dieselben Objekte bei der nächsten Abfrage, damit VoiceOver den Fokus behält.
        #expect(zip(elements, self.elements).allSatisfy { $0 === $1 })
    }

    @Test func pressingCheckboxTogglesWithUndo() throws {
        let milk = try #require(elements.first)
        #expect(milk.accessibilityPerformPress())
        #expect(editor.document[1].isChecked == false)
        #expect(milk.accessibilityValue() as? NSNumber == 0)
        textView.breakUndoCoalescing()
        textView.undoManager?.undo()
        #expect(editor.document[1].isChecked == true)
    }

    /// Bild beschriftet, Trenner für VoiceOver unsichtbar. `NSTextView` meldet beide
    /// über die Zelle ihres Attachments; dass VoiceOver sie so sieht, prüft der Audit
    /// in `AccessibilityAuditUITests`.
    @Test func imageIsLabeledAndDividerIsSkipped() throws {
        _ = textView.accessibilityChildren()
        var cells: [NSTextAttachmentCell] = []
        textView.textStorage!.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textView.textStorage!.length)) { value, _, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? NSTextAttachmentCell { cells.append(cell) }
        }
        #expect(cells.count == 2)
        let image = try #require(cells.first as? ImageAttachmentCell)
        #expect(image.isAccessibilityElement())
        #expect(image.accessibilityRole() == .image)
        #expect(image.accessibilityLabel() == "Image, loading")
        // Mit geladenem Bild: natürliche Größe in der Beschriftung.
        let assetID = UUID()
        let context = CGContext(data: nil, width: 120, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        EditorImageCache.shared.store(.init(pointSize: CGSize(width: 120, height: 60), image: context.makeImage()!), for: assetID)
        let attachment = ImageAttachment(assetID: assetID)
        let loaded = ImageAttachmentCell()
        attachment.attachmentCell = loaded
        #expect(loaded.accessibilityLabel() == "Image, 120 × 60 points")
        withExtendedLifetime(attachment) {}
        #expect(cells.last is DecorativeAttachmentCell)
        #expect(cells.last?.isAccessibilityElement() == false)
    }

    @Test func checkboxFrameIsTheDrawnCheckbox() throws {
        let milk = try #require(elements.first)
        let frame = milk.accessibilityFrame()
        let size = QuillDesign.EditorLayout.checkboxSize
        #expect(abs(frame.width - size) < 0.5 && abs(frame.height - size) < 0.5)
        let textFrame = window.convertToScreen(textView.convert(textView.bounds, to: nil))
        #expect(textFrame.contains(frame))
        // Links vom Text „Milch“.
        let milkStart = editor.paragraphRange(ofBlock: 1).location
        let line = textView.firstRect(forCharacterRange: NSRange(location: milkStart, length: 1), actualRange: nil)
        #expect(frame.maxX <= line.minX)
        #expect(frame.midY > line.minY && frame.midY < line.maxY)
    }

    @Test func accessibilityTextDescribesBlockKinds() throws {
        let full = NSRange(location: 0, length: textView.string.utf16.count)
        let text = try #require(textView.accessibilityAttributedString(for: full))
        func attribute(_ key: NSAttributedString.Key, block: Int) -> Any? {
            text.attribute(key, at: editor.paragraphRange(ofBlock: block).location, effectiveRange: nil)
        }
        #expect(attribute(.accessibilityCustomText, block: 0) as? [String] == ["Heading 1"])
        #expect(attribute(.accessibilityCustomText, block: 1) as? [String] == ["To-do, done"])
        #expect(attribute(.accessibilityCustomText, block: 2) as? [String] == ["To-do, open"])
        #expect((attribute(.accessibilityListItemPrefix, block: 1) as? NSAttributedString)?.string == "☑")
        #expect((attribute(.accessibilityListItemPrefix, block: 3) as? NSAttributedString)?.string == "1.")
        #expect((attribute(.accessibilityListItemPrefix, block: 4) as? NSAttributedString)?.string == "1.")
        #expect(attribute(.accessibilityListItemLevel, block: 4) as? Int == 1)
        #expect(attribute(.accessibilityListItemIndex, block: 4) as? Int == 3)
        #expect(attribute(.accessibilityListItemPrefix, block: 8) == nil)
        #expect(attribute(.accessibilityCustomText, block: 6) as? [String] == ["Divider Line"])
        #expect(attribute(.accessibilityCustomText, block: 8) as? [String] == ["Text"])

        // Ausschnitt: Attribute relativ zum Anfang des Bereichs.
        let todo = editor.paragraphRange(ofBlock: 2)
        let part = try #require(textView.accessibilityAttributedString(for: todo))
        #expect(part.attribute(.accessibilityCustomText, at: 0, effectiveRange: nil) as? [String] == ["To-do, open"])
    }

    @Test func headingRotorWalksHeadings() throws {
        let rotor = try #require(textView.accessibilityCustomRotors().first)
        #expect(rotor.type == .heading)
        func search(_ direction: NSAccessibilityCustomRotor.SearchDirection, from item: NSAccessibilityCustomRotor.ItemResult?, filter: String = "") -> NSAccessibilityCustomRotor.ItemResult? {
            let parameters = NSAccessibilityCustomRotor.SearchParameters()
            parameters.searchDirection = direction
            parameters.currentItem = item
            parameters.filterString = filter
            return rotor.itemSearchDelegate?.rotor(rotor, resultFor: parameters)
        }
        let first = try #require(search(.next, from: nil))
        #expect(first.customLabel == "Ziele")
        #expect(first.targetRange == NSRange(location: 0, length: 5))
        let second = try #require(search(.next, from: first))
        #expect(second.customLabel == "Später")
        #expect(search(.next, from: second) == nil)
        #expect(search(.previous, from: second)?.customLabel == "Ziele")
        #expect(search(.next, from: nil, filter: "spä")?.customLabel == "Später")
    }
}
#endif
